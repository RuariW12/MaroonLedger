// Package auth verifies OIDC access tokens against a JWKS endpoint.
//
// The verifier is deliberately provider-agnostic: it is pointed at an issuer
// and a JWKS URL, not at Cognito specifically. In AWS those values describe a
// Cognito user pool; locally they describe the dev identity provider in
// cmd/devidp. Both paths run this exact code, so the authenticated request path
// is never simulated or bypassed during development.
package auth

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/MicahParks/keyfunc/v3"
	"github.com/golang-jwt/jwt/v5"
)

// Config describes the identity provider whose tokens this service accepts.
type Config struct {
	// Issuer is the exact expected `iss` claim.
	Issuer string
	// JWKSURL serves the issuer's public signing keys.
	JWKSURL string
	// ClientID is the app client the token must have been issued to. Cognito
	// puts this in `client_id` on access tokens rather than in `aud`.
	ClientID string
}

// Claims is the subset of the token this application acts on.
type Claims struct {
	// Subject is the stable per-user identifier (Cognito `sub`). It is the
	// value rows are owned by, and it never changes for a given user.
	Subject  string
	Username string
	Groups   []string
}

// Verifier validates bearer tokens against the issuer's published keys.
type Verifier struct {
	cfg     Config
	keyfunc keyfunc.Keyfunc
}

// NewVerifier starts a background refresh of the issuer's JWKS. The initial
// fetch happens here, so a misconfigured issuer fails at startup rather than on
// the first request.
func NewVerifier(ctx context.Context, cfg Config) (*Verifier, error) {
	if cfg.Issuer == "" || cfg.JWKSURL == "" || cfg.ClientID == "" {
		return nil, errors.New("auth: issuer, JWKS URL and client ID are all required")
	}

	kf, err := keyfunc.NewDefaultCtx(ctx, []string{cfg.JWKSURL})
	if err != nil {
		return nil, fmt.Errorf("auth: load JWKS from %s: %w", cfg.JWKSURL, err)
	}

	return &Verifier{cfg: cfg, keyfunc: kf}, nil
}

// ErrUnauthorized is returned for every token rejection. The specific reason is
// deliberately not surfaced to the caller -- distinguishing "expired" from
// "wrong signature" from "wrong audience" only helps an attacker probe.
var ErrUnauthorized = errors.New("unauthorized")

// Verify checks the token's signature, expiry, issuer and client, and returns
// the claims this application relies on.
func (v *Verifier) Verify(raw string) (*Claims, error) {
	token, err := jwt.Parse(raw, v.keyfunc.Keyfunc,
		// Cognito signs with RS256. Pinning the accepted algorithms is what
		// blocks the `alg: none` and HMAC-key-confusion families of attack.
		jwt.WithValidMethods([]string{"RS256"}),
		jwt.WithIssuer(v.cfg.Issuer),
		jwt.WithExpirationRequired(),
		jwt.WithLeeway(30*time.Second),
	)
	if err != nil || !token.Valid {
		return nil, ErrUnauthorized
	}

	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok {
		return nil, ErrUnauthorized
	}

	// Reject ID tokens presented as API credentials. They are issued for the
	// frontend's own use and are not proof of a delegated API call.
	if use, _ := claims["token_use"].(string); use != "access" {
		return nil, ErrUnauthorized
	}

	// A valid signature only proves the issuer minted this token -- not that it
	// minted it for us. Without this check a token issued to any other app
	// client in the same user pool would be accepted.
	if id, _ := claims["client_id"].(string); id != v.cfg.ClientID {
		return nil, ErrUnauthorized
	}

	subject, _ := claims["sub"].(string)
	if subject == "" {
		return nil, ErrUnauthorized
	}

	username, _ := claims["username"].(string)

	var groups []string
	if raw, ok := claims["cognito:groups"].([]any); ok {
		for _, g := range raw {
			if s, ok := g.(string); ok {
				groups = append(groups, s)
			}
		}
	}

	return &Claims{Subject: subject, Username: username, Groups: groups}, nil
}

type contextKey struct{}

var claimsKey contextKey

// Middleware rejects any request without a valid bearer token and attaches the
// verified claims to the request context.
func (v *Verifier) Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		header := r.Header.Get("Authorization")
		scheme, token, found := strings.Cut(header, " ")
		if !found || !strings.EqualFold(scheme, "Bearer") {
			unauthorized(w)
			return
		}

		claims, err := v.Verify(strings.TrimSpace(token))
		if err != nil {
			unauthorized(w)
			return
		}

		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), claimsKey, claims)))
	})
}

func unauthorized(w http.ResponseWriter) {
	w.Header().Set("WWW-Authenticate", `Bearer realm="maroonledger"`)
	http.Error(w, "Unauthorized", http.StatusUnauthorized)
}

// ClaimsFrom returns the verified claims attached by Middleware.
//
// The boolean is false only when called from a handler that was not wrapped in
// Middleware -- a wiring bug, not a runtime condition. Handlers should treat it
// as a 500 rather than falling back to unscoped behaviour.
func ClaimsFrom(ctx context.Context) (*Claims, bool) {
	claims, ok := ctx.Value(claimsKey).(*Claims)
	return claims, ok
}
