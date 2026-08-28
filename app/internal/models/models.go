package models

import "time"

type Account struct {
	ID   int    `json:"id"`
	Name string `json:"name"`
	Type string `json:"type"`
	// UserID is the owning identity's Cognito `sub`. It is never serialised:
	// the client already knows who it is, and echoing it back only widens the
	// surface for a scoping bug to become an information leak.
	UserID    string    `json:"-"`
	Balance   float64   `json:"balance"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type Transaction struct {
	ID          int       `json:"id"`
	AccountID   int       `json:"account_id"`
	Amount      float64   `json:"amount"`
	Category    string    `json:"category"`
	Description string    `json:"description"`
	Date        time.Time `json:"date"`
	CreatedAt   time.Time `json:"created_at"`

	// AI enrichment. All optional -- analysis is best-effort and a transaction
	// whose enrichment failed is still complete and valid.
	AutoCategorized bool    `json:"auto_categorized"`
	AnomalySeverity *string `json:"anomaly_severity,omitempty"`
	AnomalyReason   *string `json:"anomaly_reason,omitempty"`
	AIProvider      *string `json:"ai_provider,omitempty"`
}
