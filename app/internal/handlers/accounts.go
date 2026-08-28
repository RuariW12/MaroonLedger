package handlers

import (
	"database/sql"
	"log"
	"net/http"
	"strconv"
	"strings"

	"github.com/RuariW12/MaroonLedger/internal/models"
)

type AccountHandler struct {
	DB *sql.DB
}

// accountTypes mirrors the CHECK constraint on the accounts table. Validating
// here turns a database constraint violation into a useful 400.
var accountTypes = map[string]bool{
	"checking": true, "savings": true, "credit": true, "loan": true,
}

const accountColumns = "id, name, type, balance, created_at, updated_at"

func (h *AccountHandler) List(w http.ResponseWriter, r *http.Request) {
	userID, ok := currentUser(w, r)
	if !ok {
		return
	}

	rows, err := h.DB.Query(
		"SELECT "+accountColumns+" FROM accounts WHERE user_id = $1 ORDER BY id", userID,
	)
	if err != nil {
		http.Error(w, "Failed to query accounts", http.StatusInternalServerError)
		log.Printf("Error querying accounts: %v", err)
		return
	}
	defer rows.Close()

	accounts := []models.Account{}
	for rows.Next() {
		var a models.Account
		if err := rows.Scan(&a.ID, &a.Name, &a.Type, &a.Balance, &a.CreatedAt, &a.UpdatedAt); err != nil {
			http.Error(w, "Failed to scan account", http.StatusInternalServerError)
			log.Printf("Error scanning account: %v", err)
			return
		}
		accounts = append(accounts, a)
	}
	if err := rows.Err(); err != nil {
		http.Error(w, "Failed to read accounts", http.StatusInternalServerError)
		log.Printf("Error iterating accounts: %v", err)
		return
	}

	writeJSON(w, http.StatusOK, accounts)
}

func (h *AccountHandler) Get(w http.ResponseWriter, r *http.Request) {
	userID, ok := currentUser(w, r)
	if !ok {
		return
	}

	id, err := strconv.Atoi(r.PathValue("id"))
	if err != nil {
		http.Error(w, "Invalid account ID", http.StatusBadRequest)
		return
	}

	var a models.Account
	err = h.DB.QueryRow(
		"SELECT "+accountColumns+" FROM accounts WHERE id = $1 AND user_id = $2", id, userID,
	).Scan(&a.ID, &a.Name, &a.Type, &a.Balance, &a.CreatedAt, &a.UpdatedAt)

	// Someone else's account is reported as missing, not forbidden -- a 403
	// would confirm the id is real.
	if err == sql.ErrNoRows {
		http.Error(w, "Account not found", http.StatusNotFound)
		return
	}
	if err != nil {
		http.Error(w, "Failed to query account", http.StatusInternalServerError)
		log.Printf("Error querying account: %v", err)
		return
	}

	writeJSON(w, http.StatusOK, a)
}

func (h *AccountHandler) Create(w http.ResponseWriter, r *http.Request) {
	userID, ok := currentUser(w, r)
	if !ok {
		return
	}

	var input struct {
		Name    string  `json:"name"`
		Type    string  `json:"type"`
		Balance float64 `json:"balance"`
	}
	if !decodeJSON(w, r, &input) {
		return
	}

	input.Name = strings.TrimSpace(input.Name)
	switch {
	case input.Name == "":
		http.Error(w, "Name is required", http.StatusBadRequest)
		return
	case len(input.Name) > 255:
		http.Error(w, "Name must be 255 characters or fewer", http.StatusBadRequest)
		return
	case !accountTypes[input.Type]:
		http.Error(w, "Type must be one of: checking, savings, credit, loan", http.StatusBadRequest)
		return
	}

	var a models.Account
	err := h.DB.QueryRow(
		"INSERT INTO accounts (name, type, balance, user_id) VALUES ($1, $2, $3, $4) RETURNING "+accountColumns,
		input.Name, input.Type, input.Balance, userID,
	).Scan(&a.ID, &a.Name, &a.Type, &a.Balance, &a.CreatedAt, &a.UpdatedAt)
	if err != nil {
		http.Error(w, "Failed to create account", http.StatusInternalServerError)
		log.Printf("Error creating account: %v", err)
		return
	}

	writeJSON(w, http.StatusCreated, a)
}
