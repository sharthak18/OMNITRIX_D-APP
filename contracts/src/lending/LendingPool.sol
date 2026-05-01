// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./IPriceOracle.sol";

/// @title LendingPool
/// @notice Aave-style over-collateralized lending pool featuring:
///
///   SECURITY
///   - ReentrancyGuard on every state-changing function
///   - Pausable emergency stop (owner only)
///   - Oracle timelock: changing the price oracle requires a 48-hour delay
///   - Supply caps + borrow caps per asset (prevents whale manipulation)
///   - Minimum health factor buffer (1.05×) enforced post-borrow
///
///   INTEREST MODEL
///   - Compound interest via second-order Taylor approximation (more accurate than simple)
///   - Linear utilization-based rate: baseRate + slope × utilization
///
///   PROTOCOL PROFIT
///   - Reserve factor: 20% of all interest accrued goes to the protocol treasury
///   - Flash loans: atomic borrow-and-repay with 0.09% fee (pure profit)
///   - treasury can withdraw accumulated reserves at any time
///
///   LENDING MECHANICS
///   - Multi-asset collateral (any ERC-20 registered by owner)
///   - 75% LTV cap, 80% liquidation threshold
///   - 50% close-factor liquidations with 5% bonus for liquidators
contract LendingPool is ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;

    /* ─────────────────────────── Constants ─────────────────────────── */

    uint256 public constant LTV_RATIO              = 75;     // 75% max borrow
    uint256 public constant LIQUIDATION_THRESHOLD  = 80;     // liquidate when collateral < 80% of debt
    uint256 public constant LIQUIDATION_BONUS      = 105;    // liquidator gets 5% bonus (105/100)
    uint256 public constant CLOSE_FACTOR           = 50;     // max 50% of debt per liquidation call

    uint256 public constant BASE_INTEREST_RATE     = 2e16;   // 2% per year at 0% utilization
    uint256 public constant SLOPE                  = 10e16;  // +10% per year at 100% utilization

    uint256 public constant PRECISION              = 1e18;
    uint256 public constant SECONDS_PER_YEAR       = 365 days;

    /// @notice 5% health factor buffer after borrow (prevents instant liquidation)
    uint256 public constant MIN_HEALTH_AFTER_BORROW = 105e16; // 1.05 × 1e18

    /// @notice 20% of interest income goes to protocol treasury
    uint256 public constant RESERVE_FACTOR         = 20;

    /// @notice Flash loan fee: 0.09% (9 / 10_000)
    uint256 public constant FLASH_LOAN_FEE_BPS     = 9;
    uint256 public constant FLASH_LOAN_FEE_DENOM   = 10_000;

    /// @notice Delay before a newly proposed oracle takes effect (security timelock)
    uint256 public constant ORACLE_TIMELOCK_DELAY  = 48 hours;

    /* ─────────────────────────── Data Structures ───────────────────── */

    struct AssetConfig {
        bool    supported;
        uint256 totalDeposited;   // total token units currently deposited
        uint256 totalBorrowed;    // total token units currently borrowed
        uint256 debtIndex;        // compound interest accumulator (starts at PRECISION = 1e18)
        uint256 lastUpdateTime;   // last block.timestamp when index was updated
        uint256 supplyCap;        // max totalDeposited allowed (0 = no cap)
        uint256 borrowCap;        // max totalBorrowed allowed (0 = no cap)
    }

    struct UserPosition {
        uint256 deposited;    // collateral deposited (token units)
        uint256 borrowed;     // principal borrowed, scaled to current index
        uint256 borrowIndex;  // snapshot of debtIndex at time of last borrow/repay
    }

    /* ─────────────────────────── State ─────────────────────────────── */

    IPriceOracle public oracle;

    /// @notice Address that receives protocol reserve withdrawals
    address public treasury;

    /// @notice Pending oracle address (must wait ORACLE_TIMELOCK_DELAY before activation)
    address public pendingOracle;
    uint256 public oracleUnlockTime;

    /// @notice Flash loans enabled/disabled toggle
    bool public flashLoanEnabled = true;

    /// @notice Accumulated protocol reserves per asset (not yet withdrawn)
    mapping(address => uint256) public reserves;

    mapping(address => AssetConfig)                         public assetConfigs;
    mapping(address => mapping(address => UserPosition))    public positions; // user → token → position

    address[] public supportedAssets;

    /* ─────────────────────────── Events ────────────────────────────── */

    event AssetRegistered(address indexed asset);
    event CapsUpdated(address indexed asset, uint256 supplyCap, uint256 borrowCap);
    event Deposited(address indexed user, address indexed asset, uint256 amount);
    event Withdrawn(address indexed user, address indexed asset, uint256 amount);
    event Borrowed(address indexed user, address indexed asset, uint256 amount);
    event Repaid(address indexed user, address indexed asset, uint256 amount);
    event Liquidated(
        address indexed liquidator,
        address indexed borrower,
        address indexed collateralAsset,
        address          debtAsset,
        uint256          debtRepaid,
        uint256          collateralSeized
    );
    event FlashLoan(address indexed receiver, address indexed asset, uint256 amount, uint256 fee);
    event ReservesAccrued(address indexed asset, uint256 amount);
    event ReservesWithdrawn(address indexed asset, uint256 amount, address to);
    event OracleUpdateProposed(address indexed proposed, uint256 unlockTime);
    event OracleUpdateExecuted(address indexed newOracle);
    event TreasuryUpdated(address indexed newTreasury);

    /* ─────────────────────────── Constructor ───────────────────────── */

    constructor(address _oracle, address initialOwner) Ownable(initialOwner) {
        oracle   = IPriceOracle(_oracle);
        treasury = initialOwner; // default treasury = deployer
    }

    /* ─────────────────────────── Admin ─────────────────────────────── */

    /// @notice Register a new asset. Sets no caps by default (0 = unlimited).
    function registerAsset(address asset) external onlyOwner {
        require(asset != address(0), "LendingPool: zero address");
        require(!assetConfigs[asset].supported, "LendingPool: already registered");
        assetConfigs[asset] = AssetConfig({
            supported:      true,
            totalDeposited: 0,
            totalBorrowed:  0,
            debtIndex:      PRECISION,
            lastUpdateTime: block.timestamp,
            supplyCap:      0,
            borrowCap:      0
        });
        supportedAssets.push(asset);
        emit AssetRegistered(asset);
    }

    /// @notice Update supply and borrow caps for an asset (0 = no cap)
    function setCaps(address asset, uint256 _supplyCap, uint256 _borrowCap) external onlyOwner {
        require(assetConfigs[asset].supported, "LendingPool: asset not supported");
        assetConfigs[asset].supplyCap = _supplyCap;
        assetConfigs[asset].borrowCap = _borrowCap;
        emit CapsUpdated(asset, _supplyCap, _borrowCap);
    }

    /// @notice Set a new treasury address for reserve withdrawals
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "LendingPool: zero address");
        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }

    /// @notice Enable or disable flash loans
    function setFlashLoanEnabled(bool enabled) external onlyOwner {
        flashLoanEnabled = enabled;
    }

    // ── Oracle timelock ──────────────────────────────────────────────

    /// @notice Step 1: propose a new oracle. Activatable after 48 hours.
    /// @dev Prevents a compromised owner key from instantly swapping to a malicious feed.
    function proposeOracle(address _oracle) external onlyOwner {
        require(_oracle != address(0), "LendingPool: zero oracle");
        pendingOracle    = _oracle;
        oracleUnlockTime = block.timestamp + ORACLE_TIMELOCK_DELAY;
        emit OracleUpdateProposed(_oracle, oracleUnlockTime);
    }

    /// @notice Step 2: execute the pending oracle update (after 48h have passed)
    function executeOracleUpdate() external onlyOwner {
        require(pendingOracle != address(0), "LendingPool: no pending oracle");
        require(block.timestamp >= oracleUnlockTime, "LendingPool: oracle timelock active");
        oracle        = IPriceOracle(pendingOracle);
        pendingOracle = address(0);
        emit OracleUpdateExecuted(address(oracle));
    }

    // ── Emergency controls ───────────────────────────────────────────

    function pause()   external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ── Reserve management ───────────────────────────────────────────

    /// @notice Withdraw protocol-owned reserves for an asset to the treasury
    function withdrawReserves(address asset, uint256 amount) external {
        require(msg.sender == treasury, "LendingPool: only treasury");
        require(amount <= reserves[asset], "LendingPool: insufficient reserves");
        require(
            IERC20(asset).balanceOf(address(this)) >= amount,
            "LendingPool: insufficient pool balance"
        );
        reserves[asset] -= amount;
        IERC20(asset).safeTransfer(treasury, amount);
        emit ReservesWithdrawn(asset, amount, treasury);
    }

    /* ─────────────────────────── Valuation Helper ───────────────────── */

    /// @dev Converts a token amount to 18-decimal USD value.
    ///      Formula: amount × price / 10^(tokenDecimals + priceDec - 18)
    ///      Works for any token decimal count (e.g. 6 for USDC, 18 for WETH).
    function _toUSD18(
        uint256 amount,
        uint8   tokenDecimals,
        uint256 price,
        uint8   priceDec
    ) internal pure returns (uint256) {
        uint256 combinedDec = uint256(tokenDecimals) + uint256(priceDec);
        if (combinedDec >= 18) {
            return amount * price / 10 ** (combinedDec - 18);
        } else {
            return amount * price * 10 ** (18 - combinedDec);
        }
    }

    /* ─────────────────────────── Interest Model ─────────────────────── */

    /// @dev Linear utilization-based APY: baseRate + slope × utilization
    ///      Returns an 18-decimal annual rate (e.g. 5e16 = 5% APY)
    function _currentInterestRate(address asset) internal view returns (uint256) {
        AssetConfig storage cfg = assetConfigs[asset];
        if (cfg.totalDeposited == 0) return BASE_INTEREST_RATE;
        uint256 utilization = cfg.totalBorrowed * PRECISION / cfg.totalDeposited;
        return BASE_INTEREST_RATE + (SLOPE * utilization / PRECISION);
    }

    /// @dev Compound interest via 2nd-order Taylor series:
    ///      new_index = old_index × (1 + r*t + (r*t)²/2)
    ///      where r = annual rate, t = elapsed / SECONDS_PER_YEAR
    ///
    ///      More accurate than simple interest over long periods and
    ///      generates marginally more revenue for the protocol.
    ///      The 2nd-order term is negligible for short intervals but
    ///      avoids systematic under-charging over months/years.
    function _accrueInterest(address asset) internal {
        AssetConfig storage cfg = assetConfigs[asset];
        uint256 elapsed = block.timestamp - cfg.lastUpdateTime;

        if (elapsed == 0 || cfg.totalBorrowed == 0) {
            cfg.lastUpdateTime = block.timestamp;
            return;
        }

        uint256 rate = _currentInterestRate(asset);
        // rt = rate × elapsed / SECONDS_PER_YEAR  (18-decimal fraction)
        uint256 rt = rate * elapsed / SECONDS_PER_YEAR;

        // Compound factor = 1 + rt + rt²/2  (expressed in PRECISION units)
        uint256 interestFactor = rt + (rt * rt / (2 * PRECISION));

        // New interest = old_index × interestFactor
        uint256 newInterest = cfg.debtIndex * interestFactor / PRECISION;

        // Reserve factor: 20% of new interest → protocol treasury
        uint256 reserveAmount = newInterest * RESERVE_FACTOR / 100;
        reserves[asset] += reserveAmount;
        if (reserveAmount > 0) emit ReservesAccrued(asset, reserveAmount);

        cfg.debtIndex      += newInterest;
        cfg.lastUpdateTime  = block.timestamp;
    }

    /// @dev Projects the current debt of a user including accrued interest.
    ///      Read-only (does not write state), mirrors _accrueInterest logic.
    function _currentDebt(address user, address asset) internal view returns (uint256) {
        UserPosition storage pos = positions[user][asset];
        if (pos.borrowed == 0) return 0;

        AssetConfig storage cfg = assetConfigs[asset];
        uint256 elapsed = block.timestamp - cfg.lastUpdateTime;
        uint256 projectedIndex = cfg.debtIndex;

        if (elapsed > 0 && cfg.totalBorrowed > 0) {
            uint256 rate = _currentInterestRate(asset);
            uint256 rt   = rate * elapsed / SECONDS_PER_YEAR;
            uint256 interestFactor = rt + (rt * rt / (2 * PRECISION));
            projectedIndex += cfg.debtIndex * interestFactor / PRECISION;
        }

        return pos.borrowed * projectedIndex / pos.borrowIndex;
    }

    /* ─────────────────────────── Health Factor ──────────────────────── */

    /// @notice Compute health factor across all supported assets for a user.
    ///         Returns type(uint256).max if user has no debt.
    ///         Health factor < 1e18 means the position is liquidatable.
    function healthFactor(address user) public view returns (uint256) {
        uint256 totalCollateralUSD = 0;
        uint256 totalDebtUSD       = 0;

        for (uint256 i = 0; i < supportedAssets.length; i++) {
            address asset = supportedAssets[i];
            UserPosition storage pos = positions[user][asset];
            uint8 tokenDec = ITokenDecimals(asset).decimals();

            if (pos.deposited > 0) {
                (uint256 price, uint8 priceDec) = oracle.getPrice(asset);
                uint256 valueUSD = _toUSD18(pos.deposited, tokenDec, price, priceDec);
                totalCollateralUSD += valueUSD * LIQUIDATION_THRESHOLD / 100;
            }

            if (pos.borrowed > 0) {
                (uint256 price, uint8 priceDec) = oracle.getPrice(asset);
                uint256 debtValue = _toUSD18(_currentDebt(user, asset), tokenDec, price, priceDec);
                totalDebtUSD += debtValue;
            }
        }

        if (totalDebtUSD == 0) return type(uint256).max;
        return totalCollateralUSD * PRECISION / totalDebtUSD;
    }

    /* ─────────────────────────── Core Functions ─────────────────────── */

    /// @notice Deposit collateral into the pool.
    ///         Respects supplyCap if set.
    function deposit(address asset, uint256 amount) external nonReentrant whenNotPaused {
        require(assetConfigs[asset].supported, "LendingPool: asset not supported");
        require(amount > 0, "LendingPool: zero amount");
        _accrueInterest(asset);

        AssetConfig storage cfg = assetConfigs[asset];
        if (cfg.supplyCap > 0) {
            require(cfg.totalDeposited + amount <= cfg.supplyCap, "LendingPool: supply cap exceeded");
        }

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        positions[msg.sender][asset].deposited += amount;
        cfg.totalDeposited += amount;

        emit Deposited(msg.sender, asset, amount);
    }

    /// @notice Withdraw collateral. Health factor must remain >= 1.0 after withdrawal.
    function withdraw(address asset, uint256 amount) external nonReentrant whenNotPaused {
        require(assetConfigs[asset].supported, "LendingPool: asset not supported");
        require(amount > 0, "LendingPool: zero amount");
        _accrueInterest(asset);

        UserPosition storage pos = positions[msg.sender][asset];
        require(pos.deposited >= amount, "LendingPool: insufficient deposit");

        pos.deposited -= amount;
        assetConfigs[asset].totalDeposited -= amount;

        if (pos.borrowed > 0) {
            require(healthFactor(msg.sender) >= PRECISION, "LendingPool: unhealthy after withdraw");
        }

        IERC20(asset).safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, asset, amount);
    }

    /// @notice Borrow tokens against deposited collateral.
    ///         Enforces 75% LTV cap AND a 5% health factor buffer post-borrow.
    function borrow(address asset, uint256 amount) external nonReentrant whenNotPaused {
        require(assetConfigs[asset].supported, "LendingPool: asset not supported");
        require(amount > 0, "LendingPool: zero amount");
        _accrueInterest(asset);

        AssetConfig storage cfg = assetConfigs[asset];
        require(
            IERC20(asset).balanceOf(address(this)) - reserves[asset] >= amount,
            "LendingPool: insufficient liquidity"
        );

        // Enforce borrow cap
        if (cfg.borrowCap > 0) {
            require(cfg.totalBorrowed + amount <= cfg.borrowCap, "LendingPool: borrow cap exceeded");
        }

        // Compute total collateral USD value across all assets
        uint256 totalCollateralUSD = 0;
        (uint256 assetPrice, uint8 assetPriceDec) = oracle.getPrice(asset);
        uint8 assetTokenDec = ITokenDecimals(asset).decimals();

        for (uint256 i = 0; i < supportedAssets.length; i++) {
            address collateral = supportedAssets[i];
            uint256 dep = positions[msg.sender][collateral].deposited;
            if (dep > 0) {
                (uint256 colPrice, uint8 colPriceDec) = oracle.getPrice(collateral);
                uint8 colTokenDec = ITokenDecimals(collateral).decimals();
                totalCollateralUSD += _toUSD18(dep, colTokenDec, colPrice, colPriceDec);
            }
        }

        uint256 maxBorrowUSD   = totalCollateralUSD * LTV_RATIO / 100;
        uint256 currentDebtUSD = _toUSD18(_currentDebt(msg.sender, asset), assetTokenDec, assetPrice, assetPriceDec);
        uint256 newDebtUSD     = currentDebtUSD + _toUSD18(amount, assetTokenDec, assetPrice, assetPriceDec);

        require(newDebtUSD <= maxBorrowUSD, "LendingPool: exceeds LTV");

        // Update position
        UserPosition storage pos = positions[msg.sender][asset];
        if (pos.borrowed == 0) {
            pos.borrowIndex = cfg.debtIndex;
            pos.borrowed    = amount;
        } else {
            pos.borrowed    = _currentDebt(msg.sender, asset) + amount;
            pos.borrowIndex = cfg.debtIndex;
        }
        cfg.totalBorrowed += amount;

        // 5% health factor buffer: ensures user isn't immediately at risk of liquidation
        require(healthFactor(msg.sender) >= MIN_HEALTH_AFTER_BORROW, "LendingPool: insufficient health buffer");

        IERC20(asset).safeTransfer(msg.sender, amount);
        emit Borrowed(msg.sender, asset, amount);
    }

    /// @notice Repay borrowed tokens (full or partial).
    function repay(address asset, uint256 amount) external nonReentrant whenNotPaused {
        require(assetConfigs[asset].supported, "LendingPool: asset not supported");
        require(amount > 0, "LendingPool: zero amount");
        _accrueInterest(asset);

        UserPosition storage pos = positions[msg.sender][asset];
        uint256 debt = _currentDebt(msg.sender, asset);
        require(debt > 0, "LendingPool: no debt");

        uint256 repayAmount = amount > debt ? debt : amount;
        pos.borrowed    = debt - repayAmount;
        pos.borrowIndex = assetConfigs[asset].debtIndex;

        uint256 totalBorrowed = assetConfigs[asset].totalBorrowed;
        assetConfigs[asset].totalBorrowed = repayAmount > totalBorrowed ? 0 : totalBorrowed - repayAmount;

        IERC20(asset).safeTransferFrom(msg.sender, address(this), repayAmount);
        emit Repaid(msg.sender, asset, repayAmount);
    }

    /// @notice Liquidate an undercollateralized position.
    /// @param borrower        The user being liquidated
    /// @param debtAsset       Token the borrower owes
    /// @param collateralAsset Token seized from the borrower
    /// @param debtAmount      Amount of debt to repay (capped at 50% close factor)
    function liquidate(
        address borrower,
        address debtAsset,
        address collateralAsset,
        uint256 debtAmount
    ) external nonReentrant whenNotPaused {
        require(healthFactor(borrower) < PRECISION, "LendingPool: position is healthy");
        _accrueInterest(debtAsset);
        _accrueInterest(collateralAsset);

        uint256 totalDebt = _currentDebt(borrower, debtAsset);
        require(totalDebt > 0, "LendingPool: no debt");

        // Close factor: max 50% of debt per liquidation call
        uint256 maxRepay    = totalDebt * CLOSE_FACTOR / 100;
        uint256 repayAmount = debtAmount > maxRepay ? maxRepay : debtAmount;

        // Calculate collateral to seize (USD-normalized, with liquidation bonus)
        (uint256 debtPrice,  uint8 debtPriceDec) = oracle.getPrice(debtAsset);
        (uint256 colPrice,   uint8 colPriceDec)  = oracle.getPrice(collateralAsset);
        uint8 debtTokenDec = ITokenDecimals(debtAsset).decimals();
        uint8 colTokenDec  = ITokenDecimals(collateralAsset).decimals();

        uint256 debtValueUSD18    = _toUSD18(repayAmount, debtTokenDec, debtPrice, debtPriceDec);
        uint256 colPriceUSD18     = _toUSD18(10 ** colTokenDec, colTokenDec, colPrice, colPriceDec);
        uint256 collateralToSeize = debtValueUSD18 * LIQUIDATION_BONUS / 100 * (10 ** colTokenDec) / colPriceUSD18;

        require(
            positions[borrower][collateralAsset].deposited >= collateralToSeize,
            "LendingPool: insufficient collateral"
        );

        // Update borrower position
        positions[borrower][debtAsset].borrowed     = totalDebt - repayAmount;
        positions[borrower][debtAsset].borrowIndex  = assetConfigs[debtAsset].debtIndex;
        positions[borrower][collateralAsset].deposited -= collateralToSeize;
        assetConfigs[collateralAsset].totalDeposited   -= collateralToSeize;

        uint256 totalBorrowed = assetConfigs[debtAsset].totalBorrowed;
        assetConfigs[debtAsset].totalBorrowed = repayAmount > totalBorrowed ? 0 : totalBorrowed - repayAmount;

        // Liquidator pays debt → receives collateral + bonus
        IERC20(debtAsset).safeTransferFrom(msg.sender, address(this), repayAmount);
        IERC20(collateralAsset).safeTransfer(msg.sender, collateralToSeize);

        emit Liquidated(msg.sender, borrower, collateralAsset, debtAsset, repayAmount, collateralToSeize);
    }

    /* ─────────────────────────── Flash Loans ───────────────────────── */

    /// @notice Execute a flash loan. The receiver must implement IFlashLoanReceiver.
    ///         The full amount + fee must be repaid by the end of this transaction.
    ///
    /// @dev Flash loans are pure protocol revenue:
    ///      - 0.09% fee on the borrowed amount
    ///      - Fee goes directly into reserves[asset]
    ///      - No collateral required — atomicity guarantees repayment
    ///
    /// @param receiver  Contract that will receive and use the funds
    /// @param asset     Token to borrow
    /// @param amount    Amount to borrow
    /// @param data      Arbitrary data passed to the receiver's executeOperation
    function flashLoan(
        address receiver,
        address asset,
        uint256 amount,
        bytes calldata data
    ) external nonReentrant whenNotPaused {
        require(flashLoanEnabled, "LendingPool: flash loans disabled");
        require(assetConfigs[asset].supported, "LendingPool: asset not supported");
        require(amount > 0, "LendingPool: zero amount");

        uint256 poolBalance = IERC20(asset).balanceOf(address(this));
        // Available = pool balance minus protocol-owned reserves
        require(poolBalance - reserves[asset] >= amount, "LendingPool: insufficient liquidity");

        uint256 fee = amount * FLASH_LOAN_FEE_BPS / FLASH_LOAN_FEE_DENOM;
        // repayAmount = amount + fee (checked via balance comparison below)

        // Transfer funds to receiver
        IERC20(asset).safeTransfer(receiver, amount);

        // Receiver executes arbitrary logic and must repay before returning
        IFlashLoanReceiver(receiver).executeOperation(asset, amount, fee, data);

        // Verify full repayment
        uint256 newBalance = IERC20(asset).balanceOf(address(this));
        require(newBalance >= poolBalance + fee, "LendingPool: flash loan not repaid");

        // Accrue fee to protocol reserves
        reserves[asset] += fee;
        emit ReservesAccrued(asset, fee);
        emit FlashLoan(receiver, asset, amount, fee);
    }

    /* ─────────────────────────── Views ─────────────────────────────── */

    function getUserDebt(address user, address asset) external view returns (uint256) {
        return _currentDebt(user, asset);
    }

    function getInterestRate(address asset) external view returns (uint256) {
        return _currentInterestRate(asset);
    }

    function getUtilizationRate(address asset) external view returns (uint256) {
        AssetConfig storage cfg = assetConfigs[asset];
        if (cfg.totalDeposited == 0) return 0;
        return cfg.totalBorrowed * PRECISION / cfg.totalDeposited;
    }

    function getAllSupportedAssets() external view returns (address[] memory) {
        return supportedAssets;
    }

    function getReserves(address asset) external view returns (uint256) {
        return reserves[asset];
    }
}

/* ─────────────────────────── Interfaces ───────────────────────── */

/// @dev Minimal decimals interface — all standard ERC-20 tokens implement this
interface ITokenDecimals {
    function decimals() external view returns (uint8);
}

/// @dev Flash loan receiver interface — implement this in your flash loan consumer
interface IFlashLoanReceiver {
    /// @param asset    The token that was borrowed
    /// @param amount   Amount borrowed (must repay amount + fee before returning)
    /// @param fee      Protocol fee (0.09% of amount)
    /// @param data     Arbitrary data passed from the flashLoan call
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external;
}
