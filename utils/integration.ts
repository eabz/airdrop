import { StandardMerkleTree } from "@openzeppelin/merkle-tree";
import {
	type ContractTransactionReceipt,
	type ContractTransactionResponse,
	HDNodeWallet,
	JsonRpcProvider,
	Mnemonic,
	parseEther,
} from "ethers";
import type { Claim, Vault } from "../types";
import { Claim__factory, Vault__factory } from "../types";

const RPC_URL = "http://127.0.0.1:8545";
const MNEMONIC = "test test test test test test test test test test test junk";

const CONTRIBUTOR_AMOUNT = 100;

async function waitForRpc(url: string, timeoutMs = 15_000) {
	const start = Date.now();

	const provider = new JsonRpcProvider(url, 31337, {
		staticNetwork: true,
		polling: false,
	});

	while (true) {
		try {
			await provider.getBlockNumber();
			return;
		} catch {
			if (Date.now() - start > timeoutMs) {
				throw new Error("Timed out waiting for anvil to be ready");
			}

			await new Promise((r) => setTimeout(r, 250));
		}
	}
}

function deriveWallets(n: number, provider: JsonRpcProvider): HDNodeWallet[] {
	const mnemonic = Mnemonic.fromPhrase(MNEMONIC);

	const wallets: HDNodeWallet[] = [];

	for (let i = 0; i < n; i++) {
		const w = HDNodeWallet.fromMnemonic(
			mnemonic,
			`m/44'/60'/0'/0/${i}`,
		).connect(provider);
		wallets.push(w);
	}

	return wallets;
}

async function main() {
	console.log("==> Starting integration test");

	console.log("==> Starting anvil local node");
	const anvil = Bun.spawn(
		[
			"anvil",
			"--port",
			"8545",
			"--chain-id",
			"31337",
			"--mnemonic",
			String(MNEMONIC),
			"--accounts",
			String(CONTRIBUTOR_AMOUNT + 1),
			"--balance",
			"1000",
			"--silent",
		],
		{
			stdout: "pipe",
			stderr: "pipe",
		},
	);

	const cleanup = async () => {
		try {
			anvil.kill();
		} catch {}
	};

	process.on("SIGINT", cleanup);
	process.on("SIGTERM", cleanup);
	process.on("exit", cleanup);

	console.log("==> Waiting for RPC to be ready");
	await waitForRpc(RPC_URL);

	const provider = new JsonRpcProvider(RPC_URL, undefined, {
		staticNetwork: false,
	});

	console.log("==> Deriving wallets for testing");

	const wallets = deriveWallets(CONTRIBUTOR_AMOUNT + 1, provider);

	const deployer = wallets[0];

	console.log("==> Deployer:", await deployer?.getAddress());

	console.log("==> Loading contract artifacts");

	console.log("==> Deploying Vault");
	const now = Math.floor(Date.now() / 1000);

	const start = BigInt(now - 60);

	const end = BigInt(now + 24 * 60 * 60);

	const vaultFactory = new Vault__factory(deployer);
	const vault: Vault = await vaultFactory.deploy(start, end);
	await vault.waitForDeployment();

	const vaultAddr = await vault.getAddress();
	console.log("==> Vault deployed at:", vaultAddr);

	console.log("==> Start event listener for contributions");

	const contributions: [string, bigint][] = [];

	vault.on(vault.filters.Contributed, (contributor: string, amount: bigint) => {
		contributions.push([contributor, amount]);
	});

	console.log(`==> Sending ${CONTRIBUTOR_AMOUNT} deposits of 5 ETH`);

	const contributionTxs = [];
	const contributorWallets = wallets.slice(1, 1 + CONTRIBUTOR_AMOUNT);

	for (let i = 0; i < contributorWallets.length; i++) {
		const contributor = contributorWallets[i];
		if (contributor) {
			const vaultAsDepositor = vault.connect(contributor);
			contributionTxs.push(
				vaultAsDepositor.contribute({ value: parseEther("5") }),
			);
		}
	}

	await Promise.all(
		contributionTxs.map((p: Promise<ContractTransactionResponse>) =>
			p.then(
				(tx: ContractTransactionResponse) =>
					tx.wait() as Promise<ContractTransactionReceipt>,
			),
		),
	);

	while (contributions.length < CONTRIBUTOR_AMOUNT) {
		console.log("==> Waiting for contribution events.");
		await new Promise((r) => setTimeout(r, 2000));
	}

	console.log(`==> Loaded a total of ${contributions.length} events.`);

	console.log(`==> Creating merkle tree.`);

	const tree = StandardMerkleTree.of(contributions, ["address", "uint256"]);

	console.log(`==> Tree created, Merkle Root: ${tree.root}.`);

	console.log(`==> Deploying Claim.`);

	const claimFactory = new Claim__factory(deployer);
	const claim: Claim = await claimFactory.deploy("Claim Contract", "CLAIM");
	await claim.waitForDeployment();

	const claimAddr = await claim.getAddress();
	console.log("==> Claim deployed at:", claimAddr);

	console.log("==> Setting claim root");

	const nonce = await deployer?.getNonce();
	const setMerkleRootTx = await claim.setClaimMerkle(tree.root, { nonce });
	await setMerkleRootTx.wait();

	console.log("==> Claiming tokens for all accounts");

	const claimTxs = [];
	for (let i = 0; i < contributions.length; i++) {
		const contributor = contributions[i];
		if (contributor) {
			const contributorData: [string, bigint] = [
				contributor[0],
				contributor[1],
			];

			const proof = tree.getProof(contributorData);

			const signerWallet = contributorWallets[i];

			const claimAsUser = claim.connect(signerWallet);

			claimTxs.push(claimAsUser.claim(contributor[0], contributor[1], proof));
		}
	}

	await Promise.all(
		claimTxs.map((p: Promise<ContractTransactionResponse>) =>
			p.then(
				(tx: ContractTransactionResponse) =>
					tx.wait() as Promise<ContractTransactionReceipt>,
			),
		),
	);

	console.log("==> Check balances");
	for (let i = 0; i < contributorWallets.length; i++) {
		const contributor = contributorWallets[i];
		if (contributor) {
			const balance = await claim.balanceOf(contributor);
			if (balance !== parseEther("5")) {
				process.exit("invalid balance");
			}
		}
	}

	console.log("==> Integration flow completed, finishing gracefully");

	process.exit(0);
}

main();
