import { useState, useMemo, useId } from 'react';

// Charts are hand-built SVG rather than a charting library for one specific
// reason: every colour here is a CSS custom property, so light/dark theming is
// a variable swap with no re-render and no JS reading computed styles.

export function money(value, { compact = false, sign = false } = {}) {
  const abs = Math.abs(value);
  const prefix = sign && value > 0 ? '+' : value < 0 ? '-' : '';

  if (compact && abs >= 1000) {
    const units = [
      [1e9, 'B'],
      [1e6, 'M'],
      [1e3, 'K'],
    ];
    for (const [size, suffix] of units) {
      if (abs >= size) {
        // One decimal, but never a trailing ".0" -- "$9.8K" not "$9.8K" vs "$10.0K".
        const scaled = (abs / size).toFixed(abs / size < 10 ? 1 : 0);
        return `${prefix}$${scaled.replace(/\.0$/, '')}${suffix}`;
      }
    }
  }

  return `${prefix}$${abs.toLocaleString('en-US', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })}`;
}

/**
 * Sparkline — trend at a glance, no axes, no labels.
 *
 * Deliberately has no tooltip: it sits inside a row that is itself clickable,
 * and a hover target inside a hover target is a usability trap. The detail
 * view is where the same series gets a readable axis.
 */
export function Sparkline({ values, width = 78, height = 26, stroke = 'var(--brand)' }) {
  const points = useMemo(() => {
    if (!values || values.length < 2) return null;

    const min = Math.min(...values);
    const max = Math.max(...values);
    // A flat series has zero range; dividing by it yields NaN and the path
    // silently disappears. Centring it is the honest rendering.
    const range = max - min || 1;
    const step = width / (values.length - 1);
    // 1px inset top and bottom so a 2px stroke is not clipped at the extremes.
    const usable = height - 2;

    return values
      .map((v, i) => `${(i * step).toFixed(2)},${(1 + usable - ((v - min) / range) * usable).toFixed(2)}`)
      .join(' ');
  }, [values, width, height]);

  if (!points) return <svg width={width} height={height} aria-hidden="true" />;

  return (
    <svg width={width} height={height} viewBox={`0 0 ${width} ${height}`} aria-hidden="true">
      <polyline
        points={points}
        fill="none"
        stroke={stroke}
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
        vectorEffect="non-scaling-stroke"
      />
    </svg>
  );
}

/**
 * BalanceArea — balance over time, one series.
 *
 * One series means no legend: the card title names it. A crosshair and tooltip
 * are the default for a line/area chart, not an enhancement, so the reader can
 * recover an exact value at any date rather than estimating against gridlines.
 */
export function BalanceArea({ series, height = 260 }) {
  const [hover, setHover] = useState(null);
  const gradientId = useId();

  const W = 900;
  const H = height;
  const pad = { top: 16, right: 14, bottom: 26, left: 62 };

  const geom = useMemo(() => {
    if (!series || series.length < 2) return null;

    const values = series.map((d) => d.balance);
    let min = Math.min(...values);
    let max = Math.max(...values);

    // Never force a zero baseline on a balance chart: with values clustered
    // around 4,200 a zero floor flattens the entire line into a straight edge
    // and hides the variation the chart exists to show.
    const span = max - min || Math.abs(max) || 1;
    min -= span * 0.12;
    max += span * 0.12;

    const plotW = W - pad.left - pad.right;
    const plotH = H - pad.top - pad.bottom;
    const x = (i) => pad.left + (i / (series.length - 1)) * plotW;
    const y = (v) => pad.top + plotH - ((v - min) / (max - min)) * plotH;

    const line = series.map((d, i) => `${x(i)},${y(d.balance)}`).join(' ');
    const area = `${pad.left},${pad.top + plotH} ${line} ${pad.left + plotW},${pad.top + plotH}`;

    // Four ticks is enough to read level without turning the plot into a grid.
    const ticks = Array.from({ length: 4 }, (_, i) => min + ((max - min) / 3) * i);

    return { x, y, line, area, ticks, plotW, plotH };
  }, [series, H, pad.left, pad.right, pad.top, pad.bottom]);

  if (!geom) {
    return <div className="chart-empty">Not enough history to plot yet</div>;
  }

  const onMove = (e) => {
    const rect = e.currentTarget.getBoundingClientRect();
    // The SVG scales to its container, so pointer position has to be mapped
    // back into viewBox units before it can be turned into an index.
    const svgX = ((e.clientX - rect.left) / rect.width) * W;
    const ratio = (svgX - pad.left) / geom.plotW;
    const index = Math.round(ratio * (series.length - 1));

    if (index < 0 || index >= series.length) {
      setHover(null);
      return;
    }
    setHover({ index, left: ((geom.x(index) / W) * rect.width) });
  };

  const point = hover ? series[hover.index] : null;

  return (
    <div className="chart">
      <svg
        viewBox={`0 0 ${W} ${H}`}
        preserveAspectRatio="none"
        style={{ height }}
        onMouseMove={onMove}
        onMouseLeave={() => setHover(null)}
        role="img"
        aria-label="Account balance over time"
      >
        <defs>
          {/* Three stops rather than two: a linear ramp to zero leaves a
              visible hard edge partway down on dark surfaces, where the fill
              and the card background are close in luminance. */}
          <linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="var(--series-1)" stopOpacity="0.34" />
            <stop offset="55%" stopColor="var(--series-1)" stopOpacity="0.12" />
            <stop offset="100%" stopColor="var(--series-1)" stopOpacity="0" />
          </linearGradient>
        </defs>

        {/* Gridlines are recessive: they orient the eye and must never compete
            with the data. */}
        {geom.ticks.map((t, i) => (
          <g key={i}>
            <line
              x1={pad.left}
              x2={W - pad.right}
              y1={geom.y(t)}
              y2={geom.y(t)}
              stroke="var(--grid)"
              strokeWidth="1"
            />
            <text
              className="chart-axis-label"
              x={pad.left - 9}
              y={geom.y(t) + 3.5}
              textAnchor="end"
            >
              {money(t, { compact: true }).replace('$-', '-$')}
            </text>
          </g>
        ))}

        <polygon points={geom.area} fill={`url(#${gradientId})`} />
        <polyline
          points={geom.line}
          fill="none"
          stroke="var(--series-1)"
          strokeWidth="2"
          strokeLinejoin="round"
          strokeLinecap="round"
          vectorEffect="non-scaling-stroke"
        />

        {point && (
          <g>
            <line
              x1={geom.x(hover.index)}
              x2={geom.x(hover.index)}
              y1={pad.top}
              y2={pad.top + geom.plotH}
              stroke="var(--axis)"
              strokeWidth="1"
              strokeDasharray="3 3"
              vectorEffect="non-scaling-stroke"
            />
            {/* A surface-coloured ring keeps the marker legible wherever it
                lands on the filled area. */}
            <circle
              cx={geom.x(hover.index)}
              cy={geom.y(point.balance)}
              r="5"
              fill="var(--series-1)"
              stroke="var(--surface)"
              strokeWidth="2"
            />
          </g>
        )}

        {/* Endpoint dates only. A label on every point is noise. */}
        <text className="chart-axis-label" x={pad.left} y={H - 7} textAnchor="start">
          {formatDay(series[0].date)}
        </text>
        <text className="chart-axis-label" x={W - pad.right} y={H - 7} textAnchor="end">
          {formatDay(series[series.length - 1].date)}
        </text>
      </svg>

      {point && (
        <div className="tooltip" style={{ left: hover.left, top: 0 }}>
          <div className="tooltip-date">{formatDay(point.date, true)}</div>
          <div className="tooltip-value">{money(point.balance)}</div>
        </div>
      )}
    </div>
  );
}

// Fixed category-to-slot assignment.
//
// Colour follows the category, never its position in the sorted list -- so
// filtering or a change in ranking never repaints the survivors. Eight
// categories get a validated hue; everything else, including the "Other"
// rollup, is deliberately neutral so a minor category can never impersonate a
// named one. This is why the list is a map rather than an index into an array.
const CATEGORY_COLORS = {
  housing: 'var(--series-1)',
  transport: 'var(--series-2)',
  dining: 'var(--series-3)',
  groceries: 'var(--series-4)',
  utilities: 'var(--series-5)',
  transfer: 'var(--series-6)',
  entertainment: 'var(--series-7)',
  healthcare: 'var(--series-8)',
};

// Account type is a small closed set, so each gets its own validated hue.
// Keyed on the type rather than the row's position, for the same reason
// categories are: adding an account must not repaint the others.
const ACCOUNT_TYPE_COLORS = {
  checking: 'var(--series-2)',
  savings: 'var(--series-8)',
  credit: 'var(--series-1)',
  loan: 'var(--series-7)',
};

export function accountTypeColor(type) {
  return ACCOUNT_TYPE_COLORS[String(type).toLowerCase()] || 'var(--series-muted)';
}

export function categoryColor(category) {
  return CATEGORY_COLORS[String(category).toLowerCase()] || 'var(--series-muted)';
}

/**
 * CategoryBars — ranked magnitude.
 *
 * Ranked bars read magnitude far more accurately than a pie. Identity is
 * carried by the row label first and the hue second: the label is what makes
 * the chart legible without colour at all, which is also what satisfies the
 * relief rule for the two light-mode hues that sit below 3:1 on white.
 */
export function CategoryBars({ categories, limit = 6 }) {
  const rows = useMemo(() => {
    if (!categories) return [];

    // Spending only. Income in a "where money went" chart both inflates the
    // scale and lets a salary read as the largest expense.
    const spend = categories
      .filter((c) => c.total < 0)
      .map((c) => ({ ...c, magnitude: Math.abs(c.total) }))
      .sort((a, b) => b.magnitude - a.magnitude);

    if (spend.length <= limit) return spend;

    // Past the cap, the tail folds into a single "Other" row rather than
    // sprouting new categories that would each need their own colour.
    const head = spend.slice(0, limit);
    const tail = spend.slice(limit);
    return [
      ...head,
      {
        category: `Other (${tail.length})`,
        magnitude: tail.reduce((sum, c) => sum + c.magnitude, 0),
        count: tail.reduce((sum, c) => sum + c.count, 0),
      },
    ];
  }, [categories, limit]);

  if (!rows.length) {
    return <div className="chart-empty">No spending in this period</div>;
  }

  const max = Math.max(...rows.map((r) => r.magnitude));
  const total = rows.reduce((sum, r) => sum + r.magnitude, 0);

  return (
    <div>
      {rows.map((row) => (
        <div className="bar-row" key={row.category}>
          <div className="bar-label" title={row.category}>
            {row.category}
          </div>
          <div className="bar-track">
            <div
              className="bar-fill"
              style={{
                width: `${Math.max((row.magnitude / max) * 100, 1.5)}%`,
                // Fades toward the surface along its length, which keeps the
                // bar's leading edge -- the end the eye measures against -- the
                // most saturated part of the mark.
                background: `linear-gradient(90deg, ${categoryColor(row.category)} 0%, color-mix(in srgb, ${categoryColor(row.category)} 42%, transparent) 100%)`,
              }}
              title={`${row.category}: ${money(row.magnitude)}`}
            />
          </div>
          <div className="bar-value">
            {money(row.magnitude, { compact: true })}
            <span style={{ color: 'var(--text-3)', marginLeft: 6 }}>
              {total > 0 ? `${Math.round((row.magnitude / total) * 100)}%` : ''}
            </span>
          </div>
        </div>
      ))}
    </div>
  );
}

function formatDay(iso, long = false) {
  // Parsed as UTC noon: a bare YYYY-MM-DD is UTC midnight, which renders as the
  // previous day for anyone west of Greenwich.
  const d = new Date(`${iso}T12:00:00Z`);
  return d.toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    ...(long ? { year: 'numeric' } : {}),
  });
}
