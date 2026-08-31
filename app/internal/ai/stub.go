package ai

import (
	"context"
	"fmt"
	"math"
	"sort"
	"strconv"
	"strings"
)

// Stub is a deterministic, dependency-free Provider.
//
// It exists so the application is fully functional with no AWS account, no
// credentials, and no inference spend -- every AI surface renders real output
// during local development and in tests. Its answers come from keyword matching
// and arithmetic, not a model, so they are repeatable and instant.
//
// It is a stand-in for the Bedrock provider, not a fallback for it: when
// Bedrock is configured and fails, the request degrades (see the handlers)
// rather than silently returning stub output as though it were inference.
type Stub struct{}

func NewStub() *Stub { return &Stub{} }

func (s *Stub) Name() string { return "stub" }

// categoryKeywords drives stub classification. Order matters only in that the
// first matching category wins.
var categoryKeywords = []struct {
	category Category
	keywords []string
}{
	{CategoryGroceries, []string{"grocer", "supermarket", "aldi", "lidl", "tesco", "sainsbury", "whole foods", "trader joe", "market"}},
	{CategoryDining, []string{"restaurant", "cafe", "coffee", "starbucks", "pizza", "burger", "deliveroo", "uber eats", "doordash", "bar ", "pub"}},
	{CategoryTransport, []string{"uber", "lyft", "taxi", "fuel", "petrol", "gas station", "shell", "bp ", "rail", "train", "transit", "parking", "airline", "flight"}},
	{CategoryHousing, []string{"rent", "mortgage", "landlord", "letting", "property"}},
	{CategoryUtilities, []string{"electric", "water", "gas bill", "internet", "broadband", "phone", "mobile", "utility", "council tax"}},
	{CategoryHealthcare, []string{"pharmacy", "doctor", "dental", "clinic", "hospital", "health", "optician"}},
	{CategoryEntertainment, []string{"netflix", "spotify", "cinema", "theatre", "concert", "game", "steam", "disney", "hulu", "gym"}},
	{CategoryShopping, []string{"amazon", "ebay", "store", "shop", "clothing", "zara", "h&m", "nike", "apple store"}},
	{CategoryIncome, []string{"salary", "payroll", "wages", "deposit", "refund", "dividend", "interest paid"}},
	{CategoryTransfer, []string{"transfer", "zelle", "venmo", "paypal", "wire", "internal"}},
	{CategoryFees, []string{"fee", "charge", "overdraft", "interest charged", "penalty", "atm"}},
}

// usd formats an amount the way the summary text reads it aloud: a currency
// symbol and thousands separators. Without it the generated prose says
// "2118.75 of outflow", which reads like a quantity rather than money.
func usd(v float64) string {
	whole := int64(math.Abs(v))
	frac := int64(math.Round((math.Abs(v) - float64(whole)) * 100))
	if frac == 100 {
		whole++
		frac = 0
	}

	digits := strconv.FormatInt(whole, 10)
	var grouped strings.Builder
	for i, r := range digits {
		if i > 0 && (len(digits)-i)%3 == 0 {
			grouped.WriteByte(',')
		}
		grouped.WriteRune(r)
	}

	sign := ""
	if v < 0 {
		sign = "-"
	}
	return fmt.Sprintf("%s$%s.%02d", sign, grouped.String(), frac)
}

// comparisonLabel names whatever the amount was measured against, so the
// reason text says what the comparison actually was.
func comparisonLabel(category string) string {
	if category == "" {
		return "this account"
	}
	return category
}

// capitalize upper-cases the first letter for display. Categories are ASCII
// single words, so byte indexing is safe here.
func capitalize(s string) string {
	if s == "" {
		return s
	}
	return strings.ToUpper(s[:1]) + s[1:]
}

func (s *Stub) Categorize(ctx context.Context, in TransactionInput) (*Categorization, error) {
	desc := strings.ToLower(truncate(in.Description, maxDescriptionLen))

	for _, entry := range categoryKeywords {
		for _, kw := range entry.keywords {
			if strings.Contains(desc, kw) {
				return &Categorization{
					Category:   entry.category,
					Confidence: 0.85,
					Rationale:  fmt.Sprintf("Description matched %q.", strings.TrimSpace(kw)),
				}, nil
			}
		}
	}

	// A positive amount with no keyword match is most likely money coming in.
	if in.Amount > 0 {
		return &Categorization{
			Category:   CategoryIncome,
			Confidence: 0.4,
			Rationale:  "Positive amount with no matching keyword.",
		}, nil
	}

	return &Categorization{
		Category:   CategoryOther,
		Confidence: 0.3,
		Rationale:  "No keyword matched.",
	}, nil
}

func (s *Stub) DetectAnomaly(ctx context.Context, in TransactionInput, baseline []HistoricalStat) (*AnomalyAssessment, error) {
	amount := math.Abs(in.Amount)

	if len(baseline) == 0 {
		return &AnomalyAssessment{
			Severity: SeverityNone,
			Reason:   "No history yet to compare against.",
		}, nil
	}

	// Compare like with like. Rent is many times the size of a typical
	// purchase, so scoring it against the account-wide average flags every
	// month's rent as unusual -- the comparison that matters is against other
	// housing transactions, where it is entirely ordinary. Only when the
	// category has no history does the account-wide scale become the fallback.
	var totalCount int
	var totalAmount, overallMax float64

	if in.Category != "" {
		for _, stat := range baseline {
			if stat.Category == in.Category {
				totalCount = stat.Count
				totalAmount = math.Abs(stat.TotalAmount)
				overallMax = math.Abs(stat.MaxAmount)
				break
			}
		}
	}

	if totalCount == 0 {
		for _, stat := range baseline {
			totalCount += stat.Count
			totalAmount += math.Abs(stat.TotalAmount)
			overallMax = math.Max(overallMax, math.Abs(stat.MaxAmount))
		}
	}
	if totalCount == 0 {
		return &AnomalyAssessment{Severity: SeverityNone, Reason: "No history yet to compare against."}, nil
	}
	mean := totalAmount / float64(totalCount)

	// Money arriving is held to a much higher bar than money leaving. A salary
	// is routinely several times the size of a typical purchase, so scoring
	// inflows on the same scale as outflows flags every payday as suspicious.
	if in.Amount > 0 {
		if amount > mean*10 {
			return &AnomalyAssessment{
				Anomalous: true,
				Severity:  SeverityLow,
				Reason:    fmt.Sprintf("Incoming amount is %.1fx the account average.", amount/mean),
			}, nil
		}
		return &AnomalyAssessment{
			Severity: SeverityNone,
			Reason:   "Incoming funds consistent with this account.",
		}, nil
	}

	switch {
	case amount > overallMax*2 && amount > mean*4:
		return &AnomalyAssessment{
			Anomalous: true,
			Severity:  SeverityHigh,
			Reason:    fmt.Sprintf("Amount is %.1fx the usual for %s and more than double the previous largest.", amount/mean, comparisonLabel(in.Category)),
		}, nil
	case amount > mean*3:
		return &AnomalyAssessment{
			Anomalous: true,
			Severity:  SeverityMedium,
			Reason:    fmt.Sprintf("Amount is %.1fx the usual for %s.", amount/mean, comparisonLabel(in.Category)),
		}, nil
	case amount > mean*2:
		return &AnomalyAssessment{
			Anomalous: true,
			Severity:  SeverityLow,
			Reason:    fmt.Sprintf("Amount is %.1fx the usual for %s.", amount/mean, comparisonLabel(in.Category)),
		}, nil
	default:
		return &AnomalyAssessment{
			Severity: SeverityNone,
			Reason:   "Amount is consistent with this account's history.",
		}, nil
	}
}

func (s *Stub) GenerateInsights(ctx context.Context, summary SpendingSummary) (*Insights, error) {
	if len(summary.ByCategory) == 0 {
		return &Insights{
			Summary:      "No spending was recorded in this period, so there is nothing to analyse yet.",
			Observations: []string{"No transactions fall within the selected period."},
			Recommendations: []string{
				"Add transactions to your accounts to start building a spending picture.",
			},
		}, nil
	}

	// ByCategory is spending only, already positive, and carries no income
	// rows -- see handlers.categoryOutflow. Ranking is redone here rather than
	// trusted from the caller, since Provider takes a summary from anywhere.
	ranked := append([]CategorySpend(nil), summary.ByCategory...)
	var spend float64
	for _, c := range ranked {
		spend += c.Total
	}

	if len(ranked) == 0 || spend == 0 {
		return &Insights{
			Summary: fmt.Sprintf("You recorded %s of income and no outgoing spending between %s and %s.",
				usd(summary.TotalInflow),
				summary.PeriodStart.Format("2 Jan 2006"), summary.PeriodEnd.Format("2 Jan 2006")),
			Observations:    []string{"No outgoing transactions fall within this period."},
			Recommendations: []string{"Add spending transactions to see where your money goes."},
		}, nil
	}

	sort.Slice(ranked, func(i, j int) bool { return ranked[i].Total > ranked[j].Total })

	top := ranked[0]
	topShare := top.Total / spend * 100

	net := summary.TotalInflow - summary.TotalOutflow
	direction := "more than you took in"
	if net >= 0 {
		direction = "less than you took in"
	}

	observations := []string{
		fmt.Sprintf("%s is your largest spending category at %s, which is %.0f%% of outgoings.", capitalize(top.Category), usd(top.Total), topShare),
		fmt.Sprintf("You spent %s across %d spending categories, %s (%s net).", usd(spend), len(ranked), direction, usd(net)),
	}
	if len(ranked) > 1 {
		second := ranked[1]
		observations = append(observations, fmt.Sprintf(
			"%s follows at %s across %d transactions.", capitalize(second.Category), usd(second.Total), second.Count))
	}

	recommendations := []string{
		fmt.Sprintf("Set a monthly ceiling for %s -- it is where a small percentage cut frees the most cash.", top.Category),
	}
	if topShare > 40 {
		recommendations = append(recommendations, fmt.Sprintf(
			"%.0f%% of spending in one category is concentrated; check whether any of it is recurring and cancellable.", topShare))
	}
	if net < 0 {
		recommendations = append(recommendations, "Outflow exceeded inflow this period -- review the largest categories before the pattern repeats.")
	}

	return &Insights{
		Summary: fmt.Sprintf(
			"Between %s and %s you recorded %s of outflow against %s of inflow. Spending concentrated in %s, which accounted for %.0f%% of outgoings across %d categories.",
			summary.PeriodStart.Format("2 Jan 2006"), summary.PeriodEnd.Format("2 Jan 2006"),
			usd(summary.TotalOutflow), usd(summary.TotalInflow), top.Category, topShare, len(ranked)),
		Observations:    observations,
		Recommendations: recommendations,
	}, nil
}
