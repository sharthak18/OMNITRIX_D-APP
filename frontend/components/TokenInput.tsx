'use client';

import { useAccount, useReadContract } from 'wagmi';
import { formatUnits } from 'viem';
import { ERC20_ABI } from '@/lib/contracts';

interface TokenInputProps {
  label: string;
  value: string;
  onChange?: (v: string) => void;
  tokenAddress?: `0x${string}`;
  tokenSymbol: string;
  tokenIcon: string;
  tokenDecimals?: number;
  readOnly?: boolean;
  placeholder?: string;
  onMax?: () => void;
}

export function TokenInput({
  label, value, onChange, tokenAddress, tokenSymbol, tokenIcon,
  tokenDecimals = 18, readOnly = false, placeholder = '0.0', onMax,
}: TokenInputProps) {
  const { address } = useAccount();

  const { data: balance } = useReadContract({
    address: tokenAddress,
    abi: ERC20_ABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: { enabled: !!address && !!tokenAddress },
  });

  const formattedBal = balance !== undefined
    ? parseFloat(formatUnits(balance, tokenDecimals)).toFixed(4)
    : '—';

  // Single-char icons (like 'D', '$') get a styled badge instead of raw text
  const isBadgeIcon = tokenIcon.length === 1;

  const inputId = `token-input-${label.toLowerCase().replace(/\s+/g, '-')}`;

  return (
    <label htmlFor={inputId} className="token-input-wrapper" style={{ display: 'block', cursor: 'text' }}>
      <div className="token-input-label">{label}</div>
      <div className="token-input-row">
        {/* readOnly outputs (quotes, loading) use text display to handle non-numeric strings */}
        {readOnly ? (
          <div
            className="token-amount-input"
            style={{
              display: 'flex',
              alignItems: 'center',
              color: value && !value.includes('Loading') ? 'var(--text-primary)' : 'var(--text-muted)',
              fontSize: value?.includes('Loading') ? '0.95rem' : undefined,
            }}
          >
            {value || placeholder}
          </div>
        ) : (
          <input
            id={inputId}
            className="token-amount-input"
            type="number"
            placeholder={placeholder}
            value={value}
            onChange={e => onChange?.(e.target.value)}
            readOnly={readOnly}
            min="0"
            step="any"
          />
        )}

        <div className="token-selector">
          {isBadgeIcon ? (
            <span
              className="token-icon"
              style={{
                display: 'inline-flex',
                alignItems: 'center',
                justifyContent: 'center',
                width: '22px',
                height: '22px',
                borderRadius: '50%',
                background: 'linear-gradient(135deg, var(--accent), #8b5cf6)',
                color: '#fff',
                fontSize: '0.75rem',
                fontWeight: 800,
                flexShrink: 0,
              }}
            >
              {tokenIcon}
            </span>
          ) : (
            <span className="token-icon">{tokenIcon}</span>
          )}
          <span className="token-symbol">{tokenSymbol}</span>
        </div>
      </div>
      {address && (
        <div className="token-balance" onClick={onMax}>
          Balance: <span>{formattedBal}</span>{onMax && ' · MAX'}
        </div>
      )}
    </label>
  );
}
