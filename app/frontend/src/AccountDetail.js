import { useState, useEffect } from 'react';
import { getTransactions, createTransaction } from './api';

function AccountDetail({ account, onBack }) {
  const [transactions, setTransactions] = useState([]);
  const [showForm, setShowForm] = useState(false);
  const [form, setForm] = useState({ amount: '', category: '', description: '', date: '' });

  useEffect(() => {
    getTransactions(account.id).then(res => setTransactions(res.data));
  }, [account.id]);

  const handleSubmit = async (e) => {
    e.preventDefault();
    await createTransaction(account.id, {
      ...form,
      amount: parseFloat(form.amount),
    });
    const res = await getTransactions(account.id);
    setTransactions(res.data);
    setForm({ amount: '', category: '', description: '', date: '' });
    setShowForm(false);
  };

  const totalSpent = transactions.filter(t => t.amount < 0).reduce((sum, t) => sum + t.amount, 0);
  const totalReceived = transactions.filter(t => t.amount > 0).reduce((sum, t) => sum + t.amount, 0);

  return (
    <div className="main-content">
      <button className="btn-back" onClick={onBack}>← Back to Dashboard</button>

      <div className="detail-header">
        <div>
          <p className="detail-label">Account</p>
          <h1 className="page-title">{account.name}</h1>
          <span className={`account-type type-${account.type}`}>{account.type}</span>
        </div>
        <div style={{ textAlign: 'right' }}>
          <p className="detail-label">Current Balance</p>
          <p className="detail-balance">${account.balance.toFixed(2)}</p>
        </div>
      </div>

      <div className="info-row">
        <div className="info-item">
          <span className="info-label">Transactions</span>
          <span className="info-value">{transactions.length}</span>
        </div>
        <div className="info-item">
          <span className="info-label">Total Received</span>
          <span className="info-value" style={{ color: 'var(--green)' }}>+${totalReceived.toFixed(2)}</span>
        </div>
        <div className="info-item">
          <span className="info-label">Total Spent</span>
          <span className="info-value" style={{ color: 'var(--red)' }}>-${Math.abs(totalSpent).toFixed(2)}</span>
        </div>
        <div className="info-item">
          <span className="info-label">Opened</span>
          <span className="info-value">{new Date(account.created_at).toLocaleDateString()}</span>
        </div>
      </div>

      <div className="section-header">
        <h2 className="section-title">Transactions</h2>
        <button className="btn btn-primary" onClick={() => setShowForm(!showForm)}>
          {showForm ? 'Cancel' : '+ New Transaction'}
        </button>
      </div>

      {showForm && (
        <div className="form-container">
          <p className="form-title">Add Transaction</p>
          <form onSubmit={handleSubmit}>
            <div className="form-grid">
              <div className="form-field">
                <label className="form-label">Amount</label>
                <input
                  type="number"
                  placeholder="Negative for expenses"
                  value={form.amount}
                  onChange={e => setForm({ ...form, amount: e.target.value })}
                  className="form-input"
                  step="0.01"
                  required
                />
              </div>
              <div className="form-field">
                <label className="form-label">Category</label>
                <input
                  type="text"
                  placeholder="e.g. Groceries"
                  value={form.category}
                  onChange={e => setForm({ ...form, category: e.target.value })}
                  className="form-input"
                  required
                />
              </div>
            </div>
            <div className="form-grid">
              <div className="form-field">
                <label className="form-label">Description</label>
                <input
                  type="text"
                  placeholder="Optional details"
                  value={form.description}
                  onChange={e => setForm({ ...form, description: e.target.value })}
                  className="form-input"
                />
              </div>
              <div className="form-field">
                <label className="form-label">Date</label>
                <input
                  type="date"
                  value={form.date}
                  onChange={e => setForm({ ...form, date: e.target.value })}
                  className="form-input"
                />
              </div>
            </div>
            <button type="submit" className="btn btn-primary">Add Transaction</button>
          </form>
        </div>
      )}

      <div className="transaction-list">
        {transactions.length === 0 ? (
          <div className="empty-state">
            <div className="empty-state-icon">◎</div>
            <p>No transactions yet</p>
            <p className="hint">Add a transaction to start tracking</p>
          </div>
        ) : (
          transactions.map(t => (
            <div key={t.id} className="transaction-item">
              <div>
                <p className="transaction-category">{t.category}</p>
                <p className="transaction-description">{t.description}</p>
                <p className="transaction-date">{new Date(t.date).toLocaleDateString()}</p>
              </div>
              <p className={`transaction-amount ${t.amount < 0 ? 'amount-negative' : 'amount-positive'}`}>
                {t.amount < 0 ? '-' : '+'}${Math.abs(t.amount).toFixed(2)}
              </p>
            </div>
          ))
        )}
      </div>
    </div>
  );
}

export default AccountDetail;
