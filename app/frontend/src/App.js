import { useState, useEffect, useCallback } from 'react';
import Dashboard from './Dashboard';
import AccountDetail from './AccountDetail';
import Insights from './Insights';
import Login from './Login';
import { getToken, signOut, authMode, completeCognitoSignIn } from './auth';
import { getMe } from './api';
import { useTheme } from './theme';
import {
  IconDashboard,
  IconInsights,
  IconSun,
  IconMoon,
  IconSignOut,
} from './components/Icons';
import './styles/App.css';

const NAV = [
  { id: 'dashboard', label: 'Dashboard', Icon: IconDashboard },
  { id: 'insights', label: 'Insights', Icon: IconInsights },
];

function App() {
  const { theme, toggle } = useTheme();
  const [view, setView] = useState('dashboard');
  const [selectedAccount, setSelectedAccount] = useState(null);
  const [user, setUser] = useState(null);
  const [ready, setReady] = useState(false);
  const [authError, setAuthError] = useState(null);

  const loadUser = useCallback(async () => {
    if (!getToken()) {
      setUser(null);
      return;
    }
    try {
      const res = await getMe();
      setUser(res.data);
    } catch {
      // A 401 is handled by the interceptor, which returns us to sign-in.
      setUser(null);
    }
  }, []);

  useEffect(() => {
    (async () => {
      try {
        // Handles the redirect back from the Cognito hosted UI. A no-op in dev
        // mode and on any load without an authorization code.
        if (authMode === 'cognito') {
          await completeCognitoSignIn();
        }
      } catch (err) {
        setAuthError(err.message);
      }
      await loadUser();
      setReady(true);
    })();
  }, [loadUser]);

  if (!ready) {
    return <div className="loading">Loading…</div>;
  }

  if (!user) {
    return (
      <>
        {authError && (
          <div className="auth" style={{ minHeight: 'auto', paddingBottom: 0 }}>
            <div className="alert" style={{ maxWidth: 384, width: '100%' }}>
              {authError}
            </div>
          </div>
        )}
        <Login onSignedIn={loadUser} theme={theme} onToggleTheme={toggle} />
      </>
    );
  }

  const goto = (id) => {
    setSelectedAccount(null);
    setView(id);
  };

  const openAccount = (account) => {
    setSelectedAccount(account);
    setView('dashboard');
  };

  const initial = (user.username || 'u').charAt(0).toUpperCase();

  return (
    <div className="app">
      <aside className="rail">
        <div className="rail-brand">
          <div className="rail-mark">M</div>
          <div className="rail-name">MaroonLedger</div>
        </div>

        <p className="rail-label">Menu</p>
        {NAV.map(({ id, label, Icon }) => (
          <button
            key={id}
            className={`rail-link ${view === id && !selectedAccount ? 'active' : ''}`}
            onClick={() => goto(id)}
            aria-current={view === id && !selectedAccount ? 'page' : undefined}
          >
            <Icon />
            {label}
          </button>
        ))}

        <p className="rail-label">Infrastructure</p>
        <div className="rail-fact">
          <span>Region</span>
          <span className="rail-fact-value">us-east-2</span>
        </div>
        <div className="rail-fact">
          <span>Compute</span>
          <span className="rail-fact-value">ECS Fargate</span>
        </div>
        <div className="rail-fact">
          <span>Database</span>
          <span className="rail-fact-value">RDS Postgres</span>
        </div>
        <div className="rail-fact">
          <span>Identity</span>
          <span className="rail-fact-value">
            {authMode === 'cognito' ? 'Cognito' : 'Dev IdP'}
          </span>
        </div>

        <div className="rail-foot">
          <div className="rail-user">
            <div className="rail-avatar">{initial}</div>
            <div style={{ minWidth: 0, flex: 1 }}>
              <div className="rail-user-name">{user.username || 'Signed in'}</div>
              <div className="rail-user-sub">Signed in</div>
            </div>
            <button
              className="rail-link"
              style={{ width: 'auto', padding: 6 }}
              onClick={signOut}
              title="Sign out"
              aria-label="Sign out"
            >
              <IconSignOut />
            </button>
          </div>
        </div>
      </aside>

      <div className="main">
        <header className="topbar">
          <div>
            <h1 className="topbar-title">
              {selectedAccount
                ? selectedAccount.name
                : view === 'insights'
                  ? 'Insights'
                  : 'Dashboard'}
            </h1>
            <p className="topbar-sub">
              {selectedAccount
                ? 'Account activity and AI analysis'
                : view === 'insights'
                  ? 'Model-generated analysis of your spending'
                  : 'Balance, activity and anomalies across your accounts'}
            </p>
          </div>

          <div className="topbar-actions">
            <button
              className="icon-btn"
              onClick={toggle}
              title={`Switch to ${theme === 'dark' ? 'light' : 'dark'} mode`}
              aria-label={`Switch to ${theme === 'dark' ? 'light' : 'dark'} mode`}
            >
              {theme === 'dark' ? <IconSun /> : <IconMoon />}
            </button>
          </div>
        </header>

        {selectedAccount ? (
          <AccountDetail
            account={selectedAccount}
            onBack={() => setSelectedAccount(null)}
          />
        ) : view === 'insights' ? (
          <Insights />
        ) : (
          <Dashboard onSelectAccount={openAccount} />
        )}
      </div>
    </div>
  );
}

export default App;
