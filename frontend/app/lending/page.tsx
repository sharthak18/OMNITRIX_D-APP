'use client';

/**
 * Lending Page — OMNITRIX Protocol
 *
 * Allows users to:
 *  - Deposit collateral tokens into the lending pool
 *  - Withdraw previously deposited collateral
 *  - Borrow tokens against collateral (max 75% LTV)
 *  - Repay borrowed tokens (with accrued interest)
 *
 * Health Factor = (collateral value × liquidation threshold) / debt value
 * When health factor < 1.0 the position is liquidatable.
 */

import { useState } from 'react';
import {
  useAccount,
  useChainId,
  useWriteContract,
  useWaitForTransactionReceipt,
  useReadContract,
} from 'wagmi';
import { useQueryClient } from '@tanstack/react-query';
import { parseUnits, formatUnits, maxUint256 } from 'viem';

import { TokenInput } from '@/components/TokenInput';
import { getContracts, LENDING_ABI, ERC20_ABI } from '@/lib/contracts';
import { formatHealthFactor, healthFactorColor, formatAmount } from '@/lib/utils';
import { TOKENS } from '@/lib/utils';

// ─── Types ───────────────────────────────────────────────────────────────────

type Tab    = 'deposit' | 'withdraw' | 'borrow' | 'repay';
type TxState = 'idle' | 'approving' | 'pending' | 'success' | 'error';

const TAB_LABELS: Record<Tab, string> = {
  deposit:  'Deposit',
  withdraw: 'Withdraw',
  borrow:   'Borrow',
  repay:    'Repay',
};

// ─── Component ───────────────────────────────────────────────────────────────

export default function LendingPage() {
  const { address, isConnected } = useAccount();
  const chainId   = useChainId();
  const contracts = getContracts(chainId);

  // UI state
  const [activeTab,      setActiveTab]      = useState<Tab>('deposit');
  const [selectedToken,  setSelectedToken]  = useState<typeof TOKENS[number]>(TOKENS[1]); // Default: WETH
  const [amount,         setAmount]         = useState('');
  const [txStatus,       setTxStatus]       = useState<TxState>('idle');
  const [txHash,         setTxHash]         = useState<`0x${string}` | undefined>();
  const [errorMessage,   setErrorMessage]   = useState('');
  const queryClient = useQueryClient();

  // Refresh balances after successful transaction
  const refreshBalances = () => queryClient.invalidateQueries();

  // Resolve the selected token's on-chain address
  const tokenAddr: `0x${string}` =
    selectedToken.symbol === 'WETH'  ? contracts.WETH :
    selectedToken.symbol === 'USDC'  ? contracts.USDC :
    contracts.DefiToken;

  // Parse the user's input amount to bigint (in smallest units)
  const parsedAmount = amount ? parseUnits(amount, selectedToken.decimals) : 0n;

  // ─── On-chain reads (auto-refresh every 8 seconds) ───────────────────────

  /** User's deposited collateral and borrowed amount for the selected token */
  const { data: position } = useReadContract({
    address:      contracts.LendingPool,
    abi:          LENDING_ABI,
    functionName: 'positions',
    args:         address ? [address, tokenAddr] : undefined,
    query:        { enabled: !!address, refetchInterval: 8_000 },
  });

  /** Live debt including accrued interest (more accurate than position.borrowed) */
  const { data: liveDebt } = useReadContract({
    address:      contracts.LendingPool,
    abi:          LENDING_ABI,
    functionName: 'getUserDebt',
    args:         address ? [address, tokenAddr] : undefined,
    query:        { enabled: !!address, refetchInterval: 8_000 },
  });

  /** Overall health factor across ALL assets (1e18 = 1.0) */
  const { data: healthFactorRaw } = useReadContract({
    address:      contracts.LendingPool,
    abi:          LENDING_ABI,
    functionName: 'healthFactor',
    args:         address ? [address] : undefined,
    query:        { enabled: !!address, refetchInterval: 8_000 },
  });

  /** Annual interest rate for the selected asset (18-decimal fraction, e.g. 0.05e18 = 5%) */
  const { data: interestRate } = useReadContract({
    address:      contracts.LendingPool,
    abi:          LENDING_ABI,
    functionName: 'getInterestRate',
    args:         [tokenAddr],
    query:        { refetchInterval: 30_000 },
  });

  /** What percentage of deposits are currently borrowed (0–1e18) */
  const { data: utilizationRaw } = useReadContract({
    address:      contracts.LendingPool,
    abi:          LENDING_ABI,
    functionName: 'getUtilizationRate',
    args:         [tokenAddr],
    query:        { refetchInterval: 30_000 },
  });

  /**
   * ERC-20 allowance: how many tokens the LendingPool
   * is authorised to pull from the user's wallet.
   * Required for deposit and repay actions.
   */
  const { data: allowance } = useReadContract({
    address:      tokenAddr,
    abi:          ERC20_ABI,
    functionName: 'allowance',
    args:         address ? [address, contracts.LendingPool] : undefined,
    query:        { enabled: !!address },
  });

  // ─── Derived values ───────────────────────────────────────────────────────

  // Deposit and repay both pull tokens from the user → need approval
  const requiresApproval =
    (activeTab === 'deposit' || activeTab === 'repay') &&
    parsedAmount > 0n &&
    (allowance ?? 0n) < parsedAmount;

  const deposited    = position?.[0] ?? 0n;
  const borrowedRaw  = position?.[1] ?? 0n;
  const currentDebt  = liveDebt ?? borrowedRaw;

  // Health factor: convert from 1e18 fixed-point to a display string
  const hfValue  = healthFactorRaw ?? 0n;
  const hfString = formatHealthFactor(hfValue);
  const hfColor  = healthFactorColor(hfValue);

  // Gauge fill: cap at 3× for display (3.0 = "very safe")
  const hfNumber = hfValue ? parseFloat(formatUnits(hfValue, 18)) : 0;
  const hfGaugePct = Math.min((hfNumber / 3) * 100, 100);

  // Human-readable market stats
  const apyPercent  = interestRate  ? parseFloat(formatUnits(interestRate,  16)).toFixed(2) : '—';
  const utilPercent = utilizationRaw ? parseFloat(formatUnits(utilizationRaw, 16)).toFixed(1) : '—';

  // Current LTV for this asset
  const currentLTV = deposited > 0n && currentDebt > 0n
    ? `${(Number(currentDebt) / Number(deposited) * 100).toFixed(1)}%`
    : '0%';

  // ─── Write contract ───────────────────────────────────────────────────────

  const { writeContractAsync } = useWriteContract();
  const { isLoading: isConfirming } = useWaitForTransactionReceipt({ hash: txHash });
  const isLoading = txStatus === 'approving' || txStatus === 'pending' || isConfirming;

  /** Step 1 (if needed): approve the LendingPool to spend the user's tokens */
  const handleApprove = async () => {
    setTxStatus('approving');
    setErrorMessage('');
    try {
      const hash = await writeContractAsync({
        address:      tokenAddr,
        abi:          ERC20_ABI,
        functionName: 'approve',
        args:         [contracts.LendingPool, maxUint256],
      });
      setTxHash(hash);
      refreshBalances();
    } catch (err: unknown) {
      setTxStatus('error');
      setErrorMessage(err instanceof Error ? err.message : 'Approval rejected');
    }
  };

  /** Step 2: execute the selected action on the LendingPool */
  const handleAction = async () => {
    if (!address || parsedAmount === 0n) return;
    setTxStatus('pending');
    setErrorMessage('');
    try {
      let hash: `0x${string}`;

      if (activeTab === 'deposit') {
        hash = await writeContractAsync({
          address: contracts.LendingPool, abi: LENDING_ABI,
          functionName: 'deposit', args: [tokenAddr, parsedAmount],
        });
      } else if (activeTab === 'withdraw') {
        hash = await writeContractAsync({
          address: contracts.LendingPool, abi: LENDING_ABI,
          functionName: 'withdraw', args: [tokenAddr, parsedAmount],
        });
      } else if (activeTab === 'borrow') {
        hash = await writeContractAsync({
          address: contracts.LendingPool, abi: LENDING_ABI,
          functionName: 'borrow', args: [tokenAddr, parsedAmount],
        });
      } else {
        // repay
        hash = await writeContractAsync({
          address: contracts.LendingPool, abi: LENDING_ABI,
          functionName: 'repay', args: [tokenAddr, parsedAmount],
        });
      }

      setTxHash(hash!);
      setTxStatus('success');
      setAmount(''); // clear input after success
      refreshBalances();
    } catch (err: unknown) {
      setTxStatus('error');
      setErrorMessage(err instanceof Error ? err.message : 'Transaction failed');
    }
  };

  // ─── Render ───────────────────────────────────────────────────────────────

  return (
    <div className="slide-up">

      {/* ── Page header ─────────────────────────────────── */}
      <div className="page-header">
        <h1 className="page-title">Lend &amp; Borrow</h1>
        <p className="page-subtitle">
          Deposit collateral, borrow up to 75% LTV, and monitor your health factor in real time.
        </p>
      </div>

      <div className="two-col">

        {/* ── LEFT: Action panel ──────────────────────────── */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>

          {/* Asset selector */}
          <div className="card">
            <div className="card-title" style={{ marginBottom: '0.75rem' }}>Select Asset</div>
            <div style={{ display: 'flex', gap: '0.5rem' }}>
              {TOKENS.map(token => (
                <button
                  key={token.symbol}
                  id={`asset-btn-${token.symbol}`}
                  className={`tab${selectedToken.symbol === token.symbol ? ' active' : ''}`}
                  onClick={() => { setSelectedToken(token); setAmount(''); setTxStatus('idle'); }}
                  style={{ flex: 1 }}
                >
                  {token.icon} {token.symbol}
                </button>
              ))}
            </div>
          </div>

          {/* Action tabs + input */}
          <div className="card">
            {/* Tab switcher */}
            <div className="tabs">
              {(Object.keys(TAB_LABELS) as Tab[]).map(tab => (
                <button
                  key={tab}
                  id={`tab-${tab}`}
                  className={`tab${activeTab === tab ? ' active' : ''}`}
                  onClick={() => { setActiveTab(tab); setAmount(''); setTxStatus('idle'); }}
                >
                  {TAB_LABELS[tab]}
                </button>
              ))}
            </div>

            {/* Amount input */}
            <TokenInput
              label={`Amount to ${TAB_LABELS[activeTab]}`}
              value={amount}
              onChange={v => { setAmount(v); setTxStatus('idle'); }}
              tokenAddress={tokenAddr}
              tokenSymbol={selectedToken.symbol}
              tokenIcon={selectedToken.icon}
              tokenDecimals={selectedToken.decimals}
            />

            {/* Helpful context under the input */}
            {activeTab === 'borrow' && deposited > 0n && (
              <p style={{ fontSize: '0.78rem', color: 'var(--text-muted)', marginTop: '0.5rem' }}>
                Max borrow ≈{' '}
                <span style={{ color: 'var(--accent-light)' }}>
                  {formatAmount(deposited * 75n / 100n, selectedToken.decimals)} {selectedToken.symbol}
                </span>{' '}
                (75% of your deposit)
              </p>
            )}

            {/* Action button */}
            <div style={{ marginTop: '1rem' }}>
              {!isConnected ? (
                <p style={{ textAlign: 'center', color: 'var(--text-muted)', padding: '1rem 0' }}>
                  Connect your wallet to continue
                </p>
              ) : requiresApproval ? (
                <button
                  id="lending-approve-btn"
                  className="btn btn-outline btn-lg"
                  onClick={handleApprove}
                  disabled={isLoading}
                >
                  {txStatus === 'approving' || isConfirming
                    ? `⏳ Approving ${selectedToken.symbol}…`
                    : `Approve ${selectedToken.symbol}`}
                </button>
              ) : (
                <button
                  id="lending-action-btn"
                  className="btn btn-primary btn-lg"
                  onClick={handleAction}
                  disabled={!amount || parsedAmount === 0n || isLoading}
                >
                  {isLoading
                    ? `⏳ ${TAB_LABELS[activeTab]}ing…`
                    : TAB_LABELS[activeTab]}
                </button>
              )}
            </div>

            {/* Transaction feedback */}
            {txStatus === 'success' && (
              <div className="tx-status success">
                ✓ {TAB_LABELS[activeTab]} successful!
                {txHash && chainId !== 31337 && (
                  <a
                    href={`https://sepolia.etherscan.io/tx/${txHash}`}
                    target="_blank"
                    rel="noreferrer"
                    style={{ marginLeft: '0.5rem', color: 'var(--green)' }}
                  >
                    View on Etherscan ↗
                  </a>
                )}
                {txHash && chainId === 31337 && (
                  <span style={{ marginLeft: '0.5rem', color: 'var(--text-muted)' }}>(Local transaction)</span>
                )}
              </div>
            )}
            {txStatus === 'error' && (
              <div className="tx-status error">
                ✗ {errorMessage || 'Transaction failed. Please try again.'}
              </div>
            )}
          </div>
        </div>

        {/* ── RIGHT: Position overview & market stats ─── */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem' }}>

          {/* Health factor gauge */}
          <div className="card">
            <div className="card-title">Health Factor</div>
            <div style={{
              fontSize: '2.8rem',
              fontWeight: 800,
              color: hfColor,
              marginBottom: '0.5rem',
              lineHeight: 1,
            }}>
              {hfString}
            </div>

            {/* Colour-coded bar: red < 1.0, orange < 1.5, green >= 2.0 */}
            <div className="hf-bar">
              <div
                className="hf-fill"
                style={{ width: `${hfGaugePct}%`, background: hfColor }}
              />
            </div>

            <p style={{ fontSize: '0.75rem', color: 'var(--text-muted)', marginTop: '0.5rem' }}>
              Below 1.0 = liquidatable · Above 2.0 = safe
            </p>
          </div>

          {/* Your position for the selected asset */}
          <div className="card">
            <div className="card-title" style={{ marginBottom: '1rem' }}>
              Your Position — {selectedToken.symbol}
            </div>

            <div className="info-row">
              <span>Deposited</span>
              <span>{formatAmount(deposited, selectedToken.decimals)} {selectedToken.symbol}</span>
            </div>
            <div className="info-row">
              <span>Debt (with interest)</span>
              <span style={{ color: currentDebt > 0n ? 'var(--yellow)' : 'inherit' }}>
                {formatAmount(currentDebt, selectedToken.decimals)} {selectedToken.symbol}
              </span>
            </div>
            <div className="info-row">
              <span>Current LTV</span>
              <span>{currentLTV} <span style={{ color: 'var(--text-muted)', fontWeight: 400 }}>(max 75%)</span></span>
            </div>
          </div>

          {/* Market parameters for the selected asset */}
          <div className="card">
            <div className="card-title" style={{ marginBottom: '1rem' }}>
              Market Params — {selectedToken.symbol}
            </div>

            <div className="info-row">
              <span>Borrow APY</span>
              <span style={{ color: 'var(--yellow)' }}>{apyPercent}%</span>
            </div>
            <div className="info-row">
              <span>Utilization Rate</span>
              <span>{utilPercent}%</span>
            </div>
            <div className="info-row">
              <span>Max LTV</span>
              <span>75%</span>
            </div>
            <div className="info-row">
              <span>Liquidation Threshold</span>
              <span>80%</span>
            </div>
            <div className="info-row">
              <span>Liquidation Bonus</span>
              <span style={{ color: 'var(--green)' }}>+5% for liquidators</span>
            </div>

            {/* Utilization bar */}
            {utilizationRaw !== undefined && (
              <div style={{ marginTop: '0.75rem' }}>
                <div className="progress-bar">
                  <div className="progress-fill" style={{ width: `${utilPercent}%` }} />
                </div>
                <p style={{ fontSize: '0.72rem', color: 'var(--text-muted)', marginTop: '0.3rem' }}>
                  Pool utilization — higher = higher borrow rate
                </p>
              </div>
            )}
          </div>

          {/* How it works explainer */}
          <div className="card" style={{ fontSize: '0.82rem', color: 'var(--text-secondary)', lineHeight: 1.7 }}>
            <div className="card-title" style={{ marginBottom: '0.5rem' }}>How it works</div>
            <p>
              <strong style={{ color: 'var(--text-primary)' }}>Deposit</strong> any supported token as collateral.
              Then <strong style={{ color: 'var(--text-primary)' }}>Borrow</strong> up to 75% of its USD value.
              Interest accrues per-second and is added to your debt.
              Keep your health factor above 1.0 or risk liquidation.
            </p>
          </div>
        </div>

      </div>
    </div>
  );
}
