// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.10;

import {IERC20} from '../dependencies/aave-core/dependencies/openzeppelin/contracts/IERC20.sol';
import {FlashLoanReceiverBase} from '../dependencies/aave-core-v8/flashloan/base/FlashLoanReceiverBase.sol';
import {SafeERC20} from '../dependencies/aave-core-v8/dependencies/openzeppelin/contracts/SafeERC20.sol';
import {ILendingPoolAddressesProvider} from '../dependencies/aave-core-v8/interfaces/ILendingPoolAddressesProvider.sol';

contract MockFlashLoanReceiver is FlashLoanReceiverBase {
  using SafeERC20 for IERC20;

  ILendingPoolAddressesProvider internal _provider;

  event ExecutedWithFail(address[] _assets, uint256[] _amounts, uint256[] _premiums);
  event ExecutedWithSuccess(address[] _assets, uint256[] _amounts, uint256[] _premiums);

  bool _failExecution;
  uint256 _amountToApprove;
  bool _simulateEOA;

  constructor(ILendingPoolAddressesProvider provider) public FlashLoanReceiverBase(provider) {}

  function setFailExecutionTransfer(bool fail) public {
    _failExecution = fail;
  }

  function setAmountToApprove(uint256 amountToApprove) public {
    _amountToApprove = amountToApprove;
  }

  function setSimulateEOA(bool flag) public {
    _simulateEOA = flag;
  }

  function amountToApprove() public view returns (uint256) {
    return _amountToApprove;
  }

  function simulateEOA() public view returns (bool) {
    return _simulateEOA;
  }

  function executeOperation(
    address[] memory assets,
    uint256[] memory amounts,
    uint256[] memory premiums,
    address initiator,
    bytes memory params
  ) public override returns (bool) {
    params;
    initiator;

    if (_failExecution) {
      emit ExecutedWithFail(assets, amounts, premiums);
      return !_simulateEOA;
    }

    for (uint256 i = 0; i < assets.length; i++) {
      //check the contract has the specified balance
      require(
        amounts[i] <= IERC20(assets[i]).balanceOf(address(this)),
        'Invalid balance for the contract'
      );

      uint256 amountToReturn = amounts[i] + premiums[i];

      IERC20(assets[i]).approve(address(LENDING_POOL), amountToReturn);
    }

    emit ExecutedWithSuccess(assets, amounts, premiums);

    return true;
  }
}
