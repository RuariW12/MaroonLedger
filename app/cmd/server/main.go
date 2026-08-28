package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/RuariW12/MaroonLedger/internal/ai"
	"github.com/RuariW12/MaroonLedger/internal/auth"
	"github.com/RuariW12/MaroonLedger/internal/database"
	"github.com/RuariW12/MaroonLedger/internal/handlers"
	"github.com/RuariW12/MaroonLedger/internal/pipeline"
	"github.com/RuariW12/MaroonLedger/internal/ratelimit"
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	db, err := connectDatabase()
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	defer db.Close()

	if err := database.Migrate(db); err != nil {
		log.Fatalf("Failed to run migrations: %v", err)
	}

	// Auth configuration is required, and there is no flag to turn it off.
	// A misconfigured issuer stops the process here rather than starting a
	// server that quietly serves unauthenticated traffic.
	verifier, err := auth.NewVerifier(ctx, auth.Config{
		Issuer:   mustEnv("AUTH_ISSUER"),
		JWKSURL:  mustEnv("AUTH_JWKS_URL"),
		ClientID: mustEnv("AUTH_CLIENT_ID"),
	})
	if err != nil {
		log.Fatalf("Failed to initialise authentication: %v", err)
	}

	provider, err := buildAIProvider(ctx)
	if err != nil {
		log.Fatalf("Failed to initialise AI provider: %v", err)
	}
	log.Printf("AI provider: %s", provider.Name())

	emitter, err := buildEmitter(ctx)
	if err != nil {
		log.Fatalf("Failed to initialise data pipeline: %v", err)
	}
	log.Printf("Data pipeline: %s", emitter.Name())

	accountHandler := &handlers.AccountHandler{DB: db}
	transactionHandler := &handlers.TransactionHandler{DB: db, AI: provider, Emitter: emitter}
	insightsHandler := &handlers.InsightsHandler{DB: db, AI: provider}
	summaryHandler := &handlers.SummaryHandler{DB: db}

	// Model-backed routes cost money per call, so they get a tighter budget
	// than the plain CRUD routes.
	inference := ratelimit.New(10, 3)
	writes := ratelimit.New(60, 15)

	api := http.NewServeMux()
	api.HandleFunc("GET /api/me", handlers.Me)
	api.HandleFunc("GET /api/summary", summaryHandler.Get)
	api.HandleFunc("GET /api/accounts", accountHandler.List)
	api.HandleFunc("GET /api/accounts/{id}", accountHandler.Get)
	api.Handle("POST /api/accounts", writes.Middleware(http.HandlerFunc(accountHandler.Create)))
	api.HandleFunc("GET /api/accounts/{accountId}/transactions", transactionHandler.ListByAccount)
	api.Handle("POST /api/accounts/{accountId}/transactions", writes.Middleware(http.HandlerFunc(transactionHandler.Create)))
	api.Handle("GET /api/insights", inference.Middleware(http.HandlerFunc(insightsHandler.Generate)))

	mux := http.NewServeMux()

	// Health is deliberately unauthenticated: the ALB target group calls it
	// with no credentials. It reports liveness only -- never configuration,
	// versions, or anything else useful to someone probing the service.
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		if err := db.PingContext(r.Context()); err != nil {
			http.Error(w, `{"status":"unhealthy"}`, http.StatusServiceUnavailable)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"status":"ok"}`))
	})

	mux.Handle("/api/", verifier.Middleware(api))

	port := getEnv("PORT", "3000")
	server := &http.Server{
		Addr:              ":" + port,
		Handler:           requestLogger(securityHeaders(mux)),
		ReadTimeout:       10 * time.Second,
		ReadHeaderTimeout: 5 * time.Second,
		// Generous enough to cover a synchronous inference call on the
		// insights endpoint, which can legitimately take tens of seconds.
		WriteTimeout: 60 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	go func() {
		log.Printf("Server starting on port %s", port)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server failed: %v", err)
		}
	}()

	<-ctx.Done()
	log.Println("Shutting down server...")

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := server.Shutdown(shutdownCtx); err != nil {
		log.Fatalf("Server forced to shutdown: %v", err)
	}

	// Drained after the server stops accepting requests, so nothing is still
	// producing events. A failure here is logged rather than fatal: losing
	// buffered telemetry must not turn a clean shutdown into a crash.
	if err := emitter.Close(shutdownCtx); err != nil {
		log.Printf("Data pipeline shutdown: %v", err)
	}

	log.Println("Server exited")
}

// buildAIProvider selects the model backend.
//
// The default is the local stub, so a missing or misconfigured AI_PROVIDER can
// never result in unexpected inference spend -- opting into Bedrock is explicit.
func buildAIProvider(ctx context.Context) (ai.Provider, error) {
	switch provider := getEnv("AI_PROVIDER", "stub"); provider {
	case "stub":
		return ai.NewStub(), nil
	case "bedrock":
		return ai.NewBedrock(ctx, ai.BedrockConfig{
			Region: getEnv("AWS_REGION", "us-east-2"),
			Model:  os.Getenv("BEDROCK_MODEL"),
		})
	default:
		return nil, &configError{"AI_PROVIDER must be 'stub' or 'bedrock', got " + provider}
	}
}

// buildEmitter selects the analytics backend.
//
// Off by default, matching AI_PROVIDER: a missing or misspelled DATA_PIPELINE
// value yields the no-op emitter rather than silently starting to bill for
// Firehose ingestion. Enabling it is explicit.
func buildEmitter(ctx context.Context) (pipeline.Emitter, error) {
	switch mode := getEnv("DATA_PIPELINE", "off"); mode {
	case "off":
		return pipeline.NewDisabled(), nil
	case "firehose":
		return pipeline.NewFirehose(ctx, pipeline.FirehoseConfig{
			StreamName: mustEnv("DATA_PIPELINE_STREAM"),
			Region:     getEnv("AWS_REGION", "us-east-2"),
		})
	default:
		return nil, &configError{"DATA_PIPELINE must be 'off' or 'firehose', got " + mode}
	}
}

// securityHeaders applies defence-in-depth response headers.
//
// CloudFront terminates TLS and serves the frontend, so the headers that matter
// for the HTML document belong there. These cover the API's own responses.
func securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("Referrer-Policy", "no-referrer")
		// Financial data should not sit in a shared or disk cache.
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
		next.ServeHTTP(w, r)
	})
}

// statusRecorder captures the response status for logging.
type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(status int) {
	r.status = status
	r.ResponseWriter.WriteHeader(status)
}

// requestLogger emits one line per request.
//
// It logs the method, path, status and duration -- never headers, bodies, or
// query strings, any of which can carry tokens or personal data into what is a
// far less protected system than the database.
func requestLogger(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}

		next.ServeHTTP(rec, r)

		log.Printf("%s %s %d %s", r.Method, r.URL.Path, rec.status, time.Since(start).Round(time.Millisecond))
	})
}

type configError struct{ msg string }

func (e *configError) Error() string { return e.msg }

func mustEnv(key string) string {
	value := os.Getenv(key)
	if value == "" {
		log.Fatalf("Required environment variable %s is not set", key)
	}
	return value
}

func getEnv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

// firstNonEmpty returns the first value that is set, so a secret's fields take
// precedence over the environment without either having to be complete.
func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if v != "" {
			return v
		}
	}
	return ""
}

// nonZero renders an int as a string, treating 0 as absent so it can take part
// in firstNonEmpty.
func nonZero(n int) string {
	if n == 0 {
		return ""
	}
	return strconv.Itoa(n)
}

// connectDatabase resolves credentials from Secrets Manager when running on
// ECS (where the secret is injected as a JSON blob) and from discrete
// environment variables locally.
func connectDatabase() (*sql.DB, error) {
	if creds := os.Getenv("DB_CREDENTIALS"); creds != "" {
		var parsed struct {
			Host     string `json:"host"`
			Port     int    `json:"port"`
			Username string `json:"username"`
			Password string `json:"password"`
			DBName   string `json:"dbname"`
		}
		if err := json.Unmarshal([]byte(creds), &parsed); err != nil {
			// Deliberately does not echo the value -- it is the database
			// password, and a parse error would otherwise put it in the logs.
			return nil, &configError{"DB_CREDENTIALS is not valid JSON"}
		}

		// An RDS-managed master secret contains only username and password,
		// because that is all RDS rotates. Host, port and database name are
		// not secret and arrive as ordinary environment variables. A
		// self-managed secret may carry all five, so whatever the secret does
		// provide wins and the environment fills the rest.
		host := firstNonEmpty(parsed.Host, os.Getenv("DB_HOST"))
		port := firstNonEmpty(nonZero(parsed.Port), getEnv("DB_PORT", "5432"))
		dbname := firstNonEmpty(parsed.DBName, os.Getenv("DB_NAME"))

		if host == "" || dbname == "" {
			return nil, &configError{"DB_HOST and DB_NAME must be set when DB_CREDENTIALS omits them"}
		}

		return database.Connect(host, port, parsed.Username, parsed.Password, dbname,
			getEnv("DB_SSLMODE", "require"))
	}

	return database.Connect(
		getEnv("DB_HOST", "localhost"),
		getEnv("DB_PORT", "5432"),
		getEnv("DB_USER", "postgres"),
		getEnv("DB_PASSWORD", "postgres"),
		getEnv("DB_NAME", "maroonledger"),
		getEnv("DB_SSLMODE", "disable"),
	)
}
