// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

import {PrepareTierData} from "./Membership.sol";

import "@matterlabs/zksync-contracts/l2/system-contracts/Constants.sol";
import {IContractDeployer} from "@matterlabs/zksync-contracts/l2/system-contracts/interfaces/IContractDeployer.sol";
import {SystemContractsCaller} from "@matterlabs/zksync-contracts/l2/system-contracts/libraries/SystemContractsCaller.sol";

contract MembershipFactory {
    event MembershipCreated(address indexed membershipAddress);

    bytes32 private membershipTemplateBytecodeHash;

    constructor(bytes32 _membershipTemplateBytecodeHash) {
        membershipTemplateBytecodeHash = _membershipTemplateBytecodeHash;
    }

    function createMembershipContract(
        PrepareTierData[] memory _prepareTierData
    ) external returns (address contractAddress) {
        (bool success, bytes memory returnData) = SystemContractsCaller
            .systemCallWithReturndata(
                uint32(gasleft()),
                address(DEPLOYER_SYSTEM_CONTRACT),
                uint128(0),
                abi.encodeCall(
                    DEPLOYER_SYSTEM_CONTRACT.create,
                    (
                        0,
                        membershipTemplateBytecodeHash,
                        abi.encode(_prepareTierData)
                    )
                )
            );

        require(success, "Membership contract deployment failed");

        (contractAddress) = abi.decode(returnData, (address));
        emit MembershipCreated(contractAddress);
    }

    function templateBytecodeHash() public view returns (bytes32) {
        return membershipTemplateBytecodeHash;
    }
}
