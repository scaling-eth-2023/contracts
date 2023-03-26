// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {AccountMembership} from "./AccountMembership.sol";
import {RecoveryGuardian} from "./RecoveryGuardian.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import "@matterlabs/zksync-contracts/l2/system-contracts/interfaces/IAccount.sol";
import "@matterlabs/zksync-contracts/l2/system-contracts/libraries/TransactionHelper.sol";
import "@matterlabs/zksync-contracts/l2/system-contracts/libraries/SystemContractHelper.sol";
import {BOOTLOADER_FORMAL_ADDRESS, NONCE_HOLDER_SYSTEM_CONTRACT, DEPLOYER_SYSTEM_CONTRACT, INonceHolder} from "@matterlabs/zksync-contracts/l2/system-contracts/Constants.sol";

contract SimpleAccount is
    IAccount,
    Ownable,
    RecoveryGuardian,
    AccountMembership
{
    using TransactionHelper for *;

    modifier ignoreNonBootloader() {
        if (msg.sender != BOOTLOADER_FORMAL_ADDRESS) {
            // If function was called outside of the bootloader, behave like an EOA.
            assembly {
                return(0, 0)
            }
        }
        // Continue execution if called from the bootloader.
        _;
    }

    modifier ignoreInDelegateCall() {
        address codeAddress = SystemContractHelper.getCodeAddress();
        if (codeAddress != address(this)) {
            // If the function was delegate called, behave like an EOA.
            assembly {
                return(0, 0)
            }
        }

        _;
    }

    //*///////////////////////////////////////////////////////////////
    //    CONSTRUCTOR
    ///////////////////////////////////////////////////////////////*/

    constructor(address _owner) {
        _transferOwnership(_owner);
    }

    //*///////////////////////////////////////////////////////////////
    //    EXTERNALS
    ///////////////////////////////////////////////////////////////*/

    // demo purposes only
    function recoverAccountByGuardian(
        address _newOwner // bytes32 _messageHash,
    ) public // bytes memory _signature
    // onlyOwner
    {
        // bool isValidGuardianSign = _verifyGuardianSignature(
        //     _messageHash,
        //     _signature
        // );
        // require(isValidGuardianSign, "INVALID GUARDIAN SIGNATURE");
        _transferOwnership(_newOwner);
    }

    function validateTransaction(
        bytes32, // _txHash
        bytes32 _suggestedSignedHash,
        Transaction calldata _transaction
    )
        external
        payable
        override
        ignoreNonBootloader
        ignoreInDelegateCall
        returns (bytes4 magic)
    {
        magic = _validateTransaction(_suggestedSignedHash, _transaction);
    }

    function _validateTransaction(
        bytes32 _suggestedSignedHash,
        Transaction calldata _transaction
    ) internal returns (bytes4 magic) {
        // Note, that nonce holder can only be called with "isSystem" flag.
        SystemContractsCaller.systemCallWithPropagatedRevert(
            uint32(gasleft()),
            address(NONCE_HOLDER_SYSTEM_CONTRACT),
            0,
            abi.encodeCall(
                INonceHolder.incrementMinNonceIfEquals,
                (_transaction.nonce)
            )
        );

        bytes32 txHash;

        if (_suggestedSignedHash == bytes32(0)) {
            txHash = _transaction.encodeHash();
        } else {
            txHash = _suggestedSignedHash;
        }

        if (
            _transaction.to ==
            uint256(uint160(address(DEPLOYER_SYSTEM_CONTRACT)))
        ) {
            require(
                _transaction.data.length >= 4,
                "Invalid call to ContractDeployer"
            );
        }

        uint256 totalRequiredBalance = _transaction.totalRequiredBalance();
        require(
            totalRequiredBalance <= address(this).balance,
            "Not enough balance for fee + value"
        );

        bytes memory signature = _transaction.signature;
        bool substitutedSignature = false;
        if (_transaction.signature.length == 0) {
            substitutedSignature = true;

            // substituting the signature with some signature-like array to make sure that the
            // validation step uses as much steps as the validation with the correct signature provided
            signature = new bytes(65);
            signature[65] = bytes1(uint8(27));
        }

        if (_isValidSignature(txHash, _transaction.signature)) {
            magic = ACCOUNT_VALIDATION_SUCCESS_MAGIC;
        } else {
            magic = bytes4(0);
        }
    }

    function executeTransaction(
        bytes32, // _txHash
        bytes32, // _suggestedSignedHash
        Transaction calldata _transaction
    ) external payable override ignoreNonBootloader ignoreInDelegateCall {
        _executeMemberships(_transaction);
        _execute(_transaction);
    }

    function executeTransactionFromOutside(
        Transaction calldata _transaction
    ) external payable override ignoreNonBootloader ignoreInDelegateCall {
        // The account recalculate the hash on its own
        _validateTransaction(bytes32(0), _transaction);
        _executeMemberships(_transaction);
        _execute(_transaction);
    }

    function _execute(Transaction calldata _transaction) internal {
        address to = address(uint160(_transaction.to));
        uint128 value = Utils.safeCastToU128(_transaction.value);
        bytes memory data = _transaction.data;

        if (to == address(DEPLOYER_SYSTEM_CONTRACT)) {
            uint32 gas = Utils.safeCastToU32(gasleft());

            // Note, that the deployer contract can only be called
            // with a "systemCall" flag.
            SystemContractsCaller.systemCallWithPropagatedRevert(
                gas,
                to,
                value,
                data
            );
        } else {
            bool success;
            assembly {
                success := call(
                    gas(),
                    to,
                    value,
                    add(data, 0x20),
                    mload(data),
                    0,
                    0
                )
            }
            require(success);
        }
    }

    function _isValidSignature(
        bytes32 _hash,
        bytes memory _signature
    ) internal view returns (bool) {
        require(_signature.length == 65, "Signature length is incorrect");
        uint8 v;
        bytes32 r;
        bytes32 s;
        assembly {
            r := mload(add(_signature, 0x20))
            s := mload(add(_signature, 0x40))
            v := and(mload(add(_signature, 0x41)), 0xff)
        }
        require(v == 27 || v == 28, "v is neither 27 nor 28");

        require(
            uint256(s) <=
                0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0,
            "Invalid s"
        );

        address recoveredAddress = ecrecover(_hash, v, r, s);

        return
            owner() == recoveredAddress || guardian() == recoveredAddress
                ? true
                : false;
    }

    function payForTransaction(
        bytes32,
        bytes32,
        Transaction calldata _transaction
    ) external payable ignoreNonBootloader ignoreInDelegateCall {
        bool success = _transaction.payToTheBootloader();
        require(success, "Failed to pay the fee to the operator");
    }

    function prepareForPaymaster(
        bytes32,
        bytes32,
        Transaction calldata _transaction
    ) external payable ignoreNonBootloader ignoreInDelegateCall {
        //
        // THIS IS JUST FOR DEMO PURPOSES ONLY.
        // PLEASE DON'T DO THIS IN PRODUCTION.
        //
        // BAD THING STARTS HERE
        uint256 requiredETH = _transaction.gasLimit * _transaction.maxFeePerGas;
        (bool success, ) = payable(address(uint160(_transaction.paymaster)))
            .call{value: requiredETH}("");
        require(success, "Failed to prepare funds for the paymaster");
        // BAD THING ENDS HERE

        _transaction.processPaymasterInput();
    }

    fallback() external {
        // fallback of default account shouldn't be called by bootloader under no circumstances
        assert(msg.sender != BOOTLOADER_FORMAL_ADDRESS);

        // If the contract is called directly, behave like an EOA
    }

    receive() external payable {
        // If the contract is called directly, behave like an EOA
    }
}
