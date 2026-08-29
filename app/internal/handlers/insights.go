package handlers

import (
	"database/sql"
	"errors"
	"log"
	"math"
	"net/http"
	"time"

	"github.com/RuariW12/MaroonLedger/internal/ai"
	"github.com/RuariW12/MaroonLedger/internal/auth"
)

type InsightsHandler struct {
	DB *sql.DB
	AI ai.Provider
}

// defaultInsightWindow is the period analysed when the caller does not specify
// one.
const defaultInsightWindow = 90 * 24 * time.Hour

type insightsResponse struct {
	Summary         string             `json:"summary"`
	Observations    []string           `json:"observations"`
	Recommendations []string           `json:"recommendations"`
	Provider        string             `json:"provider"`
	PeriodStart     string             `json:"period_start"`
	PeriodEnd       string             `json:"period_end"`
	TotalInflow     float64            `json:"total_inflow"`
	TotalOutflow    float64            `json:"total_outflow"`
	ByCategory      []categoryBreakout `json:"by_category"`
}

type categoryBreakout struct {
	Category string  `json:"category"`
	Count    int     `json:"count"`
	Total    float64 `json:"total"`
}

// Generate analyses the authenticated user's spending over a period.
//
// Only aggregates leave the database for the model: category totals and counts,
// never descriptions, account names, or ids. That keeps the data sent to
// Bedrock to the minimum the task actually needs.
func (h *InsightsHandler) Generate(w http.ResponseWriter, r *http.Request) {
	userID, ok := currentUser(w, r)
	if !ok {
		return
	}

	end := time.Now()
	start := end.Add(-defaultInsightWindow)

	if raw := r.URL.Query().Get("from"); raw != "" {
		parsed, err := time.Parse(time.DateOnly, raw)
		if err != nil {
			http.Error(w, "Invalid 'from' date, use YYYY-MM-DD", http.StatusBadRequest)
			return
		}
		start = parsed
	}
	if raw := r.URL.Query().Get("to"); raw != "" {
		parsed, err := time.Parse(time.DateOnly, raw)
		if err != nil {
			http.Error(w, "Invalid 'to' date, use YYYY-MM-DD", http.StatusBadRequest)
			return
		}
		end = parsed
	}
	if !start.Before(end) {
		http.Error(w, "'from' must be earlier than 'to'", http.StatusBadRequest)
		return
	}

	summary, breakout, err := h.summarise(r, userID, start, end)
	if err != nil {
		http.Error(w, "Failed to summarise spending", http.StatusInternalServerError)
		log.Printf("Error summarising spending: %v", err)
		return
	}

	result, err := h.AI.GenerateInsights(r.Context(), summary)
	if err != nil {
		// The model is a dependency of this endpoint specifically, so unlike
		// transaction enrichment there is nothing to degrade to. Report it
		// honestly rather than inventing a summary.
		if errors.Is(err, ai.ErrUnavailable) {
			http.Error(w, "Insight generation is temporarily unavailable", http.StatusServiceUnavailable)
		} else {
			http.Error(w, "Failed to generate insights", http.StatusInternalServerError)
		}
		log.Printf("Error generating insights: %v", err)
		return
	}

	writeJSON(w, http.StatusOK, insightsResponse{
		Summary:         result.Summary,
		Observations:    result.Observations,
		Recommendations: result.Recommendations,
		Provider:        h.AI.Name(),
		PeriodStart:     start.Format(time.DateOnly),
		PeriodEnd:       end.Format(time.DateOnly),
		TotalInflow:     summary.TotalInflow,
		TotalOutflow:    summary.TotalOutflow,
		ByCategory:      breakout,
	})
}

func (h *InsightsHandler) summarise(r *http.Request, userID string, start, end time.Time) (ai.SpendingSummary, []categoryBreakout, error) {
	// The join on accounts is what scopes this to the caller. Transactions
	// carry no user_id of their own, so ownership is always established
	// through the account that holds them.
	rows, err := h.DB.QueryContext(r.Context(), `
		SELECT t.category, COUNT(*), COALESCE(SUM(t.amount), 0)
		FROM transactions t
		JOIN accounts a ON a.id = t.account_id
		WHERE a.user_id = $1 AND t.date >= $2 AND t.date < $3
		GROUP BY t.category
		ORDER BY SUM(ABS(t.amount)) DESC`, userID, start, end)
	if err != nil {
		return ai.SpendingSummary{}, nil, err
	}
	defer rows.Close()

	summary := ai.SpendingSummary{
		PeriodStart: start,
		PeriodEnd:   end,
		Currency:    "USD",
	}
	breakout := []categoryBreakout{}

	for rows.Next() {
		var c categoryBreakout
		if err := rows.Scan(&c.Category, &c.Count, &c.Total); err != nil {
			return ai.SpendingSummary{}, nil, err
		}
		breakout = append(breakout, c)

		if c.Total >= 0 {
			summary.TotalInflow += c.Total
		} else {
			summary.TotalOutflow += math.Abs(c.Total)
		}
		summary.ByCategory = append(summary.ByCategory, ai.CategorySpend{
			Category: c.Category, Count: c.Count, Total: c.Total,
		})
	}
	if err := rows.Err(); err != nil {
		return ai.SpendingSummary{}, nil, err
	}

	return summary, breakout, nil
}

// Me returns the caller's own identity, so the frontend can render who is
// signed in without decoding the token itself.
func Me(w http.ResponseWriter, r *http.Request) {
	claims, ok := auth.ClaimsFrom(r.Context())
	if !ok {
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"sub":      claims.Subject,
		"username": claims.Username,
		"groups":   claims.Groups,
	})
}
