import { formatUnits, parseUnits } from 'viem';

export function formatAmount(value: bigint, decimals = 18, displayDecimals = 4): string {
  const formatted = formatUnits(value, decimals);
  const num = parseFloat(formatted);
  if (num === 0) return '0';
  if (num < 0.0001) return '<0.0001';
  return num.toFixed(displayDecimals);
}

export function parseAmount(value: string, decimals = 18): bigint {
  if (!value || value === '') return 0n;
  try {
    return parseUnits(value, decimals);
  } catch {
    return 0n;
  }
}

export function formatHealthFactor(hf: bigint): string {
  if (hf === BigInt('0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff')) {
    return '∞';
  }
  return formatAmount(hf, 18, 2);
}

export function healthFactorColor(hf: bigint): string {
  const val = parseFloat(formatUnits(hf, 18));
  if (val === Infinity || val > 2) return '#00d4aa';
  if (val >= 1.5) return '#f0c14b';
  if (val >= 1.1) return '#ff8c00';
  return '#ff4444';
}

export function calcPriceImpact(amountIn: bigint, reserveIn: bigint, reserveOut: bigint): number {
  if (reserveIn === 0n || reserveOut === 0n || amountIn === 0n) return 0;
  const spotPrice = Number(reserveOut) / Number(reserveIn);
  const amountOut = (Number(amountIn) * 997 * Number(reserveOut)) /
    (Number(reserveIn) * 1000 + Number(amountIn) * 997);
  const execPrice = amountOut / Number(amountIn);
  return Math.abs((spotPrice - execPrice) / spotPrice * 100);
}

export function formatUSD(value: number): string {
  return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 2 }).format(value);
}

export function shortenAddress(address: string): string {
  return `${address.slice(0, 6)}…${address.slice(-4)}`;
}

export const DEADLINE_BUFFER = 300; // 5 minutes in seconds
export function getDeadline(): bigint {
  return BigInt(Math.floor(Date.now() / 1000) + DEADLINE_BUFFER);
}

export const TOKENS = [
  { symbol: 'OMNI', name: 'Omnitrix Token', decimals: 18, icon: 'O' },
  { symbol: 'WETH', name: 'Wrapped ETH', decimals: 18, icon: '⟠' },
  { symbol: 'USDC', name: 'USD Coin',    decimals: 6,  icon: '$' },
] as const;
