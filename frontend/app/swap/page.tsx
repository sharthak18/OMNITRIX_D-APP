'use client';

import { useState } from 'react';
import { useAccount, useChainId, useWriteContract, useWaitForTransactionReceipt, useReadContract } from 'wagmi';
import { useQueryClient } from '@tanstack/react-query';
import { parseUnits, formatUnits, maxUint256 } from 'viem';
import { TokenInput } from '@/components/TokenInput';
import { getContracts, ROUTER_ABI, ERC20_ABI } from '@/lib/contracts';
import { getDeadline, TOKENS } from '@/lib/utils';

const SLIPPAGE_PRESETS = ['0.1', '0.5', '1.0'];

export default function SwapPage() {
  const { address, isConnected } = useAccount();
  const chainId = useChainId();
  const contracts = getContracts(chainId);

  const [tokenIn,  setTokenIn]  = useState<typeof TOKENS[number]>(TOKENS[1]);  // WETH
  const [tokenOut, setTokenOut] = useState<typeof TOKENS[number]>(TOKENS[0]);  // DEFI
  const [amountIn,  setAmountIn]  = useState('');
  const [slippage,  setSlippage]  = useState('0.5');
  const [customSlip, setCustomSlip] = useState('');
  const [txStatus, setTxStatus] = useState<'idle'|'approving'|'swapping'|'success'|'error'>('idle');
  const queryClient = useQueryClient();

  // Refresh balances after successful transaction
  const refreshBalances = () => queryClient.invalidateQueries();

  const tokenInAddr  = tokenIn.symbol  === 'WETH' ? contracts.WETH  : tokenIn.symbol  === 'USDC' ? contracts.USDC  : contracts.DefiToken;
  const tokenOutAddr = tokenOut.symbol === 'WETH' ? contracts.WETH  : tokenOut.symbol === 'USDC' ? contracts.USDC : contracts.DefiToken;

  const parsedIn = amountIn ? parseUnits(amountIn, tokenIn.decimals) : 0n;
  const effectiveSlippage = customSlip || slippage;

  // Read quote from router — live price from on-chain reserves
  const { data: amountsOut, isLoading: isQuoting, isError: isQuoteError } = useReadContract({
    address: contracts.DefiRouter as `0x${string}`,
    abi: ROUTER_ABI,
    functionName: 'getAmountsOut',
    args: parsedIn > 0n ? [parsedIn, [tokenInAddr, tokenOutAddr]] : undefined,
    query: {
      enabled: parsedIn > 0n && tokenInAddr !== tokenOutAddr,
      refetchInterval: 5000,
    },
  });

  const amountOut = amountsOut?.[1] ?? 0n;
  const amountOutFormatted = amountOut > 0n ? Number(formatUnits(amountOut, tokenOut.decimals)).toFixed(6) : '';

  // Read allowance
  const { data: allowance } = useReadContract({
    address: tokenInAddr,
    abi: ERC20_ABI,
    functionName: 'allowance',
    args: address ? [address, contracts.DefiRouter] : undefined,
    query: { enabled: !!address },
  });

  const needsApproval = parsedIn > 0n && (allowance ?? 0n) < parsedIn;

  const { writeContractAsync } = useWriteContract();
  const [txHash, setTxHash] = useState<`0x${string}` | undefined>();
  const { isLoading: isConfirming } = useWaitForTransactionReceipt({ hash: txHash });

  const handleApprove = async () => {
    setTxStatus('approving');
    try {
      const hash = await writeContractAsync({
        address: tokenInAddr,
        abi: ERC20_ABI,
        functionName: 'approve',
        args: [contracts.DefiRouter, maxUint256],
      });
      setTxHash(hash);
      refreshBalances();
    } catch { setTxStatus('error'); }
  };

  const handleSwap = async () => {
    if (!address || parsedIn === 0n) return;
    setTxStatus('swapping');
    try {
      const slip = parseFloat(effectiveSlippage) / 100;
      const minOut = BigInt(Math.floor(Number(amountOut) * (1 - slip)));
      const hash = await writeContractAsync({
        address: contracts.DefiRouter,
        abi: ROUTER_ABI,
        functionName: 'swapExactTokensForTokens',
        args: [parsedIn, minOut, [tokenInAddr, tokenOutAddr], address, getDeadline()],
      });
      setTxHash(hash);
      setTxStatus('success');
      setAmountIn('');
      refreshBalances();
    } catch { setTxStatus('error'); }
  };

  const flipTokens = () => {
    setTokenIn(tokenOut);
    setTokenOut(tokenIn);
    setAmountIn('');
  };

  const activeSlip = customSlip ? 'custom' : slippage;

  return (
    <div className="slide-up" style={{ maxWidth: 480, margin: '0 auto' }}>
      <div className="page-header" style={{ textAlign: 'center' }}>
        <h1 className="page-title">Swap</h1>
        <p className="page-subtitle">Trade tokens at the best on-chain price</p>
      </div>

      <div className="card">
        {/* Slippage */}
        <div style={{ marginBottom: '1.25rem' }}>
          <div className="card-title" style={{ marginBottom: '0.5rem' }}>Slippage Tolerance</div>
          <div className="slippage-row">
            {SLIPPAGE_PRESETS.map(s => (
              <button
                key={s}
                id={`slippage-${s}`}
                className={`slippage-btn${activeSlip === s ? ' active' : ''}`}
                onClick={() => { setSlippage(s); setCustomSlip(''); }}
              >
                {s}%
              </button>
            ))}
            <input
              id="slippage-custom"
              className="slippage-input"
              type="number"
              placeholder="Custom %"
              value={customSlip}
              onChange={e => setCustomSlip(e.target.value)}
              min="0.01" max="50" step="0.1"
            />
          </div>
        </div>

        {/* Token In */}
        <TokenInput
          label="You Pay"
          value={amountIn}
          onChange={setAmountIn}
          tokenAddress={tokenInAddr}
          tokenSymbol={tokenIn.symbol}
          tokenIcon={tokenIn.icon}
          tokenDecimals={tokenIn.decimals}
          onMax={() => {/* handled in TokenInput */}}
        />

        {/* Flip Arrow */}
        <div style={{ display: 'flex', justifyContent: 'center', margin: '0.75rem 0' }}>
          <button id="swap-flip-btn" className="swap-arrow-btn" onClick={flipTokens} title="Flip tokens">
            ⇅
          </button>
        </div>

        {/* Token Out — You Receive */}
        <TokenInput
          label="You Receive"
          value={isQuoting && parsedIn > 0n ? 'Loading quote...' : amountOutFormatted}
          tokenAddress={tokenOutAddr}
          tokenSymbol={tokenOut.symbol}
          tokenIcon={tokenOut.icon}
          tokenDecimals={tokenOut.decimals}
          readOnly
        />
        {isQuoteError && parsedIn > 0n && (
          <div style={{ fontSize: '0.8rem', color: 'var(--red)', marginTop: '0.5rem', padding: '0 0.25rem' }}>
            ⚠ Could not fetch quote. Make sure the pair has liquidity and the token pair exists.
          </div>
        )}

        {/* Price Info */}
        {amountOut > 0n && (
          <div style={{ marginTop: '1rem' }}>
            <div className="info-row">
              <span>Rate</span>
              <span>1 {tokenIn.symbol} = {(Number(amountOut) / Number(parsedIn) * 10 ** (tokenIn.decimals - tokenOut.decimals)).toFixed(6)} {tokenOut.symbol}</span>
            </div>
            <div className="info-row">
              <span>Slippage</span>
              <span>{effectiveSlippage}%</span>
            </div>
            <div className="info-row">
              <span>Min. Received</span>
              <span>{formatUnits(BigInt(Math.floor(Number(amountOut) * (1 - parseFloat(effectiveSlippage) / 100))), tokenOut.decimals).slice(0, 10)} {tokenOut.symbol}</span>
            </div>
            <div className="info-row">
              <span>Fee (0.3%)</span>
              <span>{(parseFloat(amountIn) * 0.003).toFixed(6)} {tokenIn.symbol}</span>
            </div>
          </div>
        )}

        {/* Action Button */}
        <div style={{ marginTop: '1.25rem' }}>
          {!isConnected ? (
            <div style={{ textAlign: 'center', color: 'var(--text-muted)', padding: '1rem' }}>
              Connect wallet to swap
            </div>
          ) : needsApproval ? (
            <button
              id="approve-btn"
              className="btn btn-outline btn-lg"
              onClick={handleApprove}
              disabled={txStatus === 'approving' || isConfirming}
            >
              {txStatus === 'approving' || isConfirming ? '⏳ Approving...' : `Approve ${tokenIn.symbol}`}
            </button>
          ) : (
            <button
              id="swap-btn"
              className="btn btn-primary btn-lg"
              onClick={handleSwap}
              disabled={!amountIn || parsedIn === 0n || txStatus === 'swapping' || isConfirming}
            >
              {txStatus === 'swapping' || isConfirming ? '⏳ Swapping...' : 'Swap Tokens'}
            </button>
          )}
        </div>

        {/* TX Status */}
        {txStatus === 'success' && (
          <div className="tx-status success">
            ✓ Swap successful! 
            {txHash && chainId !== 31337 && <a href={`https://sepolia.etherscan.io/tx/${txHash}`} target="_blank" rel="noreferrer" style={{ color: 'var(--green)', marginLeft: '0.5rem' }}>View on Etherscan ↗</a>}
            {txHash && chainId === 31337 && <span style={{ marginLeft: '0.5rem', color: 'var(--text-muted)' }}>(Local transaction)</span>}
          </div>
        )}
        {txStatus === 'error' && (
          <div className="tx-status error">✗ Transaction failed. Please try again.</div>
        )}
      </div>
    </div>
  );
}
