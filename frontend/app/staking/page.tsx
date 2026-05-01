'use client';

import { useState } from 'react';
import { useAccount, useChainId, useWriteContract, useWaitForTransactionReceipt, useReadContract } from 'wagmi';
import { useQueryClient } from '@tanstack/react-query';
import { parseUnits, formatUnits, maxUint256 } from 'viem';
import { TokenInput } from '@/components/TokenInput';
import { getContracts, STAKING_ABI, ERC20_ABI } from '@/lib/contracts';
import { formatAmount } from '@/lib/utils';

export default function StakingPage() {
  const { address, isConnected } = useAccount();
  const chainId   = useChainId();
  const contracts = getContracts(chainId);

  const [stakeAmount, setStakeAmount] = useState('');
  const [txStatus, setTxStatus] = useState<'idle'|'pending'|'success'|'error'>('idle');
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>();
  const { isLoading: isConfirming } = useWaitForTransactionReceipt({ hash: txHash });
  const queryClient = useQueryClient();

  // Invalidate all contract reads after a tx confirms so balances update immediately
  const refreshBalances = () => queryClient.invalidateQueries();

  const parsed = stakeAmount ? parseUnits(stakeAmount, 18) : 0n;

  const { data: staked }       = useReadContract({ address: contracts.Staking, abi: STAKING_ABI, functionName: 'balanceOf',          args: address ? [address] : undefined, query: { enabled: !!address, refetchInterval: 8000 } });
  const { data: earned }       = useReadContract({ address: contracts.Staking, abi: STAKING_ABI, functionName: 'earned',             args: address ? [address] : undefined, query: { enabled: !!address, refetchInterval: 8000 } });
  const { data: totalStaked }  = useReadContract({ address: contracts.Staking, abi: STAKING_ABI, functionName: 'totalSupply',        query: { refetchInterval: 15000 } });
  const { data: rewardRate }   = useReadContract({ address: contracts.Staking, abi: STAKING_ABI, functionName: 'rewardRate',         query: { refetchInterval: 30000 } });
  const { data: periodFinish } = useReadContract({ address: contracts.Staking, abi: STAKING_ABI, functionName: 'periodFinish',       query: { refetchInterval: 30000 } });
  // (getRewardForDuration kept here in case we add a rewards-remaining display later)

  const { data: allowance } = useReadContract({
    address: contracts.DefiWethPair as `0x${string}`,
    abi: ERC20_ABI,
    functionName: 'allowance',
    args: address ? [address, contracts.Staking] : undefined,
    query: { enabled: !!address },
  });

  const needsApproval = parsed > 0n && (allowance ?? 0n) < parsed;
  const { writeContractAsync } = useWriteContract();

  const annualRewards = rewardRate ? Number(rewardRate) * 365 * 24 * 3600 : 0;
  const tvl = totalStaked ? Number(formatUnits(totalStaked, 18)) : 0;
  const apy = tvl > 0 ? ((annualRewards / 1e18) / tvl * 100).toFixed(1) : '—';

  const secondsLeft = periodFinish ? Number(periodFinish) - Math.floor(Date.now() / 1000) : 0;
  const daysLeft    = Math.max(0, Math.floor(secondsLeft / 86400));
  const hoursLeft   = Math.max(0, Math.floor((secondsLeft % 86400) / 3600));

  const handleApprove = async () => {
    setTxStatus('pending');
    try {
      const hash = await writeContractAsync({
        address: contracts.DefiWethPair as `0x${string}`,
        abi: ERC20_ABI, functionName: 'approve',
        args: [contracts.Staking, maxUint256],
      });
      setTxHash(hash);
      refreshBalances();
    } catch { setTxStatus('error'); }
  };

  const handleStake = async () => {
    if (!address || parsed === 0n) return;
    setTxStatus('pending');
    try {
      const hash = await writeContractAsync({ address: contracts.Staking, abi: STAKING_ABI, functionName: 'stake', args: [parsed] });
      setTxHash(hash); setTxStatus('success'); setStakeAmount('');
      refreshBalances();
    } catch { setTxStatus('error'); }
  };

  const handleClaim = async () => {
    setTxStatus('pending');
    try {
      const hash = await writeContractAsync({ address: contracts.Staking, abi: STAKING_ABI, functionName: 'getReward' });
      setTxHash(hash); setTxStatus('success');
      refreshBalances();
    } catch { setTxStatus('error'); }
  };

  const handleExit = async () => {
    setTxStatus('pending');
    try {
      const hash = await writeContractAsync({ address: contracts.Staking, abi: STAKING_ABI, functionName: 'exit' });
      setTxHash(hash); setTxStatus('success');
      refreshBalances();
    } catch { setTxStatus('error'); }
  };

  return (
    <div className="slide-up">
      <div className="page-header">
        <h1 className="page-title">Yield Farming</h1>
        <p className="page-subtitle">Earn OMNI rewards by staking your OMNI/WETH LP tokens</p>
      </div>

      {/* Stats */}
      <div className="staking-stats">
        <div className="card" style={{ textAlign: 'center' }}>
          <div className="card-title">APY</div>
          <div className="card-value" style={{ color: 'var(--green)', fontSize: '1.8rem' }}>{apy}%</div>
          <div className="card-sub">Annual yield</div>
        </div>
        <div className="card" style={{ textAlign: 'center' }}>
          <div className="card-title">Total Staked</div>
          <div className="card-value" style={{ fontSize: '1.8rem' }}>{tvl.toFixed(2)}</div>
          <div className="card-sub">LP tokens</div>
        </div>
        <div className="card" style={{ textAlign: 'center' }}>
          <div className="card-title">Rewards End</div>
          <div className="card-value" style={{ fontSize: '1.8rem' }}>{daysLeft}d {hoursLeft}h</div>
          <div className="card-sub">Remaining</div>
        </div>
      </div>

      <div className="two-col">
        {/* Stake */}
        <div className="card">
          <h2 style={{ fontSize: '1.1rem', fontWeight: 700, marginBottom: '1.25rem' }}>⚡ Stake LP Tokens</h2>
          <TokenInput
            label="Amount to Stake"
            value={stakeAmount}
            onChange={setStakeAmount}
            tokenAddress={contracts.DefiWethPair as `0x${string}`}
            tokenSymbol="OMNI-LP"
            tokenIcon="L"
          />
          <div style={{ marginTop: '1rem', display: 'flex', flexDirection: 'column', gap: '0.75rem' }}>
            {!isConnected ? (
              <div style={{ textAlign: 'center', color: 'var(--text-muted)' }}>Connect wallet to stake</div>
            ) : needsApproval ? (
              <button id="stake-approve-btn" className="btn btn-outline btn-lg" onClick={handleApprove} disabled={txStatus === 'pending' || isConfirming}>
                {txStatus === 'pending' ? '⏳ Approving...' : 'Approve LP Token'}
              </button>
            ) : (
              <button id="stake-btn" className="btn btn-primary btn-lg" onClick={handleStake} disabled={!stakeAmount || parsed === 0n || txStatus === 'pending' || isConfirming}>
                {txStatus === 'pending' ? '⏳ Staking...' : 'Stake LP Tokens'}
              </button>
            )}
          </div>
          {txStatus === 'success' && <div className="tx-status success">✓ Transaction successful!</div>}
          {txStatus === 'error'   && <div className="tx-status error">✗ Transaction failed.</div>}
        </div>

        {/* Your Rewards */}
        <div className="card">
          <h2 style={{ fontSize: '1.1rem', fontWeight: 700, marginBottom: '1.25rem' }}>⚡ Your Rewards</h2>

          <div className="info-row">
            <span>Your Stake</span>
            <span>{formatAmount(staked ?? 0n)} LP</span>
          </div>
          <div className="reward-value">
            <div className="reward-icon">⚡</div>
            <span style={{ color: 'var(--green)', fontWeight: 700 }}>{formatAmount(earned ?? 0n)} OMNI</span>
          </div>
          <div className="info-row">
            <span>Your Share</span>
            <span>
              {staked && totalStaked && totalStaked > 0n
                ? `${(Number(staked) / Number(totalStaked) * 100).toFixed(3)}%`
                : '0%'}
            </span>
          </div>
          <div className="stat-row">
            <span>Emission Rate</span>
            <span>{rewardRate ? `${formatAmount(rewardRate * 86400n, 18, 2)} OMNI/day` : '—'}</span>
          </div>

          <div style={{ marginTop: '1.25rem', display: 'flex', flexDirection: 'column', gap: '0.75rem' }}>
            <button
              id="claim-btn"
              className="btn btn-outline btn-lg"
              onClick={handleClaim}
              disabled={!earned || earned === 0n || txStatus !== 'idle'}
            >
              {txStatus === 'pending' ? 'Claiming...' : `Claim ${formatAmount(earned ?? 0n, 18, 2)} OMNI`}
            </button>
            <button
              id="exit-btn"
              className="btn btn-danger btn-sm"
              style={{ width: '100%' }}
              onClick={handleExit}
              disabled={!isConnected || !staked || staked === 0n || txStatus === 'pending' || isConfirming}
            >
              Unstake All + Claim
            </button>
          </div>
        </div>
      </div>

      {/* How it works */}
      <div className="card" style={{ marginTop: '1.5rem' }}>
        <h2 style={{ fontSize: '1rem', fontWeight: 700, marginBottom: '1rem', color: 'var(--text-secondary)' }}>How Staking Works</h2>
        <div className="info-grid">
          <div><strong style={{ color: 'var(--text-primary)' }}>1. Add Liquidity →</strong><br/>Provide OMNI+WETH on the Swap page to get LP tokens</div>
          <div><strong style={{ color: 'var(--text-primary)' }}>2. Stake LP →</strong><br/>Deposit your LP tokens here to start earning OMNI rewards</div>
          <div><strong style={{ color: 'var(--text-primary)' }}>3. Claim Anytime →</strong><br/>Rewards accumulate per-second, claim whenever you want</div>
        </div>
      </div>
    </div>
  );
}
