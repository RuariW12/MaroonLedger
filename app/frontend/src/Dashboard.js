import { useState, useEffect, useCallback } from 'react';
import { getSummary, createAccount } from './api';
import { BalanceArea, CategoryBars, Sparkline, money, accountTypeColor } from './components/Charts';
import { IconPlus, IconAlert } from './components/Icons';
import Stat from './components/Stat';

const RANGES = [
  { days: 30, label: '30D' },
  { days: 90, label: '90D' },
  { days: 365, label: '1Y' },
];

const ACCOUNT_TYPES = ['checking', 'savings', 'credit', 'loan'];

function Dashboard({ onSelectAccount }) {
  const [summary, setSummary] = useState(null);
  const [days, setDays] = useState(90);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [showForm, setShowForm] = useState(false);
  const [form, setForm] = useState({ name: '', type: 'checking', balance: '' });
  const [saving, setSaving] = useState(false);

  const load = useCallback(async (range) => {
    setLoading(true);
    setError(null);
    try {
      const res = await getSummary({ days: range });
      setSummary(res.data);
    } catch {
      setError('Could not load your dashboard.');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load(days);
  }, [load, days]);

  const submit = async (e) => {
    e.preventDefault();
    setSaving(true);
    try {
      await createAccount({
        name: form.name,
        type: form.type,
        balance: parseFloat(form.balance) || 0,
      });
      setForm({ name: '', type: 'checking', balance: '' });
      setShowForm(false);
      await load(days);
    } catch {
      setError('Could not create the account.');
    } finally {
      setSaving(false);
    }
  };

  if (loading && !summary) {
    return (
      <div className="content">
        <div className="card">
          <div className="chart-empty">Loading…</div>
        </div>
      </div>
    );
  }

  if (error && !summary) {
    return (
      <div className="content">
        <div className="alert">{error}</div>
      </div>
    );
  }

  const accounts = summary?.accounts ?? [];
  const series = summary?.balance_series ?? [];

  // Change across the window, taken from the series the chart already plots so
  // the headline figure and the line can never disagree.
  const first = series[0]?.balance ?? 0;
  const last = series[series.length - 1]?.balance ?? 0;
  const change = last - first;
  const changePct = first !== 0 ? (change / Math.abs(first)) * 100 : 0;

  return (
    <div className="content">
      <div className="stat-row">
        <Stat
          label="Net Balance"
          value={money(summary.net_balance)}
          foot={
            series.length > 1 && (
              <span className={`delta ${change >= 0 ? 'value-pos' : 'value-neg'}`}>
                {/* The arrow carries direction as well as the colour, so the
                    meaning survives for a colour-blind reader. */}
                {change >= 0 ? '↑' : '↓'} {money(Math.abs(change), { compact: true })}
                {first !== 0 && ` (${Math.abs(changePct).toFixed(1)}%)`}
              </span>
            )
          }
          footNote={`over ${days} days`}
        />
        <Stat
          label="Income"
          value={money(summary.total_inflow)}
          valueClass="value-pos"
          footNote={`${accounts.length} account${accounts.length === 1 ? '' : 's'}`}
        />
        <Stat
          label="Spending"
          value={money(summary.total_outflow)}
          valueClass="value-neg"
          // Only spending categories: income sitting in a "Spending" tile's
          // subtitle reads as though salary were an expense.
          footNote={`${summary.by_category.length} categories`}
        />
        <Stat
          label="Savings Rate"
          value={summary.total_inflow > 0 ? `${summary.savings_rate.toFixed(1)}%` : '—'}
          valueClass={summary.savings_rate >= 0 ? 'value-pos' : 'value-neg'}
          footNote={summary.total_inflow > 0 ? 'of income kept' : 'no income recorded'}
        />
      </div>

      <div className="card">
        <div className="card-head">
          <div>
            <div className="card-title">Balance over time</div>
            <div className="card-sub">
              Combined end-of-day balance across all accounts
            </div>
          </div>
          <div className="segmented">
            {RANGES.map((r) => (
              <button
                key={r.days}
                className={days === r.days ? 'active' : ''}
                onClick={() => setDays(r.days)}
                aria-pressed={days === r.days}
              >
                {r.label}
              </button>
            ))}
          </div>
        </div>
        <div className="card-body">
          <BalanceArea series={series} />
        </div>
      </div>

      <div className="grid-2">
        <div className="card">
          <div className="card-head">
            <div>
              <div className="card-title">Accounts</div>
              <div className="card-sub">{accounts.length} total</div>
            </div>
            <button className="btn btn-primary" onClick={() => setShowForm((v) => !v)}>
              <IconPlus width="15" height="15" />
              {showForm ? 'Cancel' : 'New account'}
            </button>
          </div>

          {showForm && (
            <div className="card-body" style={{ borderBottom: '1px solid var(--border)' }}>
              <form onSubmit={submit}>
                <div className="form-grid">
                  <div className="field">
                    <label className="field-label" htmlFor="acct-name">
                      Account name
                    </label>
                    <input
                      id="acct-name"
                      className="input"
                      placeholder="e.g. Primary Checking"
                      value={form.name}
                      onChange={(e) => setForm({ ...form, name: e.target.value })}
                      required
                      autoFocus
                    />
                  </div>
                  <div className="field">
                    <label className="field-label" htmlFor="acct-type">
                      Type
                    </label>
                    <select
                      id="acct-type"
                      className="select"
                      value={form.type}
                      onChange={(e) => setForm({ ...form, type: e.target.value })}
                    >
                      {ACCOUNT_TYPES.map((t) => (
                        <option key={t} value={t}>
                          {t.charAt(0).toUpperCase() + t.slice(1)}
                        </option>
                      ))}
                    </select>
                  </div>
                </div>
                <div className="form-grid" style={{ marginTop: 14 }}>
                  <div className="field">
                    <label className="field-label" htmlFor="acct-balance">
                      Starting balance
                    </label>
                    <input
                      id="acct-balance"
                      className="input"
                      type="number"
                      step="0.01"
                      placeholder="0.00"
                      value={form.balance}
                      onChange={(e) => setForm({ ...form, balance: e.target.value })}
                    />
                  </div>
                </div>
                <div className="form-actions">
                  <button className="btn btn-primary" type="submit" disabled={saving}>
                    {saving ? 'Creating…' : 'Create account'}
                  </button>
                </div>
              </form>
            </div>
          )}

          {accounts.length === 0 ? (
            <div className="empty">
              <div className="empty-title">No accounts yet</div>
              <div className="empty-hint">Create one to start tracking.</div>
            </div>
          ) : (
            accounts.map((a) => (
              <button
                key={a.id}
                className="row row-clickable"
                onClick={() => onSelectAccount(a)}
              >
                <div
                  className="row-icon"
                  style={{
                    background: `color-mix(in srgb, ${accountTypeColor(a.type)} 16%, transparent)`,
                    color: accountTypeColor(a.type),
                  }}
                >
                  {a.name.charAt(0).toUpperCase()}
                </div>
                <div className="row-main">
                  <div className="row-title">{a.name}</div>
                  <div className="row-meta">
                    <span
                      className="chip"
                      style={{
                        background: `color-mix(in srgb, ${accountTypeColor(a.type)} 14%, transparent)`,
                        color: accountTypeColor(a.type),
                      }}
                    >
                      {a.type}
                    </span>
                    <span>
                      Opened {new Date(a.created_at).toLocaleDateString()}
                    </span>
                  </div>
                </div>
                <div className="row-spark">
                  <Sparkline
                    values={a.sparkline}
                    stroke={trendColor(a.sparkline)}
                  />
                </div>
                <div className={`row-amount ${a.balance < 0 ? 'value-neg' : ''}`}>
                  {money(a.balance)}
                </div>
              </button>
            ))
          )}
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 18 }}>
          <div className="card">
            <div className="card-head">
              <div>
                <div className="card-title">Where money went</div>
                <div className="card-sub">Top spending categories, last {days} days</div>
              </div>
            </div>
            <div className="card-body">
              <CategoryBars categories={summary.by_category} />
            </div>
          </div>

          <div className="card">
            <div className="card-head">
              <div>
                <div className="card-title">Needs attention</div>
                <div className="card-sub">Transactions flagged as unusual</div>
              </div>
            </div>
            {summary.anomalies.length === 0 ? (
              <div className="empty">
                <div className="empty-title">Nothing unusual</div>
                <div className="empty-hint">
                  No transactions were flagged in this period.
                </div>
              </div>
            ) : (
              summary.anomalies.map((a) => (
                <div className="row" key={a.id}>
                  <div
                    className="row-icon"
                    style={{
                      background:
                        a.severity === 'high' ? 'var(--critical-soft)' : 'var(--warning-soft)',
                      color: a.severity === 'high' ? 'var(--critical)' : 'var(--warning)',
                    }}
                  >
                    <IconAlert width="16" height="16" />
                  </div>
                  <div className="row-main">
                    <div className="row-title">{a.description || 'Transaction'}</div>
                    <div className="row-meta">
                      {/* The word sits beside the colour, so severity is never
                          communicated by hue alone. */}
                      <span className={`chip chip-${a.severity}`}>{a.severity}</span>
                      <span>{a.account_name}</span>
                    </div>
                    {a.reason && <div className="row-note">{a.reason}</div>}
                  </div>
                  <div className="row-amount value-neg">{money(a.amount)}</div>
                </div>
              ))
            )}
          </div>
        </div>
      </div>
    </div>
  );
}


// Colour follows the account's own direction of travel, not its rank in the
// list, so adding an account never repaints the others.
function trendColor(values) {
  if (!values || values.length < 2) return 'var(--text-3)';
  return values[values.length - 1] >= values[0] ? 'var(--pos)' : 'var(--neg)';
}

export default Dashboard;
