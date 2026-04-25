import { useState } from 'react';
import Dashboard from './Dashboard';
import AccountDetail from './AccountDetail';
import './styles/App.css';

function App() {
  const [selectedAccount, setSelectedAccount] = useState(null);

  return (
    <div className="app-layout">
      <aside className="sidebar">
        <h1 className="sidebar-logo">Maroon<span>Ledger</span></h1>
        <p className="sidebar-subtitle">Personal Finance</p>

        <nav className="sidebar-nav">
          <p className="sidebar-section-label">Navigation</p>
          <button
            className={`sidebar-link ${!selectedAccount ? 'active' : ''}`}
            onClick={() => setSelectedAccount(null)}
          >
            ◫ Dashboard
          </button>
          <button className="sidebar-link" disabled style={{ opacity: 0.4 }}>
            ◈ Analytics
          </button>
          <button className="sidebar-link" disabled style={{ opacity: 0.4 }}>
            ◉ Settings
          </button>
        </nav>

        <div className="sidebar-divider" />

        <p className="sidebar-section-label">Infrastructure</p>
        <div className="sidebar-link" style={{ cursor: 'default', fontSize: '12px' }}>
          <span>Region</span>
          <span style={{ marginLeft: 'auto', fontFamily: 'JetBrains Mono', color: 'var(--text-muted)' }}>us-east-2</span>
        </div>
        <div className="sidebar-link" style={{ cursor: 'default', fontSize: '12px' }}>
          <span>Backend</span>
          <span style={{ marginLeft: 'auto', fontFamily: 'JetBrains Mono', color: 'var(--text-muted)' }}>ECS Fargate</span>
        </div>
        <div className="sidebar-link" style={{ cursor: 'default', fontSize: '12px' }}>
          <span>Database</span>
          <span style={{ marginLeft: 'auto', fontFamily: 'JetBrains Mono', color: 'var(--text-muted)' }}>RDS Postgres</span>
        </div>

        <div className="sidebar-footer">
          <div className="sidebar-status">
            <div className="status-dot" />
            <span>All systems operational</span>
          </div>
          <p>v1.0.0 · Terraform + Go</p>
        </div>
      </aside>

      {selectedAccount ? (
        <AccountDetail
          account={selectedAccount}
          onBack={() => setSelectedAccount(null)}
        />
      ) : (
        <Dashboard onSelectAccount={setSelectedAccount} />
      )}
    </div>
  );
}

export default App;
