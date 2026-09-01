/**
 * Stat: one headline figure.
 *
 * Lives here because the dashboard and the account view had byte-identical
 * copies apart from one optional prop, which is exactly how two copies drift
 * into looking subtly different.
 */
function Stat({ label, value, valueClass = '', foot, footNote }) {
  return (
    <div className="stat">
      <div className="stat-label">{label}</div>
      <div className={`stat-value ${valueClass}`}>{value}</div>
      {(foot || footNote) && (
        <div className="stat-foot">
          {foot}
          {footNote && <span>{footNote}</span>}
        </div>
      )}
    </div>
  );
}

export default Stat;
