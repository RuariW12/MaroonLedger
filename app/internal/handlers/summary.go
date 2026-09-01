package handlers

import (
	"database/sql"
	"log"
	"math"
	"net/http"
	"strconv"
	"time"

	"github.com/RuariW12/MaroonLedger/internal/models"
)

type SummaryHandler struct {
	DB *sql.DB
}

// defaultSummaryDays is the window the dashboard shows when none is requested.
const defaultSummaryDays = 90

// maxSummaryDays bounds the window so a caller cannot ask the database to
// aggregate an unbounded range.
const maxSummaryDays = 1095

type summaryResponse struct {
	NetBalance   float64           `json:"net_balance"`
	TotalInflow  float64           `json:"total_inflow"`
	TotalOutflow float64           `json:"total_outflow"`
	SavingsRate  float64           `json:"savings_rate"`
	PeriodStart  string            `json:"period_start"`
	PeriodEnd    string            `json:"period_end"`
	Accounts     []accountSummary  `json:"accounts"`
	BalanceSerie []balancePoint    `json:"balance_series"`
	ByCategory   []categoryBucket  `json:"by_category"`
	Anomalies    []anomalyHeadline `json:"anomalies"`
}

type accountSummary struct {
	models.Account
	// Sparkline is the account's balance at the end of each day in the window,
	// ready to plot without further work in the browser.
	Sparkline []float64 `json:"sparkline"`
}

type balancePoint struct {
	Date    string  `json:"date"`
	Balance float64 `json:"balance"`
}

type anomalyHeadline struct {
	ID          int     `json:"id"`
	AccountID   int     `json:"account_id"`
	AccountName string  `json:"account_name"`
	Description string  `json:"description"`
	Amount      float64 `json:"amount"`
	Severity    string  `json:"severity"`
	Reason      string  `json:"reason"`
	Date        string  `json:"date"`
}

// Get returns everything the dashboard renders in a single round trip.
//
// The alternative (the browser fetching accounts, then each account's
// transactions, then deriving series client-side) is one request per account
// and puts the balance arithmetic in the least testable place. The aggregation
// belongs next to the data.
func (h *SummaryHandler) Get(w http.ResponseWriter, r *http.Request) {
	userID, ok := currentUser(w, r)
	if !ok {
		return
	}

	days := defaultSummaryDays
	if raw := r.URL.Query().Get("days"); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err != nil || parsed < 1 || parsed > maxSummaryDays {
			http.Error(w, "days must be between 1 and 1095", http.StatusBadRequest)
			return
		}
		days = parsed
	}

	end := time.Now()
	start := end.AddDate(0, 0, -days)

	accounts, err := h.accounts(r, userID)
	if err != nil {
		http.Error(w, "Failed to load accounts", http.StatusInternalServerError)
		log.Printf("summary: load accounts: %v", err)
		return
	}

	resp := summaryResponse{
		PeriodStart: start.Format(time.DateOnly),
		PeriodEnd:   end.Format(time.DateOnly),
		Accounts:    make([]accountSummary, 0, len(accounts)),
		Anomalies:   []anomalyHeadline{},
	}

	for _, a := range accounts {
		resp.NetBalance += a.Balance
	}

	// Daily net movement per account, which both series are derived from.
	deltas, err := h.dailyDeltas(r, userID, start)
	if err != nil {
		http.Error(w, "Failed to load activity", http.StatusInternalServerError)
		log.Printf("summary: daily deltas: %v", err)
		return
	}

	dayCount := days + 1
	timeline := make([]time.Time, dayCount)
	base := time.Date(start.Year(), start.Month(), start.Day(), 0, 0, 0, 0, time.UTC)
	for i := range timeline {
		timeline[i] = base.AddDate(0, 0, i)
	}

	// Per-account sparklines, plus the aggregate series summed across accounts.
	aggregate := make([]float64, dayCount)
	for _, a := range accounts {
		series := balanceSeries(a.Balance, deltas[a.ID], timeline)
		for i, v := range series {
			aggregate[i] += v
		}
		resp.Accounts = append(resp.Accounts, accountSummary{Account: a, Sparkline: series})
	}

	resp.BalanceSerie = make([]balancePoint, dayCount)
	for i, t := range timeline {
		resp.BalanceSerie[i] = balancePoint{
			Date:    t.Format(time.DateOnly),
			Balance: round2(aggregate[i]),
		}
	}

	resp.ByCategory, err = categoryOutflow(r.Context(), h.DB, userID, start, end)
	if err != nil {
		http.Error(w, "Failed to summarize categories", http.StatusInternalServerError)
		log.Printf("summary: categories: %v", err)
		return
	}

	resp.TotalInflow, resp.TotalOutflow, err = cashflow(r.Context(), h.DB, userID, start, end)
	if err != nil {
		http.Error(w, "Failed to summarize cash flow", http.StatusInternalServerError)
		log.Printf("summary: cashflow: %v", err)
		return
	}

	if err := h.anomalies(r, userID, start, &resp); err != nil {
		http.Error(w, "Failed to load anomalies", http.StatusInternalServerError)
		log.Printf("summary: anomalies: %v", err)
		return
	}

	// Savings rate is only meaningful against income. With no inflow the ratio
	// is undefined rather than zero, so it is reported as zero and the UI shows
	// a dash.
	if resp.TotalInflow > 0 {
		resp.SavingsRate = round2((resp.TotalInflow - resp.TotalOutflow) / resp.TotalInflow * 100)
	}
	resp.NetBalance = round2(resp.NetBalance)

	writeJSON(w, http.StatusOK, resp)
}

func (h *SummaryHandler) accounts(r *http.Request, userID string) ([]models.Account, error) {
	rows, err := h.DB.QueryContext(r.Context(),
		"SELECT "+accountColumns+" FROM accounts WHERE user_id = $1 ORDER BY id", userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.Account
	for rows.Next() {
		var a models.Account
		if err := rows.Scan(&a.ID, &a.Name, &a.Type, &a.Balance, &a.CreatedAt, &a.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

// dailyDeltas returns net movement per account per day, keyed by account then
// by date, for everything on or after start.
func (h *SummaryHandler) dailyDeltas(r *http.Request, userID string, start time.Time) (map[int]map[string]float64, error) {
	rows, err := h.DB.QueryContext(r.Context(), `
		SELECT t.account_id, DATE(t.date), COALESCE(SUM(t.amount), 0)
		FROM transactions t
		JOIN accounts a ON a.id = t.account_id
		WHERE a.user_id = $1 AND t.date >= $2
		GROUP BY t.account_id, DATE(t.date)`, userID, start)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	deltas := map[int]map[string]float64{}
	for rows.Next() {
		var accountID int
		var day time.Time
		var amount float64
		if err := rows.Scan(&accountID, &day, &amount); err != nil {
			return nil, err
		}
		if deltas[accountID] == nil {
			deltas[accountID] = map[string]float64{}
		}
		deltas[accountID][day.Format(time.DateOnly)] = amount
	}
	return deltas, rows.Err()
}

// balanceSeries reconstructs the end-of-day balance across the timeline.
//
// Only the current balance is stored, so history is derived by walking
// backwards from today and undoing each day's movement. Going forwards from
// zero would plot cumulative movement, not balance, and would disagree with the
// figure shown on the account.
func balanceSeries(current float64, deltas map[string]float64, timeline []time.Time) []float64 {
	series := make([]float64, len(timeline))
	running := current

	for i := len(timeline) - 1; i >= 0; i-- {
		series[i] = round2(running)
		running -= deltas[timeline[i].Format(time.DateOnly)]
	}
	return series
}

// anomalies returns the transactions worth surfacing on the dashboard: the
// partial index on (account_id, anomaly_severity) covers exactly this filter.
func (h *SummaryHandler) anomalies(r *http.Request, userID string, start time.Time, resp *summaryResponse) error {
	rows, err := h.DB.QueryContext(r.Context(), `
		SELECT t.id, t.account_id, a.name, t.description, t.amount,
		       t.anomaly_severity, COALESCE(t.anomaly_reason, ''), t.date
		FROM transactions t
		JOIN accounts a ON a.id = t.account_id
		WHERE a.user_id = $1
		  AND t.date >= $2
		  AND t.anomaly_severity IN ('medium', 'high')
		ORDER BY
		  CASE t.anomaly_severity WHEN 'high' THEN 0 ELSE 1 END,
		  ABS(t.amount) DESC
		LIMIT 5`, userID, start)
	if err != nil {
		return err
	}
	defer rows.Close()

	for rows.Next() {
		var a anomalyHeadline
		var date time.Time
		if err := rows.Scan(&a.ID, &a.AccountID, &a.AccountName, &a.Description,
			&a.Amount, &a.Severity, &a.Reason, &date); err != nil {
			return err
		}
		a.Date = date.Format(time.DateOnly)
		resp.Anomalies = append(resp.Anomalies, a)
	}
	return rows.Err()
}

// round2 keeps currency values off binary-floating-point artefacts like
// 4199.999999999999 when they reach the client.
func round2(f float64) float64 {
	return math.Round(f*100) / 100
}
