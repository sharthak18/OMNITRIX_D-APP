'use client';

/**
 * Navbar — top navigation bar for OMNITRIX Protocol
 *
 * Desktop (≥640px): logo + nav links + network badge + wallet button
 * Mobile (<640px):  logo + hamburger button → slide drawer + wallet button
 *
 * Drawer closes automatically on route change.
 */

import { useState, useEffect, useCallback } from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { ConnectButton } from '@rainbow-me/rainbowkit';
import { useChainId } from 'wagmi';

// ─── Config ──────────────────────────────────────────────────────────────────

const NAV_LINKS = [
  { href: '/',        label: 'Dashboard', icon: '📊' },
  { href: '/swap',    label: 'Swap',      icon: '⇌' },
  { href: '/lending', label: 'Lend',      icon: '🏦' },
  { href: '/staking', label: 'Stake',     icon: '⚡' },
] as const;

// ─── Component ───────────────────────────────────────────────────────────────

export function Navbar() {
  const pathname        = usePathname();
  const chainId         = useChainId();
  const [open, setOpen] = useState(false);

  // Resolve a human-readable network name + color for the badge
  const networkName = chainId === 31337     ? 'Localhost' :
                      chainId === 11155111  ? 'Sepolia'   :
                      chainId === 1         ? 'Mainnet'   :
                      `Chain ${chainId}`;
  const networkBadge = chainId === 1 ? 'badge-green' : chainId === 31337 ? 'badge-yellow' : 'badge-purple';

  // Close the drawer whenever the route changes
  useEffect(() => { setOpen(false); }, [pathname]);

  // Close on Escape key
  const handleKeyDown = useCallback((e: KeyboardEvent) => {
    if (e.key === 'Escape') setOpen(false);
  }, []);

  useEffect(() => {
    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [handleKeyDown]);

  // Prevent body scroll when drawer is open on mobile
  useEffect(() => {
    document.body.style.overflow = open ? 'hidden' : '';
    return () => { document.body.style.overflow = ''; };
  }, [open]);

  return (
    <>
      {/* ── Top bar ─────────────────────────────────────────── */}
      <nav className="navbar" role="navigation" aria-label="Main navigation">

        {/* Logo */}
        <Link href="/" className="navbar-logo" aria-label="OMNITRIX home">
          <div className="logo-icon float-anim" aria-hidden="true">O</div>
          <span>OMNITRIX</span>
        </Link>

        {/* Desktop links (hidden on mobile via CSS) */}
        <div className="navbar-links" role="menubar">
          {NAV_LINKS.map(({ href, label }) => (
            <Link
              key={href}
              href={href}
              role="menuitem"
              className={`navbar-link${pathname === href ? ' active' : ''}`}
              aria-current={pathname === href ? 'page' : undefined}
            >
              {label}
            </Link>
          ))}
        </div>

        {/* Right side: network badge + wallet + hamburger */}
        <div className="navbar-right">
          <span className={`badge ${networkBadge}`} title={`Connected to ${networkName}`}>
            {networkName}
          </span>

          <ConnectButton showBalance={false} chainStatus="icon" accountStatus="avatar" />

          {/* Hamburger — visible only on mobile via CSS */}
          <button
            id="hamburger-btn"
            className={`hamburger-btn${open ? ' open' : ''}`}
            onClick={() => setOpen(prev => !prev)}
            aria-expanded={open}
            aria-controls="mobile-drawer"
            aria-label={open ? 'Close menu' : 'Open menu'}
          >
            <span aria-hidden="true" />
            <span aria-hidden="true" />
            <span aria-hidden="true" />
          </button>
        </div>
      </nav>

      {/* ── Mobile drawer overlay (click-away to close) ─────── */}
      <div
        id="mobile-drawer-overlay"
        className={`mobile-drawer-overlay${open ? ' open' : ''}`}
        onClick={() => setOpen(false)}
        aria-hidden="true"
      />

      {/* ── Mobile drawer ───────────────────────────────────── */}
      <aside
        id="mobile-drawer"
        className={`mobile-drawer${open ? ' open' : ''}`}
        role="navigation"
        aria-label="Mobile navigation"
        aria-hidden={!open}
      >
        {NAV_LINKS.map(({ href, label, icon }) => (
          <Link
            key={href}
            href={href}
            className={`mobile-drawer-link${pathname === href ? ' active' : ''}`}
            aria-current={pathname === href ? 'page' : undefined}
            tabIndex={open ? 0 : -1}
          >
            <span className="mobile-drawer-icon" aria-hidden="true">{icon}</span>
            {label}
          </Link>
        ))}
      </aside>
    </>
  );
}
