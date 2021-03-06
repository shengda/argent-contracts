// Copyright (C) 2018  Argent Labs Ltd. <https://argent.xyz>

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./common/Utils.sol";
import "./common/LimitUtils.sol";
import "./common/BaseTransfer.sol";
import "../infrastructure/storage/ILimitStorage.sol";

/**
 * @title ApprovedTransfer
 * @notice Module to transfer tokens (ETH or ERC20) or call third-party contracts with the approval of guardians.
 * @author Julien Niset - <julien@argent.xyz>
 */
contract ApprovedTransfer is BaseTransfer {

    bytes32 constant NAME = "ApprovedTransfer";

    // The limit storage
    ILimitStorage public limitStorage;

    constructor(
        IModuleRegistry _registry,
        IGuardianStorage _guardianStorage,
        ILimitStorage _limitStorage,
        address _wethToken
    )
        BaseModule(_registry, _guardianStorage, NAME)
        BaseTransfer(_wethToken)
        public
    {
        limitStorage = _limitStorage;
    }

    /**
    * @notice Transfers tokens (ETH or ERC20) from a wallet.
    * @param _wallet The target wallet.
    * @param _token The address of the token to transfer.
    * @param _to The destination address
    * @param _amount The amount of token to transfer
    * @param _data  The data for the transaction (only for ETH transfers)
    */
    function transferToken(
        address _wallet,
        address _token,
        address _to,
        uint256 _amount,
        bytes calldata _data
    )
        external
        onlyWalletModule(_wallet)
        onlyWhenUnlocked(_wallet)
    {
        doTransfer(_wallet, _token, _to, _amount, _data);
        LimitUtils.resetDailySpent(limitStorage, _wallet);
    }

    /**
    * @notice Call a contract.
    * @param _wallet The target wallet.
    * @param _contract The address of the contract.
    * @param _value The amount of ETH to transfer as part of call
    * @param _data The encoded method data
    */
    function callContract(
        address _wallet,
        address _contract,
        uint256 _value,
        bytes calldata _data
    )
        external
        onlyWalletModule(_wallet)
        onlyWhenUnlocked(_wallet)
        onlyAuthorisedContractCall(_wallet, _contract)
    {
        doCallContract(_wallet, _contract, _value, _data);
        LimitUtils.resetDailySpent(limitStorage, _wallet);
    }

    /**
    * @notice Lets the owner do an ERC20 approve followed by a call to a contract.
    * The address to approve may be different than the contract to call.
    * We assume that the contract does not require ETH.
    * @param _wallet The target wallet.
    * @param _token The token to approve.
    * @param _spender The address to approve.
    * @param _amount The amount of ERC20 tokens to approve.
    * @param _contract The contract to call.
    * @param _data The encoded method data
    */
    function approveTokenAndCallContract(
        address _wallet,
        address _token,
        address _spender,
        uint256 _amount,
        address _contract,
        bytes calldata _data
    )
        external
        onlyWalletModule(_wallet)
        onlyWhenUnlocked(_wallet)
        onlyAuthorisedContractCall(_wallet, _contract)
    {
        doApproveTokenAndCallContract(_wallet, _token, _spender, _amount, _contract, _data);
        LimitUtils.resetDailySpent(limitStorage, _wallet);
    }

    /**
     * @notice Changes the daily limit. The change is immediate.
     * @param _wallet The target wallet.
     * @param _newLimit The new limit.
     */
    function changeLimit(address _wallet, uint256 _newLimit) external onlyWalletModule(_wallet) onlyWhenUnlocked(_wallet) {
        uint128 targetLimit = LimitUtils.safe128(_newLimit);
        ILimitStorage.Limit memory newLimit = ILimitStorage.Limit(targetLimit, targetLimit, LimitUtils.safe64(block.timestamp));
        ILimitStorage.DailySpent memory resetDailySpent = ILimitStorage.DailySpent(uint128(0), uint64(0));
        limitStorage.setLimitAndDailySpent(_wallet, newLimit, resetDailySpent);
        emit LimitChanged(_wallet, _newLimit, newLimit.changeAfter);
    }

    /**
    * @notice Resets the daily spent amount.
    * @param _wallet The target wallet.
    */
    function resetDailySpent(address _wallet) external onlyWalletModule(_wallet) onlyWhenUnlocked(_wallet) {
        LimitUtils.resetDailySpent(limitStorage, _wallet);
    }

    /**
    * @notice lets the owner wrap ETH into WETH, approve the WETH and call a contract.
    * The address to approve may be different than the contract to call.
    * We assume that the contract does not require ETH.
    * @param _wallet The target wallet.
    * @param _spender The address to approve.
    * @param _amount The amount of ERC20 tokens to approve.
    * @param _contract The contract to call.
    * @param _data The encoded method data
    */
    function approveWethAndCallContract(
        address _wallet,
        address _spender,
        uint256 _amount,
        address _contract,
        bytes calldata _data
    )
        external
        onlyWalletModule(_wallet)
        onlyWhenUnlocked(_wallet)
        onlyAuthorisedContractCall(_wallet, _contract)
    {
        doApproveWethAndCallContract(_wallet, _spender, _amount, _contract, _data);
    }

    /**
     * @inheritdoc IModule
     */
    function getRequiredSignatures(address _wallet, bytes calldata _data) external view override returns (uint256, OwnerSignature) {
        // owner  + [n/2] guardians
        uint numberOfSignatures = 1 + Utils.ceil(guardianStorage.guardianCount(_wallet), 2);
        return (numberOfSignatures, OwnerSignature.Required);
    }
}