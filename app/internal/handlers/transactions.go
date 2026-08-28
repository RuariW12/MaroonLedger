package handlers

import (
	"context"
	"database/sql"
	"log"
	"math"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/RuariW12/MaroonLedger/internal/ai"
	"github.com/RuariW12/MaroonLedger/internal/models"
	"github.com/RuariW12/MaroonLedger/internal/pipeline"
)

type TransactionHandler struct {
	DB *sql.DB
	AI ai.Provider
	// Emitter publishes committed transactions to the analytics lake. Never
	// nil in production wiring -- it is the no-op emitter when the pipeline is
	// disabled -- but guarded anyway so a zero-value handler is safe in tests.
	Emitter pipeline.Emitter
}

const transactionColumns = "id, account_id, amount, category, description, date, created_at, " +
	"auto_categorized, anomaly_severity, anomaly_reason, ai_provider"

// enrichmentTimeout bounds how long a write waits on the model. Enrichment is
// an enhancement, so exceeding it drops the analysis rather than the write.
const enrichmentTimeout = 15 * time.Second

func (h *TransactionHandler) ListByAccount(w http.ResponseWriter, r *http.Request) {
	userID, ok := currentUser(w, r)
	if !ok {
		return
	}

	accountID, err := strconv.Atoi(r.PathValue("accountId"))
	if err != nil {
		http.Error(w, "Invalid account ID", http.StatusBadRequest)
		return
	}

	// Confirm ownership before returning anything. Without this, any
	// authenticated user could read any account's transactions by id.
	if _, err := accountOwnedBy(h.DB, accountID, userID); err == sql.ErrNoRows {
		http.Error(w, "Account not found", http.StatusNotFound)
		return
	} else if err != nil {
		http.Error(w, "Failed to query account", http.StatusInternalServerError)
		log.Printf("Error checking account ownership: %v", err)
		return
	}

	rows, err := h.DB.Query(
		"SELECT "+transactionColumns+" FROM transactions WHERE account_id = $1 ORDER BY date DESC, id DESC",
		accountID,
	)
	if err != nil {
		http.Error(w, "Failed to query transactions", http.StatusInternalServerError)
		log.Printf("Error querying transactions: %v", err)
		return
	}
	defer rows.Close()

	transactions := []models.Transaction{}
	for rows.Next() {
		var t models.Transaction
		if err := rows.Scan(&t.ID, &t.AccountID, &t.Amount, &t.Category, &t.Description,
			&t.Date, &t.CreatedAt, &t.AutoCategorized, &t.AnomalySeverity, &t.AnomalyReason, &t.AIProvider); err != nil {
			http.Error(w, "Failed to scan transaction", http.StatusInternalServerError)
			log.Printf("Error scanning transaction: %v", err)
			return
		}
		transactions = append(transactions, t)
	}
	if err := rows.Err(); err != nil {
		http.Error(w, "Failed to read transactions", http.StatusInternalServerError)
		log.Printf("Error iterating transactions: %v", err)
		return
	}

	writeJSON(w, http.StatusOK, transactions)
}

func (h *TransactionHandler) Create(w http.ResponseWriter, r *http.Request) {
	userID, ok := currentUser(w, r)
	if !ok {
		return
	}

	accountID, err := strconv.Atoi(r.PathValue("accountId"))
	if err != nil {
		http.Error(w, "Invalid account ID", http.StatusBadRequest)
		return
	}

	accountType, err := accountOwnedBy(h.DB, accountID, userID)
	if err == sql.ErrNoRows {
		http.Error(w, "Account not found", http.StatusNotFound)
		return
	} else if err != nil {
		http.Error(w, "Failed to query account", http.StatusInternalServerError)
		log.Printf("Error checking account ownership: %v", err)
		return
	}

	var input struct {
		Amount      float64 `json:"amount"`
		Category    string  `json:"category"`
		Description string  `json:"description"`
		Date        string  `json:"date"`
	}
	if !decodeJSON(w, r, &input) {
		return
	}

	// NaN and ±Inf survive JSON decoding into float64 in some encoders and
	// poison every downstream aggregate, so reject them at the boundary.
	if math.IsNaN(input.Amount) || math.IsInf(input.Amount, 0) {
		http.Error(w, "Amount must be a finite number", http.StatusBadRequest)
		return
	}

	input.Description = strings.TrimSpace(input.Description)
	if len(input.Description) > 255 {
		http.Error(w, "Description must be 255 characters or fewer", http.StatusBadRequest)
		return
	}

	date := time.Now()
	if input.Date != "" {
		parsed, err := time.Parse(time.DateOnly, input.Date)
		if err != nil {
			http.Error(w, "Invalid date format, use YYYY-MM-DD", http.StatusBadRequest)
			return
		}
		date = parsed
	}

	category := strings.TrimSpace(strings.ToLower(input.Category))
	enriched := h.enrich(r.Context(), accountID, accountType, input.Amount, input.Description, category)

	needCategory := category == ""
	autoCategorized := false
	if needCategory {
		if enriched.category != "" {
			category = enriched.category
			autoCategorized = true
		} else {
			// Model unavailable and the user gave nothing: store a neutral
			// value rather than failing a write that is otherwise valid.
			category = string(ai.CategoryOther)
		}
	}

	var t models.Transaction
	err = h.DB.QueryRow(
		`INSERT INTO transactions
		   (account_id, amount, category, description, date, auto_categorized, anomaly_severity, anomaly_reason, ai_provider)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		 RETURNING `+transactionColumns,
		accountID, input.Amount, category, input.Description, date,
		autoCategorized, enriched.severity, enriched.reason, enriched.provider,
	).Scan(&t.ID, &t.AccountID, &t.Amount, &t.Category, &t.Description, &t.Date, &t.CreatedAt,
		&t.AutoCategorized, &t.AnomalySeverity, &t.AnomalyReason, &t.AIProvider)
	if err != nil {
		http.Error(w, "Failed to create transaction", http.StatusInternalServerError)
		log.Printf("Error creating transaction: %v", err)
		return
	}

	// Emitted only after the row is durably committed, so the lake can never
	// contain a transaction the database does not. Emit does not block and
	// cannot fail the request; when the pipeline is disabled this is a no-op.
	if h.Emitter != nil {
		h.Emitter.Emit(pipeline.Event{
			ID:        t.ID,
			Timestamp: t.Date,
			Amount:    t.Amount,
			Category:  t.Category,
			// Description and account are deliberately omitted -- see the
			// package comment on internal/pipeline.
			AIProvider:      deref(t.AIProvider),
			AnomalySeverity: deref(t.AnomalySeverity),
		})
	}

	writeJSON(w, http.StatusCreated, t)
}

// deref renders an optional string column as a plain value, since the event
// schema uses omitempty rather than nulls.
func deref(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

// enrichment holds whatever the model managed to produce. Every field is
// optional; a zero value means analysis was skipped or failed.
type enrichment struct {
	category string
	severity *string
	reason   *string
	provider *string
}

// enrich resolves the category, then assesses the transaction against the
// history of that same category.
//
// The two run in sequence rather than concurrently, and the ordering is the
// point: anomaly detection compares like with like, so it needs the category
// first. Comparing rent against the account-wide average -- which is what
// running them in parallel forced -- flags every month's rent as unusual,
// because rent is many times the size of a typical purchase. Against other
// housing transactions it is unremarkable.
//
// When the caller supplied a category there is nothing to resolve and only the
// assessment runs. Both steps are best-effort: any failure is logged and
// dropped, because neither is worth failing a user's write over.
func (h *TransactionHandler) enrich(ctx context.Context, accountID int, accountType string, amount float64, description, knownCategory string) enrichment {
	var out enrichment
	if h.AI == nil {
		return out
	}

	ctx, cancel := context.WithTimeout(ctx, enrichmentTimeout)
	defer cancel()

	input := ai.TransactionInput{
		Description: description,
		Amount:      amount,
		AccountType: accountType,
		Category:    knownCategory,
	}

	if knownCategory == "" {
		result, err := h.AI.Categorize(ctx, input)
		if err != nil {
			log.Printf("categorize (account %d): %v", accountID, err)
		} else {
			out.category = string(result.Category)
			input.Category = out.category
		}
	}

	if baseline, err := h.baselineFor(ctx, accountID); err != nil {
		log.Printf("anomaly baseline (account %d): %v", accountID, err)
	} else if result, err := h.AI.DetectAnomaly(ctx, input, baseline); err != nil {
		log.Printf("detect anomaly (account %d): %v", accountID, err)
	} else {
		severity := string(result.Severity)
		reason := result.Reason
		out.severity = &severity
		out.reason = &reason
	}

	if out.category != "" || out.severity != nil {
		name := h.AI.Name()
		out.provider = &name
	}
	return out
}

// baselineFor summarises an account's history by category. Aggregates are used
// rather than raw rows so descriptions are never re-sent to the model.
func (h *TransactionHandler) baselineFor(ctx context.Context, accountID int) ([]ai.HistoricalStat, error) {
	rows, err := h.DB.QueryContext(ctx, `
		SELECT category,
		       COUNT(*),
		       COALESCE(SUM(ABS(amount)), 0),
		       COALESCE(AVG(ABS(amount)), 0),
		       COALESCE(MAX(ABS(amount)), 0)
		FROM transactions
		WHERE account_id = $1
		GROUP BY category`, accountID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var stats []ai.HistoricalStat
	for rows.Next() {
		var s ai.HistoricalStat
		if err := rows.Scan(&s.Category, &s.Count, &s.TotalAmount, &s.MeanAmount, &s.MaxAmount); err != nil {
			return nil, err
		}
		stats = append(stats, s)
	}
	return stats, rows.Err()
}
