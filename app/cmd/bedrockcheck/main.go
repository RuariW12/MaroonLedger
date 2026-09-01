// Command bedrockcheck exercises the real Bedrock provider once, against
// whatever BEDROCK_API / BEDROCK_MODEL / AWS_REGION are set to.
//
// It exists because "is Bedrock working here?" has several distinct answers
// that look alike from inside the application -- the endpoint not serving the
// account, the model not being granted, the use-case form being unsubmitted,
// and the account's inference quota being zero all surface as a failed
// enrichment that is logged and dropped. Running this separates them in
// seconds instead of by reading task logs.
//
//	BEDROCK_API=runtime BEDROCK_MODEL=us.anthropic.claude-sonnet-4-6 \
//	  AWS_REGION=us-east-2 go run ./cmd/bedrockcheck
package main

import (
	"context"
	"fmt"
	"os"
	"time"

	"github.com/RuariW12/MaroonLedger/internal/ai"
)

func main() {
	model := os.Getenv("BEDROCK_MODEL")
	region := os.Getenv("AWS_REGION")
	if region == "" {
		region = "us-east-2"
	}
	fmt.Printf("api:    %s\nmodel:  %s\nregion: %s\n\n", os.Getenv("BEDROCK_API"), model, region)

	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()

	p, err := ai.NewBedrock(ctx, ai.BedrockConfig{Region: region, Model: model, API: os.Getenv("BEDROCK_API")})
	if err != nil {
		fmt.Println("client:", err)
		os.Exit(1)
	}

	start := time.Now()
	cat, err := p.Categorize(ctx, ai.TransactionInput{
		Description: "TESCO SUPERSTORE 4471 weekly shop",
		Amount:      -84.20,
		AccountType: "checking",
	})
	if err != nil {
		fmt.Printf("categorize FAILED after %s:\n  %v\n", time.Since(start).Round(time.Millisecond), err)
		os.Exit(1)
	}
	fmt.Printf("categorize OK in %s -> %s (confidence %.2f)\n  %s\n",
		time.Since(start).Round(time.Millisecond), cat.Category, cat.Confidence, cat.Rationale)

	start = time.Now()
	an, err := p.DetectAnomaly(ctx, ai.TransactionInput{
		Description: "Wire transfer overseas", Amount: -6400, AccountType: "checking", Category: "transfer",
	}, []ai.HistoricalStat{
		{Category: "transfer", Count: 3, TotalAmount: 1800, MeanAmount: 600, MaxAmount: 600},
	})
	if err != nil {
		fmt.Printf("anomaly FAILED after %s:\n  %v\n", time.Since(start).Round(time.Millisecond), err)
		os.Exit(1)
	}
	fmt.Printf("anomaly OK in %s -> anomalous=%v severity=%s\n  %s\n",
		time.Since(start).Round(time.Millisecond), an.Anomalous, an.Severity, an.Reason)
}
