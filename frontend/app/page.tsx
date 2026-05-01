'use client';

import Link from 'next/link';
import { StatCard } from '@/components/StatCard';
import { PriceChart } from '@/components/PriceChart';

export default function DashboardPage() {
  return (
    <div className="slide-up">
      <div className="page-header">
        <h1 className="page-title">Protocol Dashboard</h1>
        <p className="page-subtitle">Real-time overview of the OMNITRIX protocol on Ethereum</p>
      </div>

      {/* Stats Grid */}
      <div className="stats-grid">
        <StatCard
          title="Total Value Locked"
          value="$4.2M"
          sub="Across all pools"
          icon="🏦"
          badge="+12.4%"
          badgeType="green"
          trend={12.4}
        />
        <StatCard
          title="24h Volume"
          value="$892K"
          sub="Swap + lending"
          icon="📊"
          badge="Active"
          badgeType="green"
          trend={-3.2}
        />
        <StatCard
          title="Total Borrowed"
          value="$1.8M"
          sub="Lending pool"
          icon="💰"
          badge="Utilization 42%"
          badgeType="yellow"
        />
        <StatCard
          title="OMNI Staked"
          value="28.4M"
          sub="APY: 38.2%"
          icon="⚡"
          badge="Rewards live"
          badgeType="purple"
          trend={5.1}
        />
      </div>

      {/* Charts Row */}
      <div className="two-col" style={{ marginBottom: '2rem' }}>
        <div className="card">
          <PriceChart tokenSymbol="OMNI" basePrice={2.14} color="#6366f1" />
        </div>
        <div className="card">
          <PriceChart tokenSymbol="WETH" basePrice={2050} color="#00d4aa" />
        </div>
      </div>

      {/* CTA Cards */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))', gap: '1rem' }}>
        {[
          {
            href: '/swap',
            icon: '🔄',
            title: 'Swap Tokens',
            desc: 'Trade any pair with 0.3% fee and on-chain price impact protection.',
            btn: 'Start Swapping',
            color: '#6366f1',
            doodle: '💸',
          },
          {
            href: '/lending',
            icon: '🏛️',
            title: 'Lend & Borrow',
            desc: 'Deposit collateral and borrow up to 75% LTV with real-time health factor.',
            btn: 'Open Position',
            color: '#00d4aa',
            doodle: '🚀',
          },
          {
            href: '/staking',
            icon: '⚡',
            title: 'Stake LP Tokens',
            desc: 'Earn OMNI rewards by staking your liquidity provider tokens.',
            btn: 'Stake Now',
            color: '#f0c14b',
            doodle: '🦄',
          },
        ].map(({ href, icon, title, desc, btn, color, doodle }) => (
          <div key={href} className="card doodle-container" style={{ display: 'flex', flexDirection: 'column' }}>
            <div className="doodle">{doodle}</div>
            <div style={{ fontSize: '2rem', marginBottom: '0.75rem', transform: 'translateZ(0)' }}>{icon}</div>
            <h2 style={{ fontSize: '1.1rem', fontWeight: 700, marginBottom: '0.5rem' }}>{title}</h2>
            <p style={{ color: 'var(--text-secondary)', fontSize: '0.88rem', lineHeight: 1.6, flex: 1, marginBottom: '1.25rem' }}>{desc}</p>
            <Link href={href}>
              <button
                className="btn btn-outline"
                style={{ width: '100%', borderColor: `${color}50`, color }}
              >
                {btn} →
              </button>
            </Link>
          </div>
        ))}
      </div>

      {/* Protocol info */}
      <div className="card" style={{ marginTop: '1.5rem', display: 'flex', gap: '2rem', flexWrap: 'wrap' }}>
        <div>
          <div className="card-title">Active Pairs</div>
          <div style={{ fontSize: '1.3rem', fontWeight: 700 }}>3</div>
        </div>
        <div>
          <div className="card-title">Supported Assets</div>
          <div style={{ fontSize: '1.3rem', fontWeight: 700 }}>WETH · USDC · OMNI</div>
        </div>
        <div>
          <div className="card-title">Network</div>
          <div style={{ fontSize: '1.3rem', fontWeight: 700 }}>Ethereum Sepolia</div>
        </div>
        <div>
          <div className="card-title">Audited</div>
          <span className="badge badge-yellow">Testnet Only</span>
        </div>
        <div style={{ marginLeft: 'auto', alignSelf: 'center' }}>
          <span className="badge badge-green" style={{ padding: '0.4rem 0.9rem', fontSize: '0.8rem' }}>
            🟢 All Systems Operational
          </span>
        </div>
      </div>
    </div>
  );
}
