// Package handlers implements the MaroonLedger REST API.
//
// Every handler in this package operates on behalf of exactly one authenticated
// identity. That identity comes from the verified token on the request context,
// never from the request body or a path parameter, so a caller cannot address
// another user's data by changing what it sends.
package handlers

import (
	"database/sql"
	"encoding/json"
	"log"
	"net/http"

	"github.com/RuariW12/MaroonLedger/internal/auth"
)

// maxRequestBody bounds decoded request bodies. Without it a single large POST
// can consume memory proportional to whatever the client chooses to send.
const maxRequestBody = 1 << 20 // 1 MiB

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(body); err != nil {
		log.Printf("write response: %v", err)
	}
}

// decodeJSON reads a bounded, strictly-typed request body.
func decodeJSON(w http.ResponseWriter, r *http.Request, dst any) bool {
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxRequestBody))
	// Reject unknown fields so a client silently sending `user_id` or
	// `anomaly_severity` gets an error rather than the quiet impression that
	// the server honoured it.
	decoder.DisallowUnknownFields()

	if err := decoder.Decode(dst); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return false
	}
	return true
}

// currentUser returns the authenticated subject.
//
// A missing value means the route was mounted without the auth middleware --
// a wiring bug. It fails closed with a 500 rather than falling back to
// unscoped behaviour, which would silently expose every user's data.
func currentUser(w http.ResponseWriter, r *http.Request) (string, bool) {
	claims, ok := auth.ClaimsFrom(r.Context())
	if !ok || claims.Subject == "" {
		log.Printf("SECURITY: handler %s reached without verified claims", r.URL.Path)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return "", false
	}
	return claims.Subject, true
}

// accountOwnedBy resolves an account only if it belongs to the given user.
//
// A row that exists but belongs to someone else is reported as sql.ErrNoRows,
// so callers return 404 rather than 403 and the API does not confirm which
// account ids exist.
func accountOwnedBy(db *sql.DB, accountID int, userID string) (accountType string, err error) {
	err = db.QueryRow(
		"SELECT type FROM accounts WHERE id = $1 AND user_id = $2",
		accountID, userID,
	).Scan(&accountType)
	return accountType, err
}
