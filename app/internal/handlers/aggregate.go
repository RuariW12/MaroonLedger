package handlers

import (
	"context"
	"database/sql"
	"time"
)

// categoryBucket is one row of a spending breakdown.
//
// Total is a positive amount of money that left the account. Categories with no
// outflow in the period are absent entirely, so income can never surface as a
// "spending" category and consumers need no sign handling of their own.
type categoryBucket struct {
	Category string  `json:"category"`
	Count    int     `json:"count"`
	Total    float64 `json:"total"`
}

// categoryOutflow totals spending per category over [start, end).
//
// Only negative rows count, and the sign is flipped so callers receive a
// magnitude. Summing the signed amounts instead -- the obvious version -- is
// wrong for any category holding movement in both directions. "transfer" is the
// usual one: money moved into savings offsets a larger outbound wire, and the
// category then reports the difference, which is neither its spending nor its
// income. The failure is silent, because the number that comes out is still a
// plausible-looking amount.
//
// COUNT(*) counts outflow rows only, since the sign filter is in the WHERE
// clause -- "26 transactions" therefore means 26 pieces of spending.
//
// The join on accounts is what scopes this to the caller. Transactions carry no
// user_id of their own, so ownership is always established through the account
// that holds them.
func categoryOutflow(ctx context.Context, db *sql.DB, userID string, start, end time.Time) ([]categoryBucket, error) {
	rows, err := db.QueryContext(ctx, `
		SELECT t.category, COUNT(*), SUM(-t.amount)
		FROM transactions t
		JOIN accounts a ON a.id = t.account_id
		WHERE a.user_id = $1 AND t.date >= $2 AND t.date < $3 AND t.amount < 0
		GROUP BY t.category
		ORDER BY SUM(-t.amount) DESC`, userID, start, end)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	// Non-nil so the JSON field renders as [] rather than null.
	buckets := []categoryBucket{}
	for rows.Next() {
		var c categoryBucket
		if err := rows.Scan(&c.Category, &c.Count, &c.Total); err != nil {
			return nil, err
		}
		c.Total = round2(c.Total)
		buckets = append(buckets, c)
	}

	return buckets, rows.Err()
}

// cashflow totals money in and money out over [start, end) from the signed
// amounts themselves, which is the only way to get both sides right when a
// category holds movement in both directions. See categoryOutflow for why the
// per-category nets cannot be reused here: derived from those, a period with
// +1,800 into savings and a -2,400 wire reports 1,800 less inflow and 1,800
// less outflow than actually moved, and the savings rate computed from them is
// wrong in a way that still looks reasonable.
func cashflow(ctx context.Context, db *sql.DB, userID string, start, end time.Time) (inflow, outflow float64, err error) {
	err = db.QueryRowContext(ctx, `
		SELECT
		  COALESCE(SUM(CASE WHEN t.amount > 0 THEN  t.amount ELSE 0 END), 0),
		  COALESCE(SUM(CASE WHEN t.amount < 0 THEN -t.amount ELSE 0 END), 0)
		FROM transactions t
		JOIN accounts a ON a.id = t.account_id
		WHERE a.user_id = $1 AND t.date >= $2 AND t.date < $3`,
		userID, start, end,
	).Scan(&inflow, &outflow)

	return round2(inflow), round2(outflow), err
}
