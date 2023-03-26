import { expect } from "chai";
import { Wallet, Provider, utils, types, EIP712Signer } from "zksync-web3";
import * as hre from "hardhat";
import { Deployer } from "@matterlabs/hardhat-zksync-toolbox";
import { ethers } from "ethers";
import { setup as accountFactorySetup } from "./factory.test";

import { RICH_WALLET_PK } from "./utils";

async function createAccount() {
	const { factory, eoa, provider, acc } = accountFactorySetup();

	const salt = ethers.constants.HashZero;
	const owner1 = Wallet.createRandom();

	await (
		await eoa.sendTransaction({
			to: factory.address,
			// You can increase the amount of ETH sent to the multisig
			value: ethers.utils.parseEther("1"),
		})
	).wait();

	console.log("Factory has been funded.", await provider.getBalance(factory.address));

	const beforeTxBalance = await eoa.getBalance();

	let deployTx = await factory.populateTransaction.deployWallet(salt, owner1.address);

	const paymasterInterface = new ethers.utils.Interface([
		"function general(bytes data)",
	]);

	const gasLimit = await provider.estimateGas(deployTx);
	const gasPrice = await provider.getGasPrice();

	// Creating transaction that utilizes paymaster feature
	deployTx = {
		...deployTx,
		from: eoa.address,
		gasLimit: gasLimit,
		gasPrice: gasPrice,
		chainId: (await provider.getNetwork()).chainId,
		nonce: await provider.getTransactionCount(eoa.address),
		type: 113,
		customData: {
			gasPerPubdata: utils.DEFAULT_GAS_PER_PUBDATA_LIMIT,
			paymasterParams: {
				paymaster: factory.address,
				paymasterInput: paymasterInterface.encodeFunctionData("general", [[]]),
			},
		} as types.Eip712Meta,
		value: ethers.BigNumber.from(0),
	};

	const sentTx = await eoa.sendTransaction(deployTx);
	await sentTx.wait();

	const afterTxBalance = await eoa.getBalance();
	return {};
}

async function setup() {
	const provider = Provider.getDefaultProvider();
	const owner = new Wallet(RICH_WALLET_PK, provider);
	const deployer = new Deployer(hre, owner);

	const membershipFactoryArtifact = await deployer.loadArtifact("MembershipFactory");
	const membershipArtifact = await deployer.loadArtifact("Membership");

	const membershipFactory = await deployer.deploy(
		membershipFactoryArtifact,
		[utils.hashBytecode(membershipArtifact.bytecode)],
		undefined,
		[
			// Since the factory requires the code of the multisig to be available,
			// we should pass it here as well.
			membershipArtifact.bytecode,
		]
	);

	return {
		owner,
		membershipFactory,
		membershipFactoryArtifact,
	};
}

describe("MembershipFactory", function () {
	it("Should deploy membership contract", async function () {
		const provider = Provider.getDefaultProvider();
		const eoa = new Wallet(RICH_WALLET_PK, provider);
		const deployer = new Deployer(hre, eoa);

		const factoryArtifact = await deployer.loadArtifact("MembershipFactory");
		const membershipArtifact = await deployer.loadArtifact("Membership");

		const factory = await deployer.deploy(
			factoryArtifact,
			[utils.hashBytecode(membershipArtifact.bytecode)],
			undefined,
			[
				// Since the factory requires the code of the multisig to be available,
				// we should pass it here as well.
				membershipArtifact.bytecode,
			]
		);

		const salt = ethers.utils.randomBytes(32);

		const deployTx = await factory.createMembershipContract(salt, [
			[1, 10, 1, 0x12312332, factory.address],
			[2, 15, 2, 0x12312332, factory.address],
		]);
		const receipt = await deployTx.wait();

		const membershipContract = new ethers.Contract(
			receipt.contractAddress,
			membershipArtifact.abi,
			eoa
		);

		await expect(membershipContract.subscribe())
			.to.emit(membershipContract, "UserSubscribe")
			.withArgs(eoa.address);

		const benefit1 = await membershipContract.benefit(1);
		const benefit2 = await membershipContract.benefit(2);
		const tier = await membershipContract.userTier(eoa.address);

		expect(tier).to.equal(1);
		expect(benefit1).to.equal(10);
		expect(benefit2).to.equal(15);

		await expect(membershipContract.unsubscribe())
			.to.emit(membershipContract, "UserUnsubscribe")
			.withArgs(eoa.address, 1);
	});
});

describe("Account Membership", function () {
	it("Should execute membership-valid transaction", async function () {});
});
