import { useState } from 'react';
import { getInsights } from './api';
import { CategoryBars, money } from './components/Charts';

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
          : err.response?.status === 429
            ? 'Rate limit reached. Try again in a minute.'
            : 'Could not generate insights.'
      );
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="content">
      <div className="card">
        <div className="card-head">
          <div>
            <div className="card-title">Spending analysis</div>
            <div className="card-sub">
              {data
                ? `${data.period_start} → ${data.period_end}`
                : 'Aggregated category totals are sent for analysis, never individual transactions'}
            </div>
          </div>
          <button className="btn btn-primary" onClick={run} disabled={loading}>
            {loading ? 'Analysing…' : data ? 'Refresh analysis' : 'Analyse my spending'}
          </button>
        </div>

        <div className="card-body">
          {error && <div className="alert">{error}</div>}

          {!data && !error && !loading && (
            <div className="empty">
              <div className="empty-title">No analysis yet</div>
              <div className="empty-hint">
                Run an analysis to get a summary of where your money goes.
              </div>
            </div>
          )}

          {loading && !data && <div className="chart-empty">Generating…</div>}

          {data && (
            <>
              <p className="insight-summary">{data.summary}</p>

              {data.observations?.length > 0 && (
                <div className="insight-group">
                  <div className="insight-group-label">Observations</div>
                  <div className="insight-list">
                    {data.observations.map((o, i) => (
                      <div className="insight-item" key={i}>
                        <span className="insight-bullet">—</span>
                        <span>{o}</span>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {data.recommendations?.length > 0 && (
                <div className="insight-group">
                  <div className="insight-group-label">Recommendations</div>
                  <div className="insight-list">
                    {data.recommendations.map((r, i) => (
                      <div className="insight-item" key={i}>
                        <span className="insight-bullet">→</span>
                        <span>{r}</span>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              <div
                className="insight-group"
                style={{ display: 'flex', gap: 18, alignItems: 'center' }}
              >
                {/* Naming the provider keeps deterministic stub output from
                    being mistaken for real model inference. */}
                <span className="provider-tag">analysed by {data.provider}</span>
                <span className="provider-tag">
                  in {money(data.total_inflow, { compact: true })} · out{' '}
                  {money(data.total_outflow, { compact: true })}
                </span>
              </div>
            </>
          )}
        </div>
      </div>

      {data?.by_category?.length > 0 && (
        <div className="card">
          <div className="card-head">
            <div>
              <div className="card-title">Category breakdown</div>
              <div className="card-sub">The figures the analysis was based on</div>
            </div>
          </div>
          <div className="card-body">
            <CategoryBars categories={data.by_category} limit={8} />
          </div>
        </div>
      )}
    </div>
  );
}

export default Insights;
