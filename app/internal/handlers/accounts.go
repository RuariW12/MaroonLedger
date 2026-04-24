package handlers

import (
	"database/sql"
	"encoding/json"
	"log"
	"net/http"
	"strconv"

	"github.com/RuariW12/MaroonLedger/internal/models"
)

type AccountHandler struct {
	DB *sql.DB
}

func (h *AccountHandler) List(w http.ResponseWriter, r *http.Request) {
	rows, err := h.DB.Query(
		"SELECT id, name, type, balance, created_at, updated_at FROM accounts ORDER BY id",
	)
	if err != nil {
		http.Error(w, "Failed to query accounts", http.StatusInternalServerError)
		log.Printf("Error querying accounts: %v", err)
		return
	}
	defer rows.Close()

	var accounts []models.Account
	for rows.Next() {
		var a models.Account
		if err := rows.Scan(&a.ID, &a.Name, &a.Type, &a.Balance, &a.CreatedAt, &a.UpdatedAt); err != nil {
			http.Error(w, "Failed to scan account", http.StatusInternalServerError)
			log.Printf("Error scanning account: %v", err)
			return
		}
		accounts = append(accounts, a)
	}

	if accounts == nil {
		accounts = []models.Account{}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(accounts)
}

func (h *AccountHandler) Get(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.Atoi(r.PathValue("id"))
	if err != nil {
		http.Error(w, "Invalid account ID", http.StatusBadRequest)
		return
	}

	var a models.Account
	err = h.DB.QueryRow(
		"SELECT id, name, type, balance, created_at, updated_at FROM accounts WHERE id = $1", id,
	).Scan(&a.ID, &a.Name, &a.Type, &a.Balance, &a.CreatedAt, &a.UpdatedAt)

	if err == sql.ErrNoRows {
		http.Error(w, "Account not found", http.StatusNotFound)
		return
	}
	if err != nil {
		http.Error(w, "Failed to query account", http.StatusInternalServerError)
		log.Printf("Error querying account: %v", err)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(a)
}

func (h *AccountHandler) Create(w http.ResponseWriter, r *http.Request) {
	var input struct {
		Name string  `json:"name"`
		Type string  `json:"type"`
		Balance float64 `json:"balance"`
	}

	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if input.Name == "" || input.Type == "" {
		http.Error(w, "Name and type are required", http.StatusBadRequest)
		return
	}

	var a models.Account
	err := h.DB.QueryRow(
		"INSERT INTO accounts (name, type, balance) VALUES ($1, $2, $3) RETURNING id, name, type, balance, created_at, updated_at",
		input.Name, input.Type, input.Balance,
	).Scan(&a.ID, &a.Name, &a.Type, &a.Balance, &a.CreatedAt, &a.UpdatedAt)

	if err != nil {
		http.Error(w, "Failed to create account", http.StatusInternalServerError)
		log.Printf("Error creating account: %v", err)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(a)
}
