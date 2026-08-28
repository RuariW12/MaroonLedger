import { useState, useEffect, useCallback } from 'react';
import Dashboard from './Dashboard';
import AccountDetail from './AccountDetail';
import Insights from './Insights';
import Login from './Login';
import { getToken, signOut, authMode, completeCognitoSignIn } from './auth';
import { getMe } from './api';
import './styles/App.css';

function App() {
  const [selectedAccount, setSelectedAccount] = useState(null);
  const [view, setView] = useState('dashboard');
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
      // The interceptor sends us back to sign-in on a 401; anything else
      // just means we render as signed out.
      setUser(null);
    }
  }, []);

  useEffect(() => {
    (async () => {
      try {
        // Handles the redirect back from the Cognito hosted UI. A no-op in
        // dev mode and on any load without an authorization code.
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
    return <div className="login-shell"><p className="sidebar-subtitle">Loading…</p></div>;
  }

  if (!user) {
    return (
      <>
        {authError && <p className="login-error login-error-banner">{authError}</p>}
        <Login onSignedIn={loadUser} />
      </>
    );
  }

  const showDashboard = () => {
    setSelectedAccount(null);
    setView('dashboard');
  };

  return (
    <div className="app-layout">
      <aside className="sidebar">
        <h1 className="sidebar-logo">Maroon<span>Ledger</span></h1>
        <p className="sidebar-subtitle">Personal Finance</p>

        <nav className="sidebar-nav">
          <p className="sidebar-section-label">Navigation</p>
          <button
            className={`sidebar-link ${view === 'dashboard' && !selectedAccount ? 'active' : ''}`}
            onClick={showDashboard}
          >
            ◫ Dashboard
          </button>
          <button
            className={`sidebar-link ${view === 'insights' ? 'active' : ''}`}
            onClick={() => { setSelectedAccount(null); setView('insights'); }}
          >
            ◈ Insights
          </button>
        </nav>

        <div className="sidebar-divider" />

        <p className="sidebar-section-label">Infrastructure</p>
        <div className="sidebar-link sidebar-fact">
          <span>Region</span>
          <span className="sidebar-fact-value">us-east-2</span>
        </div>
        <div className="sidebar-link sidebar-fact">
          <span>Backend</span>
          <span className="sidebar-fact-value">ECS Fargate</span>
        </div>
        <div className="sidebar-link sidebar-fact">
          <span>Database</span>
          <span className="sidebar-fact-value">RDS Postgres</span>
        </div>
        <div className="sidebar-link sidebar-fact">
          <span>Identity</span>
          <span className="sidebar-fact-value">{authMode === 'cognito' ? 'Cognito' : 'Dev IdP'}</span>
        </div>

        <div className="sidebar-footer">
          <div className="sidebar-status">
            <div className="status-dot" />
            <span>Signed in as {user.username || 'user'}</span>
          </div>
          <button className="sidebar-signout" onClick={signOut}>Sign out</button>
          <p>v1.1.0 · Terraform + Go</p>
        </div>
      </aside>

      {selectedAccount ? (
        <AccountDetail account={selectedAccount} onBack={showDashboard} />
      ) : view === 'insights' ? (
        <div className="main-content">
          <div className="page-header">
            <h1 className="page-title">Insights</h1>
            <p className="page-subtitle">Model-generated analysis of your spending</p>
          </div>
          <Insights />
        </div>
      ) : (
        <Dashboard onSelectAccount={(a) => { setSelectedAccount(a); setView('dashboard'); }} />
      )}
    </div>
  );
}

export default App;
