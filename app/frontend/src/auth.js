// Authentication for the MaroonLedger frontend.
//
// Two modes, chosen by REACT_APP_AUTH_MODE:
//
//   cognito  production. Authorization-code flow with PKCE against the Cognito
//            hosted UI. No client secret is involved, because a browser cannot
//            keep one.
//   dev      local development. Exchanges a username for a token from the
//            dev identity provider in app/cmd/devidp.
//
// Both produce an RS256 access token that the API verifies the same way, so
// the authenticated path is never simulated during development.
//
// Token storage: sessionStorage. This is readable by any script running on the
// page, so an XSS bug becomes a token disclosure. The stronger pattern is a
// backend-for-frontend holding the token in an httpOnly, SameSite cookie and
// proxying API calls. That is the right upgrade if this ever holds real money;
// sessionStorage is the deliberate, documented trade-off here, chosen over
// localStorage so the token dies with the tab rather than persisting on disk.

const MODE = process.env.REACT_APP_AUTH_MODE || 'dev';

const config = {
  devIdpUrl: process.env.REACT_APP_DEV_IDP_URL || 'http://localhost:9000',
  cognitoDomain: process.env.REACT_APP_COGNITO_DOMAIN,
  clientId: process.env.REACT_APP_COGNITO_CLIENT_ID,
  redirectUri: process.env.REACT_APP_REDIRECT_URI || window.location.origin + '/',
};

const TOKEN_KEY = 'ml.access_token';
const EXPIRY_KEY = 'ml.expires_at';
const VERIFIER_KEY = 'ml.pkce_verifier';
const STATE_KEY = 'ml.oauth_state';

export const authMode = MODE;

export function getToken() {
  const token = sessionStorage.getItem(TOKEN_KEY);
  const expiresAt = Number(sessionStorage.getItem(EXPIRY_KEY) || 0);

  // Treat a token within 30s of expiry as already gone, so a request is not
  // sent with a credential that expires in flight.
  if (!token || Date.now() > expiresAt - 30_000) {
    return null;
  }
  return token;
}

function storeToken(accessToken, expiresInSeconds) {
  sessionStorage.setItem(TOKEN_KEY, accessToken);
  sessionStorage.setItem(EXPIRY_KEY, String(Date.now() + expiresInSeconds * 1000));
}

export function signOut() {
  sessionStorage.removeItem(TOKEN_KEY);
  sessionStorage.removeItem(EXPIRY_KEY);

  if (MODE === 'cognito' && config.cognitoDomain) {
    const params = new URLSearchParams({
      client_id: config.clientId,
      logout_uri: config.redirectUri,
    });
    window.location.assign(`${config.cognitoDomain}/logout?${params}`);
    return;
  }
  window.location.reload();
}

// --- dev mode ---------------------------------------------------------------

export async function signInWithUsername(username) {
  const response = await fetch(`${config.devIdpUrl}/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username }),
  });
  if (!response.ok) {
    throw new Error('Sign-in failed');
  }

  const data = await response.json();
  storeToken(data.access_token, data.expires_in);
  return data;
}

// --- cognito mode (PKCE) ----------------------------------------------------

function randomUrlSafe(bytes = 48) {
  const buffer = new Uint8Array(bytes);
  crypto.getRandomValues(buffer);
  return base64Url(buffer);
}

function base64Url(bytes) {
  return btoa(String.fromCharCode(...new Uint8Array(bytes)))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

async function challengeFor(verifier) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier));
  return base64Url(digest);
}

// Sends the browser to the hosted UI. The verifier stays here; only its hash
// travels, so an intercepted authorization code cannot be redeemed without it.
export async function beginCognitoSignIn() {
  const verifier = randomUrlSafe();
  const state = randomUrlSafe(16);

  sessionStorage.setItem(VERIFIER_KEY, verifier);
  sessionStorage.setItem(STATE_KEY, state);

  const params = new URLSearchParams({
    response_type: 'code',
    client_id: config.clientId,
    redirect_uri: config.redirectUri,
    scope: 'openid email profile',
    code_challenge_method: 'S256',
    code_challenge: await challengeFor(verifier),
    state,
  });

  window.location.assign(`${config.cognitoDomain}/oauth2/authorize?${params}`);
}

// Completes the flow if the current URL carries an authorization code.
// Returns true when a token was obtained.
export async function completeCognitoSignIn() {
  const url = new URL(window.location.href);
  const code = url.searchParams.get('code');
  const state = url.searchParams.get('state');
  if (!code) return false;

  const expectedState = sessionStorage.getItem(STATE_KEY);
  const verifier = sessionStorage.getItem(VERIFIER_KEY);

  // Always clear the URL, so a failed or replayed attempt cannot be retried by
  // refreshing the page.
  window.history.replaceState({}, document.title, url.pathname);
  sessionStorage.removeItem(STATE_KEY);
  sessionStorage.removeItem(VERIFIER_KEY);

  // The state parameter ties this redirect to the sign-in this tab started.
  // Without checking it, an attacker can feed the user their own code and log
  // the victim into the attacker's account.
  if (!expectedState || state !== expectedState || !verifier) {
    throw new Error('Sign-in could not be verified. Please try again.');
  }

  const response = await fetch(`${config.cognitoDomain}/oauth2/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'authorization_code',
      client_id: config.clientId,
      redirect_uri: config.redirectUri,
      code,
      code_verifier: verifier,
    }),
  });
  if (!response.ok) {
    throw new Error('Could not complete sign-in');
  }

  const data = await response.json();
  storeToken(data.access_token, data.expires_in);
  return true;
}

export async function signIn(username) {
  if (MODE === 'cognito') {
    return beginCognitoSignIn();
  }
  return signInWithUsername(username);
}
