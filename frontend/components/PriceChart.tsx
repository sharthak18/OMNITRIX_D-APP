'use client';

/**
 * PriceChart — 24h simulated price chart for display purposes.
 *
 * IMPORTANT: Math.random() is called inside useEffect (client-only) to avoid
 * React hydration mismatches. The server always renders a skeleton placeholder,
 * and the chart appears only after the component mounts on the client.
 */

import { useState, useEffect } from 'react';
import { AreaChart, Area, XAxis, YAxis, Tooltip, ResponsiveContainer } from 'recharts';

// ─── Types ────────────────────────────────────────────────────────────────────

interface DataPoint {
  time:  string;
  price: number;
}

interface PriceChartProps {
  tokenSymbol: string;
  basePrice?:  number;
  color?:      string;
}

// ─── Price data generator (client-only) ───────────────────────────────────────

/**
 * Builds a random-walk price history over `points` hours.
 * Must only be called inside useEffect — never at render time — to avoid
 * SSR/client output differences that trigger hydration errors.
 */
function generatePriceData(basePrice: number, points = 24): DataPoint[] {
  const data: DataPoint[] = [];
  let price = basePrice;

  for (let i = points; i >= 0; i--) {
    const change = (Math.random() - 0.48) * basePrice * 0.03;
    price = Math.max(price * 0.7, price + change);
    data.push({ time: `${i}h ago`, price: parseFloat(price.toFixed(4)) });
  }

  return data.reverse();
}

// ─── Tooltip ──────────────────────────────────────────────────────────────────

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function CustomTooltip({ active, payload }: any) {
  if (!active || !payload?.length) return null;
  return (
    <div style={{
      background:   'var(--bg-card)',
      border:       '1px solid var(--border)',
      borderRadius: '8px',
      padding:      '0.5rem 0.75rem',
      fontSize:     '0.82rem',
    }}>
      <div style={{ color: 'var(--accent-light)', fontWeight: 600 }}>
        ${payload[0].value.toFixed(4)}
      </div>
      <div style={{ color: 'var(--text-muted)' }}>
        {payload[0].payload.time}
      </div>
    </div>
  );
}

// ─── Component ────────────────────────────────────────────────────────────────

export function PriceChart({ tokenSymbol, basePrice = 2.0, color = '#6366f1' }: PriceChartProps) {
  // null = not yet generated (SSR state). Set only after mount.
  const [data, setData] = useState<DataPoint[] | null>(null);

  useEffect(() => {
    // This runs only in the browser, so Math.random() is safe here.
    setData(generatePriceData(basePrice));
  }, [basePrice]);

  // ── Skeleton shown during SSR and the initial client paint ────────────────
  if (!data) {
    return (
      <div>
        <div style={{ marginBottom: '1rem' }}>
          <div style={{ fontSize: '0.78rem', color: 'var(--text-muted)', marginBottom: '0.4rem' }}>
            {tokenSymbol}/USD · 24h
          </div>
          <div style={{ fontSize: '1.5rem', fontWeight: 700, color: 'var(--text-muted)' }}>
            —
          </div>
        </div>
        <div
          className="loading"
          style={{ height: 140, borderRadius: 8, background: 'var(--bg-secondary)' }}
        />
      </div>
    );
  }

  // ── Computed display values ───────────────────────────────────────────────
  const first     = data[0].price;
  const last      = data[data.length - 1].price;
  const pct       = ((last - first) / first * 100).toFixed(2);
  const isUp      = last >= first;
  const lineColor = isUp ? '#00d4aa' : '#ff4757';

  // ── Live chart ────────────────────────────────────────────────────────────
  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '1rem' }}>
        <div>
          <div style={{ fontSize: '0.78rem', color: 'var(--text-muted)', marginBottom: '0.25rem' }}>
            {tokenSymbol}/USD · 24h
          </div>
          <div style={{ fontSize: '1.5rem', fontWeight: 700 }}>
            ${last.toFixed(4)}
          </div>
        </div>
        <span className={`badge ${isUp ? 'badge-green' : 'badge-red'}`}>
          {isUp ? '+' : ''}{pct}%
        </span>
      </div>

      <ResponsiveContainer width="100%" height={140}>
        <AreaChart data={data} margin={{ top: 4, right: 0, left: -30, bottom: 0 }}>
          <defs>
            <linearGradient id={`grad-${tokenSymbol}`} x1="0" y1="0" x2="0" y2="1">
              <stop offset="5%"  stopColor={color} stopOpacity={0.25} />
              <stop offset="95%" stopColor={color} stopOpacity={0} />
            </linearGradient>
          </defs>
          <XAxis dataKey="time" hide />
          <YAxis domain={['auto', 'auto']} tick={{ fontSize: 10, fill: '#555872' }} />
          <Tooltip content={<CustomTooltip />} />
          <Area
            type="monotone"
            dataKey="price"
            stroke={lineColor}
            strokeWidth={2}
            fill={`url(#grad-${tokenSymbol})`}
            dot={false}
          />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  );
}
