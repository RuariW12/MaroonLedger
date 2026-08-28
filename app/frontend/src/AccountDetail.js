import { useState, useEffect, useCallback } from 'react';
import { getTransactions, createTransaction } from './api';
import { money } from './components/Charts';
import { IconBack, IconPlus } from './components/Icons';

function AccountDetail({ account, onBack }) {
  const [transactions, setTransactions] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [showForm, setShowForm] = useState(false);
  const [saving, setSaving] = useState(false);
  const [form, setForm] = useState({ amount: '', category: '', description: '', date: '' });

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await getTransactions(account.id);
      setTransactions(res.data);
    } catch {
      setError('Could not load transactions.');
    } finally {
      setLoading(false);
    }
  }, [account.id]);

  useEffect(() => {
    load();
  }, [load]);

  const submit = async (e) => {
    e.preventDefault();
    setSaving(true);
    setError(null);
    try {
      await createTransaction(account.id, {
        amount: parseFloat(form.amount),
        category: form.category,
        description: form.description,
        date: form.date,
      });
      setForm({ amount: '', category: '', description: '', date: '' });
      setShowForm(false);
      await load();
    } catch {
      setError('Could not add the transaction.');
    } finally {
      setSaving(false);
    }
  };

  const received = transactions.filter((t) => t.amount > 0).reduce((s, t) => s + t.amount, 0);
  const spent = transactions.filter((t) => t.amount < 0).reduce((s, t) => s + Math.abs(t.amount), 0);

  return (
    <div className="content">
      <div>
        <button className="btn btn-ghost" onClick={onBack}>
          <IconBack width="15" height="15" />
          Back to dashboard
        </button>
      </div>

      <div className="stat-row">
        <Stat label="Current Balance" value={money(account.balance)} />
        <Stat label="Received" value={money(received)} valueClass="value-pos" />
        <Stat label="Spent" value={money(spent)} valueClass="value-neg" />
        <Stat
          label="Transactions"
          value={String(transactions.length)}
          footNote={account.type}
        />
      </div>

      {error && <div className="alert">{error}</div>}

      <div className="card">
        <div className="card-head">
          <div>
            <div className="card-title">Transactions</div>
            <div className="card-sub">
              Newest first · categories marked <em>auto</em> were assigned by the model
            </div>
          </div>
          <button className="btn btn-primary" onClick={() => setShowForm((v) => !v)}>
            <IconPlus width="15" height="15" />
            {showForm ? 'Cancel' : 'New transaction'}
          </button>
        </div>

        {showForm && (
          <div className="card-body" style={{ borderBottom: '1px solid var(--border)' }}>
            <form onSubmit={submit}>
              <div className="form-grid">
                <div className="field">
                  <label className="field-label" htmlFor="tx-amount">
                    Amount
                  </label>
                  <input
                    id="tx-amount"
                    className="input"
                    type="number"
                    step="0.01"
                    placeholder="Negative for spending"
                    value={form.amount}
                    onChange={(e) => setForm({ ...form, amount: e.target.value })}
                    required
                    autoFocus
                  />
                </div>
                <div className="field">
                  <label className="field-label" htmlFor="tx-category">
                    Category
                  </label>
                  <input
                    id="tx-category"
                    className="input"
                    placeholder="Leave blank to categorise automatically"
                    value={form.category}
                    onChange={(e) => setForm({ ...form, category: e.target.value })}
                  />
                  <span className="field-hint">
                    Left empty, the description is classified for you.
                  </span>
                </div>
              </div>
              <div className="form-grid" style={{ marginTop: 14 }}>
                <div className="field">
                  <label className="field-label" htmlFor="tx-desc">
                    Description
                  </label>
                  <input
                    id="tx-desc"
                    className="input"
                    placeholder="e.g. Tesco Superstore"
                    value={form.description}
                    onChange={(e) => setForm({ ...form, description: e.target.value })}
                  />
                </div>
                <div className="field">
                  <label className="field-label" htmlFor="tx-date">
                    Date
                  </label>
                  <input
                    id="tx-date"
                    className="input"
                    type="date"
                    value={form.date}
                    onChange={(e) => setForm({ ...form, date: e.target.value })}
                  />
                </div>
              </div>
              <div className="form-actions">
                <button className="btn btn-primary" type="submit" disabled={saving}>
                  {saving ? 'Adding…' : 'Add transaction'}
                </button>
              </div>
            </form>
          </div>
        )}

        {loading ? (
          <div className="chart-empty">Loading…</div>
        ) : transactions.length === 0 ? (
          <div className="empty">
            <div className="empty-title">No transactions yet</div>
            <div className="empty-hint">Add one to start tracking this account.</div>
          </div>
        ) : (
          transactions.map((t) => (
            <div className="row" key={t.id}>
              <div className="row-main">
                <div className="row-title" style={{ textTransform: 'capitalize' }}>
                  {t.category}
                  {/* Marks a category the model chose rather than one the user
                      stated, so a suggestion is never mistaken for a fact. */}
                  {t.auto_categorized && (
                    <span
                      className="chip chip-auto"
                      style={{ marginLeft: 8 }}
                      title={`Categorised by ${t.ai_provider || 'AI'}`}
                    >
                      auto
                    </span>
                  )}
                  {t.anomaly_severity && t.anomaly_severity !== 'none' && (
                    <span
                      className={`chip chip-${t.anomaly_severity}`}
                      style={{ marginLeft: 6 }}
                      title={t.anomaly_reason}
                    >
                      {t.anomaly_severity}
                    </span>
                  )}
                </div>
                <div className="row-meta">
                  {t.description && <span>{t.description}</span>}
                  <span>{new Date(t.date).toLocaleDateString()}</span>
                </div>
                {t.anomaly_reason && t.anomaly_severity !== 'none' && (
                  <div className="row-note">{t.anomaly_reason}</div>
                )}
              </div>
              <div className={`row-amount ${t.amount < 0 ? 'value-neg' : 'value-pos'}`}>
                {money(t.amount, { sign: true })}
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  );
}

function Stat({ label, value, valueClass = '', footNote }) {
  return (
    <div className="stat">
      <div className="stat-label">{label}</div>
      <div className={`stat-value ${valueClass}`}>{value}</div>
      {footNote && (
        <div className="stat-foot">
          <span style={{ textTransform: 'capitalize' }}>{footNote}</span>
        </div>
      )}
    </div>
  );
}

export default AccountDetail;
