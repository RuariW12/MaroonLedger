import { useState } from 'react';
import { authMode, signIn } from './auth';

function Login({ onSignedIn }) {
  const [username, setUsername] = useState('');
  const [error, setError] = useState(null);
  const [busy, setBusy] = useState(false);

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError(null);
    setBusy(true);
    try {
      await signIn(username);
      // In Cognito mode signIn navigates away, so this only runs in dev mode.
      if (authMode !== 'cognito') {
        onSignedIn();
      }
    } catch (err) {
      setError(err.message || 'Sign-in failed');
      setBusy(false);
    }
  };

  return (
    <div className="login-shell">
      <div className="login-card">
        <h1 className="sidebar-logo">Maroon<span>Ledger</span></h1>
        <p className="sidebar-subtitle">Sign in to continue</p>

        <form onSubmit={handleSubmit}>
          {authMode === 'cognito' ? (
            <p className="login-hint">
              You'll be redirected to the hosted sign-in page.
            </p>
          ) : (
            <div className="form-field">
              <label className="form-label" htmlFor="username">Username</label>
              <input
                id="username"
                className="form-input"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                placeholder="e.g. ruari"
                autoFocus
                required
              />
              <p className="login-hint">
                Local development identity provider &mdash; any username works.
              </p>
            </div>
          )}

          {error && <p className="login-error">{error}</p>}

          <button type="submit" className="btn btn-primary login-submit" disabled={busy}>
            {busy ? 'Signing in…' : authMode === 'cognito' ? 'Continue to sign-in' : 'Sign in'}
          </button>
        </form>
      </div>
    </div>
  );
}

export default Login;
