import { useState, useEffect } from 'react';
import { getAccounts, createAccount } from './api';

function Dashboard({ onSelectAccount }) {
  const [accounts, setAccounts] = useState([]);
  const [showForm, setShowForm] = useState(false);
  const [form, setForm] = useState({ name: '', type: 'checking', balance: '' });

  useEffect(() => {
    getAccounts().then(res => setAccounts(res.data));
  }, []);

  const handleSubmit = async (e) => {
    e.preventDefault();
    await createAccount({ ...form, balance: parseFloat(form.balance) || 0 });
    const res = await getAccounts();
    setAccounts(res.data);
    setForm({ name: '', type: 'checking', balance: '' });
    setShowForm(false);
  };

  const total = accounts.reduce((sum, a) => sum + a.balance, 0);
  const accountCount = accounts.length;
  const highestBalance = accounts.length > 0
    ? Math.max(...accounts.map(a => a.balance))
    : 0;

  return (
    <div className="main-content">
      <div className="page-header">
        <h1 className="page-title">Dashboard</h1>
        <p className="page-subtitle">Overview of your financial accounts</p>
      </div>

      <div className="summary-row">
        <div className="summary-card highlight">
          <p className="summary-label">Total Balance</p>
          <p className={`summary-value ${total >= 0 ? 'green' : 'red'}`}>
            ${total.toFixed(2)}
          </p>
          <p className="summary-change">{accountCount} active account{accountCount !== 1 ? 's' : ''}</p>
        </div>
        <div className="summary-card">
          <p className="summary-label">Highest Balance</p>
          <p className="summary-value">${highestBalance.toFixed(2)}</p>
          <p className="summary-change">across all accounts</p>
        </div>
        <div className="summary-card">
          <p className="summary-label">System Status</p>
          <p className="summary-value green">Active</p>
          <p className="summary-change">ECS Fargate · us-east-2</p>
        </div>
      </div>

      <div className="activity-bar">
        {[...Array(20)].map((_, i) => (
          <div
            key={i}
            className={`activity-segment ${i < accountCount * 3 ? 'filled' : i < accountCount * 5 ? 'filled-light' : ''}`}
          />
        ))}
      </div>

      <div className="section-header">
        <h2 className="section-title">Accounts</h2>
        <button className="btn btn-primary" onClick={() => setShowForm(!showForm)}>
          {showForm ? 'Cancel' : '+ New Account'}
        </button>
      </div>

      {showForm && (
        <div className="form-container">
          <p className="form-title">Create New Account</p>
          <form onSubmit={handleSubmit}>
            <div className="form-grid">
              <div className="form-field">
                <label className="form-label">Account Name</label>
                <input
                  type="text"
                  placeholder="e.g. Primary Checking"
                  value={form.name}
                  onChange={e => setForm({ ...form, name: e.target.value })}
                  className="form-input"
                  required
                />
              </div>
              <div className="form-field">
                <label className="form-label">Account Type</label>
                <select
                  value={form.type}
                  onChange={e => setForm({ ...form, type: e.target.value })}
                  className="form-select"
                >
                  <option value="checking">Checking</option>
                  <option value="savings">Savings</option>
                  <option value="credit">Credit</option>
                  <option value="loan">Loan</option>
                </select>
              </div>
            </div>
            <div className="form-grid single">
              <div className="form-field">
                <label className="form-label">Starting Balance</label>
                <input
                  type="number"
                  placeholder="0.00"
                  value={form.balance}
                  onChange={e => setForm({ ...form, balance: e.target.value })}
                  className="form-input"
                  step="0.01"
                />
              </div>
            </div>
            <button type="submit" className="btn btn-primary">Create Account</button>
          </form>
        </div>
      )}

      <div className="accounts-grid">
        {accounts.length === 0 ? (
          <div className="empty-state">
            <div className="empty-state-icon">◫</div>
            <p>No accounts yet</p>
            <p className="hint">Create your first account to get started</p>
          </div>
        ) : (
          accounts.map(account => (
            <div
              key={account.id}
              className="account-card"
              onClick={() => onSelectAccount(account)}
            >
              <div className="account-info">
                <p className="account-name">{account.name}</p>
                <div className="account-meta">
                  <span className={`account-type type-${account.type}`}>
                    {account.type}
                  </span>
                  <span className="account-date">
                    Opened {new Date(account.created_at).toLocaleDateString()}
                  </span>
                </div>
              </div>
              <p className="account-balance">${account.balance.toFixed(2)}</p>
            </div>
          ))
        )}
      </div>
    </div>
  );
}

export default Dashboard;
