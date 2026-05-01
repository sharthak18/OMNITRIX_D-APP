// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/tokens/DefiToken.sol";
import "../src/swap/DefiFactory.sol";
import "../src/swap/DefiRouter.sol";
import "../src/swap/DefiPair.sol";
import "../src/lending/LendingPool.sol";
import "../src/lending/PriceOracle.sol";
import "../src/staking/StakingRewards.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockAggregatorV3.sol";

/// @notice Full deployment script for the DeFi protocol.
///         On local/testnet it deploys mock tokens + Chainlink aggregators.
///         On mainnet, set MOCK=false and provide real Chainlink feed addresses.
contract Deploy is Script {
    // ─── Deployed addresses (populated during run) ───
    DefiToken      public defiToken;
    MockERC20      public weth;
    MockERC20      public usdc;
    DefiFactory    public factory;
    DefiRouter     public router;
    address        public defiWethPair;
    PriceOracle    public oracle;
    LendingPool    public lendingPool;
    StakingRewards public staking;

    function run() external {
        // PRIVATE_KEY can be set as env var or passed via --private-key CLI flag.
        // vm.envOr falls back to the Anvil default key #0 for local convenience.
        uint256 deployerPk;
        try vm.envUint("PRIVATE_KEY") returns (uint256 pk) {
            deployerPk = pk;
        } catch {
            deployerPk = 0;
        }

        address deployer;
        if (deployerPk != 0) {
            deployer = vm.addr(deployerPk);
            vm.startBroadcast(deployerPk);
        } else if (block.chainid == 31337) {
            // Fallback to default Anvil key for local testing
            deployerPk = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
            deployer = vm.addr(deployerPk);
            vm.startBroadcast(deployerPk);
        } else {
            // Secure mode: assume we are using Foundry encrypted keystore (--account)
            deployer = msg.sender;
            vm.startBroadcast();
        }

        bool isMock = vm.envOr("MOCK", true); // default: deploy mocks

        console.log("=== Deploying DeFi Protocol ===");
        console.log("Deployer:", deployer);
        console.log("Network:", block.chainid);

        // ─────────────── 1. Token ───────────────
        defiToken = new DefiToken(deployer);
        console.log("DefiToken:", address(defiToken));

        // ─────────────── 2. Mock Tokens (local/testnet) ───────────────
        if (isMock) {
            weth = new MockERC20("Wrapped ETH", "WETH", 18);
            usdc = new MockERC20("USD Coin",    "USDC", 6);
            // Mint test liquidity to deployer
            weth.mint(deployer, 1_000 ether);
            usdc.mint(deployer, 2_000_000e6);
            console.log("MockWETH:", address(weth));
            console.log("MockUSDC:", address(usdc));
        }

        // ─────────────── 3. AMM ───────────────
        factory = new DefiFactory(deployer);
        router  = new DefiRouter(address(factory));
        console.log("DefiFactory:", address(factory));
        console.log("DefiRouter:", address(router));

        // Create DEFI/WETH pair and seed liquidity (100k DEFI : 50 WETH)
        if (isMock) {
            defiToken.approve(address(router), 100_000 ether);
            weth.approve(address(router), 50 ether);
            (,, uint256 lp) = router.addLiquidity(
                address(defiToken),
                address(weth),
                100_000 ether,
                50 ether,
                0, 0,
                deployer,
                block.timestamp + 300
            );
            defiWethPair = factory.getPair(address(defiToken), address(weth));
            console.log("DEFI/WETH Pair:", defiWethPair);
            console.log("Initial LP minted:", lp);

            // Also create DEFI/USDC pair
            defiToken.approve(address(router), 100_000 ether);
            usdc.approve(address(router), 200_000e6);
            router.addLiquidity(
                address(defiToken),
                address(usdc),
                100_000 ether,
                200_000e6,
                0, 0,
                deployer,
                block.timestamp + 300
            );
            console.log("DEFI/USDC Pair:", factory.getPair(address(defiToken), address(usdc)));
        }

        // ─────────────── 4. Price Oracle ───────────────
        oracle = new PriceOracle(deployer);

        if (block.chainid == 11155111) {
            // Register real Sepolia Chainlink feeds
            oracle.registerFeed(address(weth), 0x694AA1769357215DE4FAC081bf1f309aDC325306); // WETH/USD
            oracle.registerFeed(address(usdc), 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E); // USDC/USD

            // For DEFI token, we'll still use a mock feed since it's a test token
            MockAggregatorV3 defiFeed = new MockAggregatorV3(8, 2e8); // $2
            oracle.registerFeed(address(defiToken), address(defiFeed));

            console.log("Registered Sepolia Chainlink feeds for WETH and USDC");
        } else if (isMock) {
            // Deploy mock Chainlink aggregators
            MockAggregatorV3 wethFeed = new MockAggregatorV3(8, 2000e8); // $2000
            MockAggregatorV3 usdcFeed = new MockAggregatorV3(8, 1e8);    // $1
            MockAggregatorV3 defiFeed = new MockAggregatorV3(8, 2e8);    // $2

            oracle.registerFeed(address(weth),      address(wethFeed));
            oracle.registerFeed(address(usdc),      address(usdcFeed));
            oracle.registerFeed(address(defiToken), address(defiFeed));

            console.log("WETHFeed:", address(wethFeed));
            console.log("USDCFeed:", address(usdcFeed));
            console.log("DEFIFeed:", address(defiFeed));
        }
        console.log("PriceOracle:", address(oracle));

        // ─────────────── 5. Lending Pool ───────────────
        lendingPool = new LendingPool(address(oracle), deployer);
        if (isMock) {
            lendingPool.registerAsset(address(weth));
            lendingPool.registerAsset(address(usdc));
            lendingPool.registerAsset(address(defiToken));

            // Seed lending pool with some USDC liquidity
            usdc.approve(address(lendingPool), 500_000e6);
            usdc.mint(deployer, 500_000e6);
            lendingPool.deposit(address(usdc), 500_000e6);
        }
        console.log("LendingPool:", address(lendingPool));

        // ─────────────── 6. Staking Rewards ───────────────
        address stakingToken = defiWethPair != address(0) ? defiWethPair : address(defiToken);
        staking = new StakingRewards(address(defiToken), stakingToken, deployer);

        // Fund 40M DEFI as staking rewards over 7 days
        uint256 rewardAmount = 40_000_000 ether;
        defiToken.approve(address(staking), rewardAmount);
        staking.notifyRewardAmount(rewardAmount);
        console.log("StakingRewards:", address(staking));

        vm.stopBroadcast();

        // ─────────────── Output addresses JSON ───────────────
        _writeDeployments(deployer);
    }

    function _writeDeployments(address deployer) internal {
        string memory json = string.concat(
            '{\n',
            '  "chainId": ', vm.toString(block.chainid), ',\n',
            '  "deployer": "', vm.toString(deployer), '",\n',
            '  "DefiToken":    "', vm.toString(address(defiToken)),   '",\n',
            '  "WETH":         "', vm.toString(address(weth)),        '",\n',
            '  "USDC":         "', vm.toString(address(usdc)),        '",\n',
            '  "DefiFactory":  "', vm.toString(address(factory)),     '",\n',
            '  "DefiRouter":   "', vm.toString(address(router)),      '",\n',
            '  "DefiWethPair": "', vm.toString(defiWethPair),         '",\n',
            '  "PriceOracle":  "', vm.toString(address(oracle)),      '",\n',
            '  "LendingPool":  "', vm.toString(address(lendingPool)), '",\n',
            '  "Staking":      "', vm.toString(address(staking)),     '"\n',
            '}'
        );

        // Write to frontend/lib/deployments.json (path relative to contracts/ dir)
        vm.writeFile("../frontend/lib/deployments.json", json);
        console.log("\n=== Deployment complete! Addresses written to frontend/lib/deployments.json ===");
    }
}
