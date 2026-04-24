package handlers

import (
	"database/sql"
	"encoding/json"
	"log"
	"net/http"
	"strconv"
	"time"

	"github.com/RuariW12/MaroonLedger/internal/models"
)

type TransactionHandler struct {
	DB *sql.DB
}

func (h *TransactionHandler) ListByAccount(w http.ResponseWriter, r *http.Request) {
	accountID, err := strconv.Atoi(r.PathValue("accountId"))
	if err != nil {
		http.Error(w, "Invalid account ID", http.StatusBadRequest)
		return
	}

	rows, err := h.DB.Query(
		"SELECT id, account_id, amount, category, description, date, created_at FROM transactions WHERE account_id = $1 ORDER BY date DESC",
		accountID,
	)
	if err != nil {
		http.Error(w, "Failed to query transactions", http.StatusInternalServerError)
		log.Printf("Error querying transactions: %v", err)
		return
	}
	defer rows.Close()

	var transactions []models.Transaction
	for rows.Next() {
		var t models.Transaction
		if err := rows.Scan(&t.ID, &t.AccountID, &t.Amount, &t.Category, &t.Description, &t.Date, &t.CreatedAt); err != nil {
			http.Error(w, "Failed to scan transaction", http.StatusInternalServerError)
			log.Printf("Error scanning transaction: %v", err)
			return
		}
		transactions = append(transactions, t)
	}

	if transactions == nil {
		transactions = []models.Transaction{}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(transactions)
}

func (h *TransactionHandler) Create(w http.ResponseWriter, r *http.Request) {
	accountID, err := strconv.Atoi(r.PathValue("accountId"))
	if err != nil {
		http.Error(w, "Invalid account ID", http.StatusBadRequest)
		return
	}

	var input struct {
		Amount      float64 `json:"amount"`
		Category    string  `json:"category"`
		Description string  `json:"description"`
		Date        string  `json:"date"`
	}

	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if input.Category == "" {
		http.Error(w, "Category is required", http.StatusBadRequest)
		return
	}

	date := time.Now()
	if input.Date != "" {
		parsed, err := time.Parse("2006-01-02", input.Date)
		if err != nil {
			http.Error(w, "Invalid date format, use YYYY-MM-DD", http.StatusBadRequest)
			return
		}
		date = parsed
	}

	var t models.Transaction
	err = h.DB.QueryRow(
		"INSERT INTO transactions (account_id, amount, category, description, date) VALUES ($1, $2, $3, $4, $5) RETURNING id, account_id, amount, category, description, date, created_at",
		accountID, input.Amount, input.Category, input.Description, date,
	).Scan(&t.ID, &t.AccountID, &t.Amount, &t.Category, &t.Description, &t.Date, &t.CreatedAt)

	if err != nil {
		http.Error(w, "Failed to create transaction", http.StatusInternalServerError)
		log.Printf("Error creating transaction: %v", err)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(t)
}
