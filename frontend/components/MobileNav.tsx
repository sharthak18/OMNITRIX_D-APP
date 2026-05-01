'use client';

/**
 * MobileNav — fixed bottom tab bar for mobile screens (<640px)
 *
 * Shown only on small screens via CSS (display: none on desktop).
 * Mirrors Navbar links with icons + short labels for quick thumb access.
 * Respects iOS safe-area-inset-bottom for notched devices.
 */

import Link from 'next/link';
import { usePathname } from 'next/navigation';

// ─── Config ──────────────────────────────────────────────────────────────────

const TABS = [
  { href: '/',        label: 'Home',  icon: '📊' },
  { href: '/swap',    label: 'Swap',  icon: '⇌'  },
  { href: '/lending', label: 'Lend',  icon: '🏦' },
  { href: '/staking', label: 'Stake', icon: '⚡' },
] as const;

// ─── Component ───────────────────────────────────────────────────────────────

export function MobileNav() {
  const pathname = usePathname();

  return (
    <nav
      className="mobile-bottom-nav"
      role="navigation"
      aria-label="Mobile bottom navigation"
    >
      <div className="mobile-bottom-nav-inner">
        {TABS.map(({ href, label, icon }) => {
          const isActive = pathname === href;
          return (
            <Link
              key={href}
              href={href}
              id={`mobile-nav-${label.toLowerCase()}`}
              className={`mobile-nav-item${isActive ? ' active' : ''}`}
              aria-current={isActive ? 'page' : undefined}
              aria-label={label}
            >
              <span className="mobile-nav-icon" aria-hidden="true">
                {icon}
              </span>
              <span>{label}</span>
            </Link>
          );
        })}
      </div>
    </nav>
  );
}
