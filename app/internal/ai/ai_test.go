package ai

import (
	"context"
	"strings"
	"testing"
	"time"
)

// The model's category choice is constrained by a JSON schema, but the schema
// is enforced by the service on the other side of a network call. This
// allowlist is the control that runs in our own process, so it has to hold for
// anything a model might return -- including output steered by an injected
// instruction in a transaction description.
func TestValidCategoryRejectsAnythingOffTheAllowlist(t *testing.T) {
	for _, c := range Categories {
		if got := ValidCategory(string(c)); got != c {
			t.Errorf("ValidCategory(%q) = %q, want %q", c, got, c)
		}
	}

	hostile := []string{
		"", "admin", "admin_override", "GROCERIES", "groceries ", " groceries",
		"'; DROP TABLE transactions; --", "../../etc/passwd",
		`{"category":"income"}`, "income\nfees",
	}
	for _, input := range hostile {
		if got := ValidCategory(input); got != CategoryOther {
			t.Errorf("ValidCategory(%q) = %q, want %q", input, got, CategoryOther)
		}
	}
}

func TestValidSeverityDefaultsToNone(t *testing.T) {
	valid := map[string]Severity{
		"low": SeverityLow, "medium": SeverityMedium, "high": SeverityHigh,
	}
	for input, want := range valid {
		if got := ValidSeverity(input); got != want {
			t.Errorf("ValidSeverity(%q) = %q, want %q", input, got, want)
		}
	}

	// Anything unrecognised must fail quiet, not loud: an unparseable answer
	// should never manufacture an alert.
	for _, input := range []string{"", "none", "critical", "HIGH", "severe", "1"} {
		if got := ValidSeverity(input); got != SeverityNone {
			t.Errorf("ValidSeverity(%q) = %q, want %q", input, got, SeverityNone)
		}
	}
}

func TestStubCategorize(t *testing.T) {
	stub := NewStub()

	tests := []struct {
		description string
		amount      float64
		want        Category
	}{
		{"TESCO SUPERSTORE 4471", -84.20, CategoryGroceries},
		{"Starbucks Coffee #221", -5.75, CategoryDining},
		{"Uber trip", -18.00, CategoryTransport},
		{"Monthly rent payment", -1400, CategoryHousing},
		{"Netflix subscription", -15.99, CategoryEntertainment},
		{"Salary - August", 3200, CategoryIncome},
		{"Overdraft fee", -25, CategoryFees},
		// No keyword and money leaving: nothing sensible to infer.
		{"zzzz unknown merchant", -12, CategoryOther},
		// No keyword but money arriving: income is the best guess.
		{"zzzz unknown merchant", 12, CategoryIncome},
		{"", -5, CategoryOther},
	}

	for _, tc := range tests {
		got, err := stub.Categorize(context.Background(), TransactionInput{
			Description: tc.description, Amount: tc.amount, AccountType: "checking",
		})
		if err != nil {
			t.Fatalf("Categorize(%q): %v", tc.description, err)
		}
		if got.Category != tc.want {
			t.Errorf("Categorize(%q) = %q, want %q", tc.description, got.Category, tc.want)
		}
	}
}

func TestStubAnomalyTreatsIncomeMoreLeniently(t *testing.T) {
	stub := NewStub()
	baseline := []HistoricalStat{
		{Category: "groceries", Count: 10, TotalAmount: 500, MeanAmount: 50, MaxAmount: 90},
	}

	// A payday is many times the size of a typical purchase. Scoring it on the
	// same scale as spending would flag every salary that ever arrives.
	income, err := stub.DetectAnomaly(context.Background(),
		TransactionInput{Description: "Salary", Amount: 400}, baseline)
	if err != nil {
		t.Fatal(err)
	}
	if income.Severity != SeverityNone {
		t.Errorf("routine salary flagged as %q, want %q", income.Severity, SeverityNone)
	}

	// The same magnitude leaving the account is genuinely unusual.
	spend, err := stub.DetectAnomaly(context.Background(),
		TransactionInput{Description: "Wire transfer", Amount: -400}, baseline)
	if err != nil {
		t.Fatal(err)
	}
	if spend.Severity == SeverityNone {
		t.Error("outflow far above the account average was not flagged")
	}
	if !spend.Anomalous {
		t.Error("severity was set but Anomalous was false")
	}
}

func TestStubAnomalyWithNoHistory(t *testing.T) {
	got, err := NewStub().DetectAnomaly(context.Background(),
		TransactionInput{Description: "First ever", Amount: -99999}, nil)
	if err != nil {
		t.Fatal(err)
	}
	// With nothing to compare against there is no basis to call anything
	// unusual, however large it is.
	if got.Anomalous || got.Severity != SeverityNone {
		t.Errorf("got %+v, want a non-anomalous assessment", got)
	}
}

// Income must not be counted as spending, or a salary can be reported as the
// largest "spending" category and every total is inflated.
// Income never reaches the stub as a category: handlers.categoryOutflow filters
// it out in SQL, and every Total that arrives is a positive amount spent. This
// pins that contract, since the stub reports whatever it is handed.
func TestStubInsightsRanksSpendingWithoutIncome(t *testing.T) {
	summary := SpendingSummary{
		PeriodStart:  time.Now().AddDate(0, -1, 0),
		PeriodEnd:    time.Now(),
		Currency:     "USD",
		TotalInflow:  3200,
		TotalOutflow: 600,
		ByCategory: []CategorySpend{
			{Category: "groceries", Count: 8, Total: 400},
			{Category: "dining", Count: 5, Total: 200},
		},
	}

	got, err := NewStub().GenerateInsights(context.Background(), summary)
	if err != nil {
		t.Fatal(err)
	}

	if want := "Groceries is your largest spending category"; !contains(got.Observations, want) {
		t.Errorf("observations did not identify groceries as top spend: %v", got.Observations)
	}
	for _, o := range got.Observations {
		if strings.Contains(o, "3200") {
			t.Errorf("income leaked into a spending observation: %q", o)
		}
		if strings.Contains(o, "-$") {
			t.Errorf("spending rendered as a negative amount: %q", o)
		}
	}
}

func TestStubInsightsWithNoSpending(t *testing.T) {
	got, err := NewStub().GenerateInsights(context.Background(), SpendingSummary{
		PeriodStart: time.Now().AddDate(0, -1, 0),
		PeriodEnd:   time.Now(),
	})
	if err != nil {
		t.Fatal(err)
	}
	if got.Summary == "" || len(got.Observations) == 0 {
		t.Error("empty summary should still produce readable output")
	}
}

func contains(haystack []string, needle string) bool {
	for _, s := range haystack {
		if strings.Contains(s, needle) {
			return true
		}
	}
	return false
}

// The first transaction in a category has no peers to be measured against, so
// the score falls back to the whole account. The reason text has to say so:
// claiming "11.3x the usual for housing" when housing had no history at all is
// a statement about a comparison that never happened.
func TestStubAnomalyNamesTheBaselineItActuallyUsed(t *testing.T) {
	baseline := []HistoricalStat{
		{Category: "groceries", Count: 39, TotalAmount: -1863.55, MeanAmount: -47.78, MaxAmount: -84.20},
	}

	fellBack, err := NewStub().DetectAnomaly(context.Background(),
		TransactionInput{Description: "Monthly rent payment", Amount: -1685, AccountType: "checking", Category: "housing"},
		baseline)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(fellBack.Reason, "housing") {
		t.Errorf("named a category with no history as the baseline: %q", fellBack.Reason)
	}
	if !strings.Contains(fellBack.Reason, "this account") {
		t.Errorf("did not disclose the account-wide fallback: %q", fellBack.Reason)
	}

	// With history in its own category, the comparison is real and named.
	inCategory, err := NewStub().DetectAnomaly(context.Background(),
		TransactionInput{Description: "Wire transfer overseas", Amount: -2400, AccountType: "checking", Category: "transfer"},
		append(baseline, HistoricalStat{Category: "transfer", Count: 3, TotalAmount: 1800, MeanAmount: 600, MaxAmount: 600}))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(inCategory.Reason, "transfer") {
		t.Errorf("did not name the category it compared within: %q", inCategory.Reason)
	}
}
