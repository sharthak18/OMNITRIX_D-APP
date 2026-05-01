// ─── Deployed addresses ─────────────────────────────────────────────────────
// Anvil (31337): deployed 2026-04-30 via forge script script/Deploy.s.sol
// Sepolia (11155111): fill in after Sepolia deployment
const deployments: Record<number, Record<string, `0x${string}`>> = {
  31337: { // Anvil local — forge script script/Deploy.s.sol --fork-url http://localhost:8545
    DefiToken:    '0x5FbDB2315678afecb367f032d93F642f64180aa3',
    WETH:         '0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512',
    USDC:         '0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0',
    DefiFactory:  '0x5FC8d32690cc91D4c39d9d3abcBD16989F875707',
    DefiRouter:   '0x0165878A594ca255338adfa4d48449f69242Eb8F',
    DefiWethPair: '0xB71c5196BdbeD3E8Ff9cACdFDA9f1f65367fCD7B',
    DefiUsdcPair: '0x4d2E15e0c9c520ca7E0be9C1f03B5Bd4c7eb0a2d',
    PriceOracle:  '0x0DCd1Bf9A1b36cE34237eEaFef220932846BCD82',
    LendingPool:  '0xc6e7DF5E7b4f2A278906862b61205850344D4e7d',
    Staking:      '0x09635F643e140090A9A8Dcd712eD6285858ceBef',
  },
  11155111: { // Sepolia — fill in after: forge script ... --rpc-url $SEPOLIA_RPC_URL --broadcast --verify
    DefiToken:    '0x6Fa0d9F4575590A68245C6c6D0975B4d0c296565',
    WETH:         '0xBc62144363b0eE52d6Db865b1F6485B392dd1746',
    USDC:         '0x4d1aD9d1E9727e0fEFDFd77f3D09AC49E7090356',
    DefiFactory:  '0x83c73f94Ea4F235F3020e29939e84652204DDfF8',
    DefiRouter:   '0xEcA12FA902C1b794FF56EfBfB2eD6AfEc5C34bf1',
    DefiWethPair: '0xcBBA696E1170218FAbef9E25f84973F21a7f3B3c',
    DefiUsdcPair: '0xdE7F2079cd7115e287544cC032817F8ba8FaDcaE',
    PriceOracle:  '0xa7d3Ddf3Cebb25c4eed3FA28d084c1E3B29Ca553',
    LendingPool:  '0x9926E4802D0cD8cfe4E625f4a52B78d80723DfAf',
    Staking:      '0x09E18d2D4220e037bca509835b8332efaC68C8A4',
  },
};


export function getContracts(chainId: number) {
  return deployments[chainId] ?? deployments[31337];
}

// Minimal ABIs — only the functions the frontend needs
export const ROUTER_ABI = [
  { name: 'addLiquidity', type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'tokenA', type: 'address' }, { name: 'tokenB', type: 'address' }, { name: 'amountADesired', type: 'uint256' }, { name: 'amountBDesired', type: 'uint256' }, { name: 'amountAMin', type: 'uint256' }, { name: 'amountBMin', type: 'uint256' }, { name: 'to', type: 'address' }, { name: 'deadline', type: 'uint256' }], outputs: [{ name: 'amountA', type: 'uint256' }, { name: 'amountB', type: 'uint256' }, { name: 'liquidity', type: 'uint256' }] },
  { name: 'removeLiquidity', type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'tokenA', type: 'address' }, { name: 'tokenB', type: 'address' }, { name: 'liquidity', type: 'uint256' }, { name: 'amountAMin', type: 'uint256' }, { name: 'amountBMin', type: 'uint256' }, { name: 'to', type: 'address' }, { name: 'deadline', type: 'uint256' }], outputs: [{ name: 'amountA', type: 'uint256' }, { name: 'amountB', type: 'uint256' }] },
  { name: 'swapExactTokensForTokens', type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'amountIn', type: 'uint256' }, { name: 'amountOutMin', type: 'uint256' }, { name: 'path', type: 'address[]' }, { name: 'to', type: 'address' }, { name: 'deadline', type: 'uint256' }], outputs: [{ name: 'amounts', type: 'uint256[]' }] },
  { name: 'getAmountsOut', type: 'function', stateMutability: 'view', inputs: [{ name: 'amountIn', type: 'uint256' }, { name: 'path', type: 'address[]' }], outputs: [{ name: 'amounts', type: 'uint256[]' }] },
] as const;

export const LENDING_ABI = [
  { name: 'deposit',   type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'asset', type: 'address' }, { name: 'amount', type: 'uint256' }], outputs: [] },
  { name: 'withdraw',  type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'asset', type: 'address' }, { name: 'amount', type: 'uint256' }], outputs: [] },
  { name: 'borrow',    type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'asset', type: 'address' }, { name: 'amount', type: 'uint256' }], outputs: [] },
  { name: 'repay',     type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'asset', type: 'address' }, { name: 'amount', type: 'uint256' }], outputs: [] },
  { name: 'healthFactor',      type: 'function', stateMutability: 'view', inputs: [{ name: 'user', type: 'address' }], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getUserDebt',       type: 'function', stateMutability: 'view', inputs: [{ name: 'user', type: 'address' }, { name: 'asset', type: 'address' }], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getInterestRate',   type: 'function', stateMutability: 'view', inputs: [{ name: 'asset', type: 'address' }], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getUtilizationRate',type: 'function', stateMutability: 'view', inputs: [{ name: 'asset', type: 'address' }], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'positions', type: 'function', stateMutability: 'view', inputs: [{ name: 'user', type: 'address' }, { name: 'asset', type: 'address' }], outputs: [{ name: 'deposited', type: 'uint256' }, { name: 'borrowed', type: 'uint256' }, { name: 'borrowIndex', type: 'uint256' }] },
] as const;

export const STAKING_ABI = [
  { name: 'stake',    type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'amount', type: 'uint256' }], outputs: [] },
  { name: 'withdraw', type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'amount', type: 'uint256' }], outputs: [] },
  { name: 'getReward',type: 'function', stateMutability: 'nonpayable', inputs: [], outputs: [] },
  { name: 'exit',     type: 'function', stateMutability: 'nonpayable', inputs: [], outputs: [] },
  { name: 'earned',   type: 'function', stateMutability: 'view', inputs: [{ name: 'account', type: 'address' }], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'balanceOf',type: 'function', stateMutability: 'view', inputs: [{ name: 'account', type: 'address' }], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'totalSupply', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'rewardRate',  type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'periodFinish',type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'getRewardForDuration', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
] as const;

export const ERC20_ABI = [
  { name: 'approve',  type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'spender', type: 'address' }, { name: 'value', type: 'uint256' }], outputs: [{ name: '', type: 'bool' }] },
  { name: 'allowance',type: 'function', stateMutability: 'view', inputs: [{ name: 'owner', type: 'address' }, { name: 'spender', type: 'address' }], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'balanceOf',type: 'function', stateMutability: 'view', inputs: [{ name: 'account', type: 'address' }], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'decimals', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint8' }] },
  { name: 'symbol',   type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'string' }] },
  { name: 'name',     type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'string' }] },
] as const;

export const PAIR_ABI = [
  { name: 'getReserves', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: 'reserve0', type: 'uint112' }, { name: 'reserve1', type: 'uint112' }, { name: 'blockTimestampLast', type: 'uint32' }] },
  { name: 'totalSupply', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'uint256' }] },
  { name: 'token0', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'address' }] },
  { name: 'token1', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ name: '', type: 'address' }] },
  { name: 'approve',  type: 'function', stateMutability: 'nonpayable', inputs: [{ name: 'spender', type: 'address' }, { name: 'value', type: 'uint256' }], outputs: [{ name: '', type: 'bool' }] },
  { name: 'balanceOf',type: 'function', stateMutability: 'view', inputs: [{ name: 'account', type: 'address' }], outputs: [{ name: '', type: 'uint256' }] },
] as const;
