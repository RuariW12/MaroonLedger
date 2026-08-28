// Command devidp is a minimal OIDC-shaped identity provider for local development.
//
// It exists so that running MaroonLedger locally exercises the *same* token
// verification path as running it on AWS. The API server always validates an
// RS256 access token against a JWKS endpoint; in AWS that endpoint belongs to a
// Cognito user pool, and here it belongs to this process. There is no "skip
// auth" flag in the server, because a bypass that exists in the code is a
// bypass that can ship.
//
// It mints tokens for any username with no password check whatsoever. That is
// the entire point and also the reason it must never run anywhere but a
// developer's machine: it is wired only into docker-compose.yml and is not
// built into the production image (see Dockerfile, which builds ./cmd/server).
package main

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"log"
	"math/big"
	"net/http"
	"os"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const keyID = "maroonledger-dev-key"

func main() {
	issuer := getEnv("DEVIDP_ISSUER", "http://localhost:9000")
	clientID := getEnv("DEVIDP_CLIENT_ID", "maroonledger-local")
	addr := ":" + getEnv("DEVIDP_PORT", "9000")

	// A fresh key per start is fine: the server fetches the JWKS on boot and
	// refreshes it in the background, so a restart just rotates the key.
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		log.Fatalf("generate signing key: %v", err)
	}

	mux := http.NewServeMux()

	mux.HandleFunc("GET /.well-known/jwks.json", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{
			"keys": []map[string]string{{
				"kty": "RSA",
				"use": "sig",
				"alg": "RS256",
				"kid": keyID,
				"n":   base64.RawURLEncoding.EncodeToString(key.PublicKey.N.Bytes()),
				"e":   base64.RawURLEncoding.EncodeToString(bigEndian(uint64(key.PublicKey.E))),
			}},
		})
	})

	// Advertise the discovery document so the endpoint shape matches a real
	// OIDC provider even though the frontend only needs /token.
	mux.HandleFunc("GET /.well-known/openid-configuration", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{
			"issuer":                                issuer,
			"jwks_uri":                              issuer + "/.well-known/jwks.json",
			"token_endpoint":                        issuer + "/token",
			"id_token_signing_alg_values_supported": []string{"RS256"},
		})
	})

	mux.HandleFunc("POST /token", func(w http.ResponseWriter, r *http.Request) {
		username := r.FormValue("username")
		if username == "" {
			var body struct {
				Username string `json:"username"`
			}
			json.NewDecoder(r.Body).Decode(&body)
			username = body.Username
		}
		if username == "" {
			http.Error(w, "username is required", http.StatusBadRequest)
			return
		}

		now := time.Now()
		const lifetime = time.Hour

		token := jwt.NewWithClaims(jwt.SigningMethodRS256, jwt.MapClaims{
			// Derived from the username rather than random, so restarting this
			// process does not orphan the accounts a developer already created.
			"sub":       stableSubject(username),
			"token_use": "access",
			"client_id": clientID,
			"username":  username,
			"scope":     "openid profile",
			"iss":       issuer,
			"iat":       now.Unix(),
			"exp":       now.Add(lifetime).Unix(),
			"jti":       fmt.Sprintf("%d", now.UnixNano()),
		})
		token.Header["kid"] = keyID

		signed, err := token.SignedString(key)
		if err != nil {
			http.Error(w, "failed to sign token", http.StatusInternalServerError)
			log.Printf("sign token: %v", err)
			return
		}

		writeJSON(w, http.StatusOK, map[string]any{
			"access_token": signed,
			"token_type":   "Bearer",
			"expires_in":   int(lifetime.Seconds()),
			"username":     username,
		})
	})

	log.Printf("!! DEVELOPMENT IDENTITY PROVIDER -- issues tokens to anyone, never deploy !!")
	log.Printf("dev-idp listening on %s (issuer %s, client %s)", addr, issuer, clientID)

	server := &http.Server{
		Addr:              addr,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}
	log.Fatal(server.ListenAndServe())
}

// stableSubject maps a username to a deterministic UUID-shaped identifier, so
// dev tokens look like Cognito subs and stay constant across restarts.
func stableSubject(username string) string {
	sum := sha256.Sum256([]byte("maroonledger-dev:" + username))
	return fmt.Sprintf("%x-%x-%x-%x-%x", sum[0:4], sum[4:6], sum[6:8], sum[8:10], sum[10:16])
}

func bigEndian(v uint64) []byte {
	buf := make([]byte, 8)
	binary.BigEndian.PutUint64(buf, v)
	return new(big.Int).SetBytes(buf).Bytes()
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(body)
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
