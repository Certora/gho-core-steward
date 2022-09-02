// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import {IERC20} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol';
import {SafeCast} from '@aave/core-v3/contracts/dependencies/openzeppelin/contracts/SafeCast.sol';
import {VersionedInitializable} from '@aave/core-v3/contracts/protocol/libraries/aave-upgradeability/VersionedInitializable.sol';
import {WadRayMath} from '@aave/core-v3/contracts/protocol/libraries/math/WadRayMath.sol';
import {PercentageMath} from '@aave/core-v3/contracts/protocol/libraries/math/PercentageMath.sol';
import {Errors} from '@aave/core-v3/contracts/protocol/libraries/helpers/Errors.sol';
import {IPool} from '@aave/core-v3/contracts/interfaces/IPool.sol';
import {IAaveIncentivesController} from '@aave/core-v3/contracts/interfaces/IAaveIncentivesController.sol';
import {IInitializableDebtToken} from '@aave/core-v3/contracts/interfaces/IInitializableDebtToken.sol';
import {IVariableDebtToken} from '@aave/core-v3/contracts/interfaces/IVariableDebtToken.sol';
import {IScaledBalanceToken} from '@aave/core-v3/contracts/interfaces/IScaledBalanceToken.sol';
import {EIP712Base} from '@aave/core-v3/contracts/protocol/tokenization/base/EIP712Base.sol';
import {DebtTokenBase} from '@aave/core-v3/contracts/protocol/tokenization/base/DebtTokenBase.sol';
import {MintableIncentivizedERC20} from '@aave/core-v3/contracts/protocol/tokenization/base/MintableIncentivizedERC20.sol';

// Gho imports
import {IGhoVariableDebtToken} from './interfaces/IGhoVariableDebtToken.sol';
import {IGhoDiscountRateStrategy} from './interfaces/IGhoDiscountRateStrategy.sol';

/**
 * @title VariableDebtToken
 * @author Aave
 * @notice Implements a variable debt token to track the borrowing positions of users
 * at variable rate mode
 * @dev Transfer and approve functionalities are disabled since its a non-transferable token
 **/
contract GhoVariableDebtToken3 is DebtTokenBase, MintableIncentivizedERC20, IGhoVariableDebtToken {
  using WadRayMath for uint256;
  using SafeCast for uint256;
  using PercentageMath for uint256;

  uint256 public constant DEBT_TOKEN_REVISION = 0x1;

  // NEW Gho Storage
  // Corresponding AToken to this DebtToken
  address internal _ghoAToken;

  // Token that grants discounts off the debt interest
  IERC20 internal _discountToken;

  // Strategy of the discount rate to apply on debt interests
  IGhoDiscountRateStrategy internal _discountRateStrategy;

  struct GhoUserState {
    // Accumulated debt interest of the user
    uint128 accumulatedDebtInterest;
    // Discount percent of the user (expressed in bps)
    uint16 discountPercent;
    // Timestamp when users discount can be rebalanced
    uint40 rebalanceTimestamp;
  }

  // Map of users address and their gho state data (userAddress => ghoUserState)
  mapping(address => GhoUserState) internal _ghoUserState;

  // Minimum amount of time a user is entitled to a discount without performing additional actions (expressed in seconds)
  uint256 internal _discountLockPeriod;

  /**
   * @dev Only AToken can call functions marked by this modifier.
   **/
  modifier onlyAToken() {
    require(_ghoAToken == msg.sender, 'CALLER_NOT_A_TOKEN');
    _;
  }

  /**
   * @dev Only discount token can call functions marked by this modifier.
   **/
  modifier onlyDiscountToken() {
    require(address(_discountToken) == msg.sender, 'CALLER_NOT_DISCOUNT_TOKEN');
    _;
  }

  /**
   * @dev Constructor.
   * @param pool The address of the Pool contract
   */
  constructor(IPool pool)
    DebtTokenBase()
    MintableIncentivizedERC20(pool, 'VARIABLE_DEBT_TOKEN_IMPL', 'VARIABLE_DEBT_TOKEN_IMPL', 0)
  {
    // Intentionally left blank
  }

  /// @inheritdoc IInitializableDebtToken
  function initialize(
    IPool initializingPool,
    address underlyingAsset,
    IAaveIncentivesController incentivesController,
    uint8 debtTokenDecimals,
    string memory debtTokenName,
    string memory debtTokenSymbol,
    bytes calldata params
  ) external override initializer {
    require(initializingPool == POOL, Errors.POOL_ADDRESSES_DO_NOT_MATCH);
    _setName(debtTokenName);
    _setSymbol(debtTokenSymbol);
    _setDecimals(debtTokenDecimals);

    _underlyingAsset = underlyingAsset;
    _incentivesController = incentivesController;

    _domainSeparator = _calculateDomainSeparator();

    emit Initialized(
      underlyingAsset,
      address(POOL),
      address(incentivesController),
      debtTokenDecimals,
      debtTokenName,
      debtTokenSymbol,
      params
    );
  }

  /// @inheritdoc VersionedInitializable
  function getRevision() internal pure virtual override returns (uint256) {
    return DEBT_TOKEN_REVISION;
  }

  /// @inheritdoc IERC20
  function balanceOf(address user) public view virtual override returns (uint256) {
    uint256 scaledBalance = super.balanceOf(user);

    if (scaledBalance == 0) {
      return 0;
    }

    uint256 index = POOL.getReserveNormalizedVariableDebt(_underlyingAsset);
    uint256 previousIndex = _userState[user].additionalData;
    uint256 balance = scaledBalance.rayMul(index);
    if (index == previousIndex) {
      return balance;
    }

    uint256 discountPercent = _ghoUserState[user].discountPercent;
    if (discountPercent != 0) {
      uint256 balanceIncrease = balance - scaledBalance.rayMul(previousIndex);
      uint256 discount = balanceIncrease.percentMul(discountPercent);
      balance = balance - discount;
    }

    return balance;
  }

  /// @inheritdoc IVariableDebtToken
  function mint(
    address user,
    address onBehalfOf,
    uint256 amount,
    uint256 index
  ) external virtual override onlyPool returns (bool, uint256) {
    if (user != onBehalfOf) {
      _decreaseBorrowAllowance(onBehalfOf, user, amount);
    }

    uint256 amountScaled = amount.rayDiv(index);
    require(amountScaled != 0, Errors.INVALID_MINT_AMOUNT);

    uint256 previousScaledBalance = super.balanceOf(onBehalfOf);
    uint256 discountPercent = _ghoUserState[onBehalfOf].discountPercent;
    (uint256 balanceIncrease, uint256 discountScaled) = _accrueDebtOnAction(
      onBehalfOf,
      previousScaledBalance,
      discountPercent,
      index
    );

    // confirm the amount being borrowed is greater than the discount
    if (amountScaled > discountScaled) {
      _mint(onBehalfOf, (amountScaled - discountScaled).toUint128());
    } else {
      _burn(onBehalfOf, (discountScaled - amountScaled).toUint128());
    }

    refreshDiscountPercent(
      onBehalfOf,
      super.balanceOf(onBehalfOf).rayMul(index),
      _discountToken.balanceOf(onBehalfOf),
      discountPercent
    );

    uint256 amountToMint = amount + balanceIncrease;
    emit Transfer(address(0), onBehalfOf, amountToMint);
    emit Mint(user, onBehalfOf, amountToMint, balanceIncrease, index);

    return (previousScaledBalance == 0, scaledTotalSupply());
  }

  /// @inheritdoc IVariableDebtToken
  function burn(
    address from,
    uint256 amount,
    uint256 index
  ) external virtual override onlyPool returns (uint256) {
    uint256 amountScaled = amount.rayDiv(index);
    require(amountScaled != 0, Errors.INVALID_BURN_AMOUNT);

    uint256 previousScaledBalance = super.balanceOf(from);
    uint256 discountPercent = _ghoUserState[from].discountPercent;
    (uint256 balanceIncrease, uint256 discountScaled) = _accrueDebtOnAction(
      from,
      previousScaledBalance,
      discountPercent,
      index
    );

    _burn(from, (amountScaled + discountScaled).toUint128());

    refreshDiscountPercent(
      from,
      super.balanceOf(from).rayMul(index),
      _discountToken.balanceOf(from),
      discountPercent
    );

    if (balanceIncrease > amount) {
      uint256 amountToMint = balanceIncrease - amount;
      emit Transfer(address(0), from, amountToMint);
      emit Mint(from, from, amountToMint, balanceIncrease, index);
    } else {
      uint256 amountToBurn = amount - balanceIncrease;
      emit Transfer(from, address(0), amountToBurn);
      emit Burn(from, address(0), amountToBurn, balanceIncrease, index);
    }

    return scaledTotalSupply();
  }

  /// @inheritdoc IERC20
  function totalSupply() public view virtual override returns (uint256) {
    return super.totalSupply().rayMul(POOL.getReserveNormalizedVariableDebt(_underlyingAsset));
  }

  /// @inheritdoc EIP712Base
  function _EIP712BaseId() internal view override returns (string memory) {
    return name();
  }

  /// @inheritdoc IScaledBalanceToken
  function scaledBalanceOf(address user) external view override returns (uint256) {
    return super.balanceOf(user);
  }

  /// @inheritdoc IScaledBalanceToken
  function getScaledUserBalanceAndSupply(address user)
    external
    view
    override
    returns (uint256, uint256)
  {
    return (super.balanceOf(user), super.totalSupply());
  }

  /// @inheritdoc IScaledBalanceToken
  function scaledTotalSupply() public view virtual override returns (uint256) {
    return super.totalSupply();
  }

  /// @inheritdoc IScaledBalanceToken
  function getPreviousIndex(address user) external view virtual override returns (uint256) {
    return _userState[user].additionalData;
  }

  /**
   * @dev Gho specific logic
   **/

  // @inheritdoc IGhoVariableDebtToken
  function updateDiscountDistribution(
    address sender,
    address recipient,
    uint256 senderDiscountTokenBalance,
    uint256 recipientDiscountTokenBalance,
    uint256 amount
  ) external override onlyDiscountToken {
    uint256 senderPreviousScaledBalance = super.balanceOf(sender);
    uint256 recipientPreviousScaledBalance = super.balanceOf(recipient);

    uint256 index = POOL.getReserveNormalizedVariableDebt(_underlyingAsset);

    uint256 balanceIncrease;
    uint256 discountScaled;

    if (senderPreviousScaledBalance > 0) {
      (balanceIncrease, discountScaled) = _accrueDebtOnAction(
        sender,
        senderPreviousScaledBalance,
        _ghoUserState[sender].discountPercent,
        index
      );

      _burn(sender, discountScaled.toUint128());

      refreshDiscountPercent(
        sender,
        super.balanceOf(sender).rayMul(index),
        senderDiscountTokenBalance - amount,
        _ghoUserState[sender].discountPercent
      );

      emit Transfer(address(0), sender, balanceIncrease);
      emit Mint(address(0), sender, balanceIncrease, balanceIncrease, index);
    }

    if (recipientPreviousScaledBalance > 0) {
      (balanceIncrease, discountScaled) = _accrueDebtOnAction(
        recipient,
        recipientPreviousScaledBalance,
        _ghoUserState[recipient].discountPercent,
        index
      );

      _burn(recipient, discountScaled.toUint128());

      refreshDiscountPercent(
        recipient,
        super.balanceOf(recipient).rayMul(index),
        recipientDiscountTokenBalance + amount,
        _ghoUserState[recipient].discountPercent
      );

      emit Transfer(address(0), recipient, balanceIncrease);
      emit Mint(address(0), recipient, balanceIncrease, balanceIncrease, index);
    }
  }

  // @inheritdoc IGhoVariableDebtToken
  function rebalanceUserDiscountPercent(address user) external override {
    require(
      _ghoUserState[user].rebalanceTimestamp < block.timestamp &&
        _ghoUserState[user].rebalanceTimestamp != 0,
      'DISCOUNT_PERCENT_REBALANCE_CONDITION_NOT_MET'
    );

    uint256 index = POOL.getReserveNormalizedVariableDebt(_underlyingAsset);
    uint256 previousScaledBalance = super.balanceOf(user);
    uint256 discountPercent = _ghoUserState[user].discountPercent;

    (uint256 balanceIncrease, uint256 discountScaled) = _accrueDebtOnAction(
      user,
      previousScaledBalance,
      discountPercent,
      index
    );

    _burn(user, discountScaled.toUint128());

    refreshDiscountPercent(
      user,
      super.balanceOf(user).rayMul(index),
      _discountToken.balanceOf(user),
      discountPercent
    );

    emit Transfer(address(0), user, balanceIncrease);
    emit Mint(address(0), user, balanceIncrease, balanceIncrease, index);
  }

  // @inheritdoc IGhoVariableDebtToken
  function decreaseBalanceFromInterest(address user, uint256 amount) external override onlyAToken {
    _ghoUserState[user].accumulatedDebtInterest = (_ghoUserState[user].accumulatedDebtInterest -
      amount).toUint128();
  }

  // @inheritdoc IGhoVariableDebtToken
  function getDiscountPercent(address user) external view override returns (uint256) {
    return _ghoUserState[user].discountPercent;
  }

  // @inheritdoc IGhoVariableDebtToken
  function getBalanceFromInterest(address user) external view override returns (uint256) {
    return _ghoUserState[user].accumulatedDebtInterest;
  }

  /// @inheritdoc IGhoVariableDebtToken
  function setAToken(address ghoAToken) external override onlyPoolAdmin {
    require(_ghoAToken == address(0), 'ATOKEN_ALREADY_SET');
    _ghoAToken = ghoAToken;
    emit ATokenSet(ghoAToken);
  }

  /// @inheritdoc IGhoVariableDebtToken
  function getAToken() external view override returns (address) {
    return _ghoAToken;
  }

  /// @inheritdoc IGhoVariableDebtToken
  function updateDiscountRateStrategy(address discountRateStrategy)
    external
    override
    onlyPoolAdmin
  {
    address previousDiscountRateStrategy = address(_discountRateStrategy);
    _discountRateStrategy = IGhoDiscountRateStrategy(discountRateStrategy);
    emit DiscountRateStrategyUpdated(previousDiscountRateStrategy, discountRateStrategy);
  }

  /// @inheritdoc IGhoVariableDebtToken
  function getDiscountRateStrategy() external view override returns (address) {
    return address(_discountRateStrategy);
  }

  /// @inheritdoc IGhoVariableDebtToken
  function updateDiscountToken(address discountToken) external override onlyPoolAdmin {
    address previousDiscountToken = address(_discountToken);
    _discountToken = IERC20(discountToken);
    emit DiscountTokenUpdated(previousDiscountToken, discountToken);
  }

  /// @inheritdoc IGhoVariableDebtToken
  function getDiscountToken() external view override returns (address) {
    return address(_discountToken);
  }

  // @inheritdoc IGhoVariableDebtToken
  function updateDiscountLockPeriod(uint256 newLockPeriod) external override onlyPoolAdmin {
    uint256 oldLockPeriod = _discountLockPeriod;
    _discountLockPeriod = uint40(newLockPeriod);
    emit DiscountLockPeriodUpdated(oldLockPeriod, newLockPeriod);
  }

  // @inheritdoc IGhoVariableDebtToken
  function getDiscountLockPeriod() external view override returns (uint256) {
    return _discountLockPeriod;
  }

  // @inheritdoc IGhoVariableDebtToken
  function getUserRebalanceTimestamp(address user) external view override returns (uint256) {
    return _ghoUserState[user].rebalanceTimestamp;
  }

  /**
   * @dev Accumulates debt of the user since last action.
   * @dev It skips applying discount in case there is no balance increase or discount percent is zero.
   * @param user The address of the user
   * @param previousScaledBalance The previous scaled balance of the user
   * @param discountPercent The discount percent
   * @param index The variable debt index of the reserve
   * @return The increase in scaled balance since the last action of `user`
   * @return The discounted amount in scaled balance off the balance increase
   */
  function _accrueDebtOnAction(
    address user,
    uint256 previousScaledBalance,
    uint256 discountPercent,
    uint256 index
  ) internal returns (uint256, uint256) {
    uint256 balanceIncrease = previousScaledBalance.rayMul(index) -
      previousScaledBalance.rayMul(_userState[user].additionalData);

    uint256 discountScaled = 0;
    if (balanceIncrease != 0 && discountPercent != 0) {
      uint256 discount = balanceIncrease.percentMul(discountPercent);

      // skip checked division to
      // avoid rounding in the case discount = 100%
      // The index will never be 0
      discountScaled = (discount * WadRayMath.RAY) / index;

      balanceIncrease = balanceIncrease - discount;
    }

    _userState[user].additionalData = index.toUint128();

    _ghoUserState[user].accumulatedDebtInterest = (balanceIncrease +
      _ghoUserState[user].accumulatedDebtInterest).toUint128();

    return (balanceIncrease, discountScaled);
  }

  /**
   * @dev Updates the discount percent of the user according to current discount rate strategy
   * @param user The address of the user
   * @param balance The debt balance of the user
   * @param discountTokenBalance The discount token balance of the user
   * @param previousDiscountPercent The previous discount percent of the user
   */
  function refreshDiscountPercent(
    address user,
    uint256 balance,
    uint256 discountTokenBalance,
    uint256 previousDiscountPercent
  ) internal {
    uint256 newDiscountPercent = _discountRateStrategy.calculateDiscountRate(
      balance,
      discountTokenBalance
    );

    bool changed = false;
    if (previousDiscountPercent != newDiscountPercent) {
      _ghoUserState[user].discountPercent = newDiscountPercent.toUint16();
      changed = true;
    }

    if (newDiscountPercent != 0) {
      uint40 newRebalanceTimestamp = uint40(block.timestamp + _discountLockPeriod);
      _ghoUserState[user].rebalanceTimestamp = newRebalanceTimestamp;
      emit DiscountPercentLocked(user, newDiscountPercent, newRebalanceTimestamp);
    } else {
      if (changed) {
        _ghoUserState[user].rebalanceTimestamp = 0;
        emit DiscountPercentLocked(user, newDiscountPercent, 0);
      }
    }
  }

  /**
   * @dev Being non transferrable, the debt token does not implement any of the
   * standard ERC20 functions for transfer and allowance.
   **/
  function transfer(address, uint256) external virtual override returns (bool) {
    revert(Errors.OPERATION_NOT_SUPPORTED);
  }

  function allowance(address, address) external view virtual override returns (uint256) {
    revert(Errors.OPERATION_NOT_SUPPORTED);
  }

  function approve(address, uint256) external virtual override returns (bool) {
    revert(Errors.OPERATION_NOT_SUPPORTED);
  }

  function transferFrom(
    address,
    address,
    uint256
  ) external virtual override returns (bool) {
    revert(Errors.OPERATION_NOT_SUPPORTED);
  }

  function increaseAllowance(address, uint256) external virtual override returns (bool) {
    revert(Errors.OPERATION_NOT_SUPPORTED);
  }

  function decreaseAllowance(address, uint256) external virtual override returns (bool) {
    revert(Errors.OPERATION_NOT_SUPPORTED);
  }

  /// @inheritdoc IVariableDebtToken
  function UNDERLYING_ASSET_ADDRESS() external view override returns (address) {
    return _underlyingAsset;
  }
}
