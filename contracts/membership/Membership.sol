// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

import {IMembership} from "../interfaces/IMembership.sol";

import "@matterlabs/zksync-contracts/l2/system-contracts/Constants.sol";
import {Transaction} from "@matterlabs/zksync-contracts/l2/system-contracts/libraries/TransactionHelper.sol";
import {IPaymasterFlow} from "@matterlabs/zksync-contracts/l2/system-contracts/interfaces/IPaymasterFlow.sol";
import {IPaymaster, ExecutionResult, PAYMASTER_VALIDATION_SUCCESS_MAGIC} from "@matterlabs/zksync-contracts/l2/system-contracts/interfaces/IPaymaster.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";

struct PrepareTierData {
    // The tier position. Generally, we assume `low tier number == better tier` (eg Tier 1 > Tier 2).
    uint256 tier;
    uint256 benefit;
    uint256 txCountThreshold;
    bytes4 functionSelector;
    address contractAddress;
}

contract Membership is IMembership, IPaymaster {
    /**
     *
     *
     *  MEMBERSHIP
     *
     *
     */

    /// @dev For demo purposes, we assume that the available `benefit` is only gas fee reduction.
    /// Meaning, the value for benefit is the percentage of the total gas fee that will be paid by the paymaster.
    ///
    /// @dev `txCountThreshold` The total number of transactions that is needed to complete the tier.
    struct TierData {
        uint256 benefit;
        uint256 txCountThreshold;
        bytes4 functionSelector;
        address contractAddress;
    }

    struct TierProgress {
        uint256 txCount;
    }

    //*///////////////////////////////////////////////////////////////
    //    EVENTS
    ///////////////////////////////////////////////////////////////*/

    event UserSubscribe(address indexed user);
    event UserUnsubscribe(address indexed user, uint256 lastTier);
    event TierUpgrade(address indexed user, uint256 indexed newTier);

    //*///////////////////////////////////////////////////////////////
    //    STORAGES
    ///////////////////////////////////////////////////////////////*/

    string private _name;

    uint256 private _tierCount;

    mapping(address => uint256) private _userTier;

    // We assume that < 0 is invalid tier (and 0 means not subscribed)
    mapping(uint256 => TierData) private _tierData;

    // Keep track of user's progress on each tier.
    mapping(address => mapping(uint256 => TierProgress))
        private _userTierProgress;

    //*///////////////////////////////////////////////////////////////
    //    CONSTRUCTOR
    ///////////////////////////////////////////////////////////////*/

    // Although here we doesn't enforce the tier level
    constructor(PrepareTierData[] memory _prepareTierData) {
        for (uint256 i = 0; i < _prepareTierData.length; i++) {
            _tierData[_prepareTierData[i].tier] = TierData({
                benefit: _prepareTierData[i].benefit,
                contractAddress: _prepareTierData[i].contractAddress,
                functionSelector: _prepareTierData[i].functionSelector,
                txCountThreshold: _prepareTierData[i].txCountThreshold
            });
        }

        _tierCount = _prepareTierData.length;
    }

    //*///////////////////////////////////////////////////////////////
    //    VIEWS
    ///////////////////////////////////////////////////////////////*/

    function userTier(address _user) public view returns (uint256) {
        return _userTier[_user];
    }

    function benefit(uint256 _tier) public view returns (uint256) {
        return _tierData[_tier].benefit;
    }

    function totalTier() external view returns (uint256) {
        return _tierCount;
    }

    //*///////////////////////////////////////////////////////////////
    //    EXXTERNALS
    ///////////////////////////////////////////////////////////////*/

    /// @notice when user subscibe for the first time, they get put into the lowest tier.
    /// Here we assume that tiers will all have sequential numbering and the biggest tier number is considered
    /// the starting tier.
    function subscribe() external {
        _userTier[msg.sender] = _tierCount;
        emit UserSubscribe(msg.sender);
    }

    function unsubscribe() external {
        uint lastTier = _userTier[msg.sender];

        require(lastTier > 0, "USER IS NOT SUBSCRIBED");

        _userTier[msg.sender] = 0;
        emit UserUnsubscribe(msg.sender, lastTier);
    }

    function validateAndExecuteMembershipTransaction(
        Transaction calldata _transaction
    ) external returns (bool) {
        if (_validateMembershipTransaction(_transaction)) {
            address user = address(uint160(_transaction.from));
            _updateUserMembershipProgress(user);
            return true;
        } else {
            return false;
        }
    }

    //*///////////////////////////////////////////////////////////////
    //    INTERNALS
    ///////////////////////////////////////////////////////////////*/

    // validate that the transaction is valid for the tier that the user is in currently
    function _validateMembershipTransaction(
        Transaction calldata _transaction
    ) internal returns (bool) {
        address user = address(uint160(_transaction.from));
        uint256 tier = _userTier[user];

        require(tier > 0, "USER IS NOT A MEMBER");

        address to = address(uint160(_transaction.to));
        bytes4 functionSelector = bytes4(_transaction.data[0:4]);

        address tierContractAddress = _tierData[tier].contractAddress;
        bytes4 tierFunctionSelector = _tierData[tier].functionSelector;

        if (
            to == tierContractAddress &&
            functionSelector == tierFunctionSelector
        ) {
            return true;
        } else {
            return false;
        }
    }

    // Update user tx count and upgrade to next tier if pass the tiers threshold
    function _updateUserMembershipProgress(address user) internal {
        uint256 tier = _userTier[user];
        TierData storage tierData = _tierData[tier];

        // increment tx count
        // if tx count >= threshold, then upgrade to next tier
        uint256 newTierTxCount = _userTierProgress[user][tier].txCount + 1;
        _userTierProgress[user][tier].txCount = newTierTxCount;

        if (newTierTxCount == tierData.txCountThreshold) {
            // bcs we assume the tier number gets lower for better tier in the membership
            _userTier[user] -= 1;
        }
    }

    /**
     *
     *
     *  PAYMASTER
     *
     *
     */

    function validateAndPayForPaymasterTransaction(
        bytes32,
        bytes32,
        Transaction calldata _transaction
    ) external payable returns (bytes4 magic, bytes memory context) {
        // By default we consider the transaction as accepted.
        magic = PAYMASTER_VALIDATION_SUCCESS_MAGIC;
        require(
            msg.sender == BOOTLOADER_FORMAL_ADDRESS,
            "Only bootloader can call this contract"
        );
        require(
            _transaction.paymasterInput.length >= 4,
            "The standard paymaster input must be at least 4 bytes long"
        );

        address user = address(uint160(_transaction.from));
        uint256 currentTier = _userTier[user];

        bool isValid = _validateMembershipTransaction(_transaction);
        require(isValid, "Transaction isn't qualified to use this paymaster");

        // get the total fee needed to complete the transaction
        uint256 requiredETH = _transaction.gasLimit * _transaction.maxFeePerGas;

        // get the tier benefit
        uint256 gasReductionPercentage = benefit(currentTier);

        // calculate gas fee discount
        uint256 gasDiscountAmount = (requiredETH * gasReductionPercentage) /
            100;

        // refund back the discount amount
        (bool refundSuccess, ) = payable(user).call{value: gasDiscountAmount}(
            ""
        );
        require(refundSuccess, "Failed to refund the discount amount");

        // The bootloader never returns any data, so it can safely be ignored here.
        (bool paySuccess, ) = payable(BOOTLOADER_FORMAL_ADDRESS).call{
            value: requiredETH
        }("");
        require(paySuccess, "Failed to transfer funds to the bootloader");
    }

    function postTransaction(
        bytes calldata _context,
        Transaction calldata _transaction,
        bytes32,
        bytes32,
        ExecutionResult _txResult,
        uint256 _maxRefundedGas
    ) external payable override {
        // Refunds are not supported yet.
    }

    receive() external payable {}
}
