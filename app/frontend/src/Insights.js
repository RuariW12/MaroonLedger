import { useState } from 'react';
import { getInsights } from './api';

function Insights() {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  const run = async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await getInsights();
      setData(res.data);
    } catch (err) {
      // 503 means the model itself is unreachable, which is worth
      // distinguishing from a generic failure.
      setError(
        err.response?.status === 503
          ? 'Insight generation is temporarily unavailable.'
          : 'Could not generate insights.'
      );
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="insights-panel">
      <div className="section-header">
        <div>
          <h2 className="section-title">Spending Insights</h2>
          {data && (
            <p className="insights-meta">
              {data.period_start} → {data.period_end} · analysed by {data.provider}
            </p>
          )}
        </div>
        <button className="btn btn-primary" onClick={run} disabled={loading}>
          {loading ? 'Analysing…' : data ? 'Refresh analysis' : 'Analyse my spending'}
        </button>
      </div>

      {error && <p className="login-error">{error}</p>}

      {data && (
        <div className="insights-body">
          <p className="insights-summary">{data.summary}</p>

          {data.observations?.length > 0 && (
            <div className="insights-group">
              <p className="insights-group-label">Observations</p>
              <ul className="insights-list">
                {data.observations.map((o, i) => <li key={i}>{o}</li>)}
              </ul>
            </div>
          )}

          {data.recommendations?.length > 0 && (
            <div className="insights-group">
              <p className="insights-group-label">Recommendations</p>
              <ul className="insights-list">
                {data.recommendations.map((r, i) => <li key={i}>{r}</li>)}
              </ul>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

export default Insights;
