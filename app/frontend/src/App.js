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
          <button
            className={`sidebar-link ${!selectedAccount ? 'active' : ''}`}
            onClick={() => setSelectedAccount(null)}
          >
            ◫ Dashboard
          </button>
        </nav>
        <div className="sidebar-footer">
          <p>v1.0.0 · AWS Deploy</p>
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
