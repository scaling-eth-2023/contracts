// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

/// @title Guardian is a entity that has the ability to set a new owner for the account.
/// @notice Guardian will be able to help in account recovery in the case that the private
/// key of the current owner is lost.
abstract contract RecoveryGuardian {
    address private guardian;

    function setRecoveryGuardian(address _guardian) external {
        guardian = _guardian;
    }

    function isGuardian(address _guardian) external view returns (bool) {
        return guardian == _guardian ? true : false;
    }

    /// @param _messageHash keccak( address(this) )
    /// @param _signature sign( _messageHash )
    function _verifyGuardianSignature(
        bytes32 _messageHash,
        bytes memory _signature
    ) internal returns (bool) {
        (bytes32 r, bytes32 s, uint8 v) = _splitSignature(_signature);
        address recoveredAddress = ecrecover(_messageHash, v, r, s);
        return recoveredAddress == guardian ? true : false;
    }

    function _splitSignature(
        bytes memory _signature
    ) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(_signature.length == 65, "INVALID SIGNATURE LENGTH");

        assembly {
            /*
            First 32 bytes stores the length of the signature

            add(sig, 32) = pointer of sig + 32
            effectively, skips first 32 bytes of signature

            mload(p) loads next 32 bytes starting at the memory address p into memory
            */

            // first 32 bytes, after the length prefix
            r := mload(add(_signature, 32))
            // second 32 bytes
            s := mload(add(_signature, 64))
            // final byte (first byte of the next 32 bytes)
            v := byte(0, mload(add(_signature, 96)))
        }
    }
}
