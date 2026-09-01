import { useState } from 'react';
import { authMode, signIn } from './auth';
import { IconSun, IconMoon } from './components/Icons';

function Login({ onSignedIn, theme, onToggleTheme }) {
  const [username, setUsername] = useState('');
  const [error, setError] = useState(null);
  const [busy, setBusy] = useState(false);

  const submit = async (e) => {
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
    <div className="auth">
      <div className="auth-card">
        <div
          style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}
        >
          <div>
            <div className="auth-brand">
              <div className="rail-mark">M</div>
              <div className="auth-title">MaroonLedger</div>
            </div>
            <p className="auth-sub">Sign in to continue</p>
          </div>
          <button
            className="icon-btn"
            onClick={onToggleTheme}
            aria-label={`Switch to ${theme === 'dark' ? 'light' : 'dark'} mode`}
            title={`Switch to ${theme === 'dark' ? 'light' : 'dark'} mode`}
          >
            {theme === 'dark' ? <IconSun /> : <IconMoon />}
          </button>
        </div>

        <form onSubmit={submit}>
          {authMode === 'cognito' ? (
            <p className="field-hint">You'll be redirected to the hosted sign-in page.</p>
          ) : (
            <div className="field">
              <label className="field-label" htmlFor="username">
                Username
              </label>
              <input
                id="username"
                className="input"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                placeholder="e.g. ruari"
                autoFocus
                required
              />
              <span className="field-hint">
                Local development identity provider. Any username works.
              </span>
            </div>
          )}

          {error && (
            <div className="alert alert-mt">{error}</div>
          )}

          <button className="btn btn-primary auth-submit" type="submit" disabled={busy}>
            {busy
              ? 'Signing in…'
              : authMode === 'cognito'
                ? 'Continue to sign-in'
                : 'Sign in'}
          </button>
        </form>
      </div>
    </div>
  );
}

export default Login;
