'use client';

interface StatCardProps {
  title: string;
  value: string;
  sub?: string;
  icon?: string;
  badge?: string;
  badgeType?: 'green' | 'yellow' | 'red' | 'purple';
  trend?: number; // percentage change
}

export function StatCard({ title, value, sub, icon, badge, badgeType = 'green', trend }: StatCardProps) {
  return (
    <div className="card slide-up" style={{ position: 'relative', overflow: 'hidden' }}>
      {/* Background glow accent */}
      <div style={{
        position: 'absolute', top: '-40px', right: '-40px',
        width: '120px', height: '120px',
        borderRadius: '50%',
        background: 'rgba(99,102,241,0.06)',
        pointerEvents: 'none',
      }} />

      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '0.75rem' }}>
        <div className="card-title">{title}</div>
        {icon && <span style={{ fontSize: '1.4rem' }}>{icon}</span>}
      </div>

      <div className="card-value">{value}</div>

      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: '0.5rem' }}>
        {sub && <div className="card-sub">{sub}</div>}
        <div style={{ display: 'flex', gap: '0.5rem', alignItems: 'center', marginLeft: 'auto' }}>
          {trend !== undefined && (
            <span style={{ fontSize: '0.78rem', fontWeight: 600, color: trend >= 0 ? 'var(--green)' : 'var(--red)' }}>
              {trend >= 0 ? '↑' : '↓'} {Math.abs(trend).toFixed(2)}%
            </span>
          )}
          {badge && <span className={`badge badge-${badgeType}`}>{badge}</span>}
        </div>
      </div>
    </div>
  );
}
