package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/RuariW12/MaroonLedger/internal/database"
	"github.com/RuariW12/MaroonLedger/internal/handlers"
)

func main() {
	var host, port, user, password, dbname string

	if creds := os.Getenv("DB_CREDENTIALS"); creds != "" {
		var parsed struct {
			Host     string `json:"host"`
			Port     int    `json:"port"`
			Username string `json:"username"`
			Password string `json:"password"`
			DBName   string `json:"dbname"`
		}
		if err := json.Unmarshal([]byte(creds), &parsed); err != nil {
			log.Fatalf("Failed to parse DB_CREDENTIALS: %v", err)
		}
		host = parsed.Host
		port = strconv.Itoa(parsed.Port)
		user = parsed.Username
		password = parsed.Password
		dbname = parsed.DBName
	} else {
		host = getEnv("DB_HOST", "localhost")
		port = getEnv("DB_PORT", "5432")
		user = getEnv("DB_USER", "postgres")
		password = getEnv("DB_PASSWORD", "postgres")
		dbname = getEnv("DB_NAME", "maroonledger")
	}

	db, err := database.Connect(host, port, user, password, dbname)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	defer db.Close()

	accountHandler := &handlers.AccountHandler{DB: db}
	transactionHandler := &handlers.TransactionHandler{DB: db}

	mux := http.NewServeMux()

	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"status":"ok"}`))
	})

	mux.HandleFunc("GET /api/accounts", accountHandler.List)
	mux.HandleFunc("GET /api/accounts/{id}", accountHandler.Get)
	mux.HandleFunc("POST /api/accounts", accountHandler.Create)

	mux.HandleFunc("GET /api/accounts/{accountId}/transactions", transactionHandler.ListByAccount)
	mux.HandleFunc("POST /api/accounts/{accountId}/transactions", transactionHandler.Create)

	server := &http.Server{
		Addr:         ":3000",
		Handler:      mux,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	go func() {
		log.Printf("Server starting on port 3000")
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server failed: %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("Shutting down server...")

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := server.Shutdown(ctx); err != nil {
		log.Fatalf("Server forced to shutdown: %v", err)
	}

	log.Println("Server exited")
}

func getEnv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}
