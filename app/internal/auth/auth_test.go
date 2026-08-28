package auth

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const (
	testKeyID    = "test-key"
	testClientID = "test-client"
)

// issuer is a stand-in user pool: it signs tokens and publishes the matching
// JWKS, so the verifier under test resolves keys exactly as it would against
// Cognito.
type issuer struct {
	key *rsa.PrivateKey
	url string
}

func newIssuer(t *testing.T) *issuer {
	t.Helper()

	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("generate key: %v", err)
	}
	iss := &issuer{key: key}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]any{
			"keys": []map[string]string{{
				"kty": "RSA", "use": "sig", "alg": "RS256", "kid": testKeyID,
				"n": base64.RawURLEncoding.EncodeToString(key.PublicKey.N.Bytes()),
				"e": base64.RawURLEncoding.EncodeToString([]byte{1, 0, 1}),
			}},
		})
	}))
	t.Cleanup(server.Close)

	iss.url = server.URL
	return iss
}

// sign mints a token, applying overrides on top of a valid baseline so each
// test can corrupt exactly one thing.
func (i *issuer) sign(t *testing.T, overrides map[string]any) string {
	t.Helper()

	claims := jwt.MapClaims{
		"sub":       "user-123",
		"token_use": "access",
		"client_id": testClientID,
		"username":  "ruari",
		"iss":       i.url,
		"iat":       time.Now().Unix(),
		"exp":       time.Now().Add(time.Hour).Unix(),
	}
	for k, v := range overrides {
		if v == nil {
			delete(claims, k)
			continue
		}
		claims[k] = v
	}

	token := jwt.NewWithClaims(jwt.SigningMethodRS256, claims)
	token.Header["kid"] = testKeyID
	signed, err := token.SignedString(i.key)
	if err != nil {
		t.Fatalf("sign: %v", err)
	}
	return signed
}

func newTestVerifier(t *testing.T, iss *issuer) *Verifier {
	t.Helper()

	v, err := NewVerifier(context.Background(), Config{
		Issuer:   iss.url,
		JWKSURL:  iss.url + "/.well-known/jwks.json",
		ClientID: testClientID,
	})
	if err != nil {
		t.Fatalf("new verifier: %v", err)
	}
	return v
}

func TestVerifyAcceptsValidToken(t *testing.T) {
	iss := newIssuer(t)
	v := newTestVerifier(t, iss)

	claims, err := v.Verify(iss.sign(t, nil))
	if err != nil {
		t.Fatalf("expected valid token to be accepted, got %v", err)
	}
	if claims.Subject != "user-123" {
		t.Errorf("Subject = %q, want %q", claims.Subject, "user-123")
	}
	if claims.Username != "ruari" {
		t.Errorf("Username = %q, want %q", claims.Username, "ruari")
	}
}

func TestVerifyRejects(t *testing.T) {
	iss := newIssuer(t)
	v := newTestVerifier(t, iss)

	tests := []struct {
		name      string
		overrides map[string]any
	}{
		// An ID token is issued for the frontend, not as an API credential.
		{"id token presented as access token", map[string]any{"token_use": "id"}},
		{"missing token_use", map[string]any{"token_use": nil}},
		// Signed by the right pool, but minted for a different app client.
		{"token for another client", map[string]any{"client_id": "someone-elses-app"}},
		{"missing client_id", map[string]any{"client_id": nil}},
		{"wrong issuer", map[string]any{"iss": "https://evil.example.com"}},
		{"expired", map[string]any{"exp": time.Now().Add(-time.Hour).Unix()}},
		{"no expiry at all", map[string]any{"exp": nil}},
		{"empty subject", map[string]any{"sub": ""}},
		{"missing subject", map[string]any{"sub": nil}},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if _, err := v.Verify(iss.sign(t, tc.overrides)); err == nil {
				t.Fatal("expected rejection, token was accepted")
			}
		})
	}
}

// A token signed by a key the issuer never published must not be trusted, even
// when every claim in it looks correct.
func TestVerifyRejectsForeignSigningKey(t *testing.T) {
	iss := newIssuer(t)
	v := newTestVerifier(t, iss)

	attacker, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("generate key: %v", err)
	}

	token := jwt.NewWithClaims(jwt.SigningMethodRS256, jwt.MapClaims{
		"sub": "user-123", "token_use": "access", "client_id": testClientID,
		"iss": iss.url, "exp": time.Now().Add(time.Hour).Unix(),
	})
	token.Header["kid"] = testKeyID
	signed, err := token.SignedString(attacker)
	if err != nil {
		t.Fatalf("sign: %v", err)
	}

	if _, err := v.Verify(signed); err == nil {
		t.Fatal("expected rejection of token signed by an unpublished key")
	}
}

// The classic JWT bypass: strip the signature and claim the algorithm is
// "none". WithValidMethods is what stops it.
func TestVerifyRejectsAlgNone(t *testing.T) {
	iss := newIssuer(t)
	v := newTestVerifier(t, iss)

	token := jwt.NewWithClaims(jwt.SigningMethodNone, jwt.MapClaims{
		"sub": "user-123", "token_use": "access", "client_id": testClientID,
		"iss": iss.url, "exp": time.Now().Add(time.Hour).Unix(),
	})
	signed, err := token.SignedString(jwt.UnsafeAllowNoneSignatureType)
	if err != nil {
		t.Fatalf("sign: %v", err)
	}

	if _, err := v.Verify(signed); err == nil {
		t.Fatal("expected rejection of alg=none token")
	}
}

func TestMiddlewareRequiresBearerToken(t *testing.T) {
	iss := newIssuer(t)
	v := newTestVerifier(t, iss)

	guarded := v.Middleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if _, ok := ClaimsFrom(r.Context()); !ok {
			t.Error("handler ran without claims in context")
		}
		w.WriteHeader(http.StatusOK)
	}))

	tests := []struct {
		name   string
		header string
		want   int
	}{
		{"no header", "", http.StatusUnauthorized},
		{"wrong scheme", "Basic " + iss.sign(t, nil), http.StatusUnauthorized},
		{"garbage token", "Bearer not-a-jwt", http.StatusUnauthorized},
		{"valid token", "Bearer " + iss.sign(t, nil), http.StatusOK},
		{"lowercase scheme accepted", "bearer " + iss.sign(t, nil), http.StatusOK},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, "/api/accounts", nil)
			if tc.header != "" {
				req.Header.Set("Authorization", tc.header)
			}
			rec := httptest.NewRecorder()
			guarded.ServeHTTP(rec, req)

			if rec.Code != tc.want {
				t.Errorf("status = %d, want %d", rec.Code, tc.want)
			}
		})
	}
}
