/* eslint-disable no-console */

import * as fs from "node:fs/promises";
import * as path from "node:path";
import { $ } from "bun";
import {
	AbiCoder,
	type Contract,
	ContractFactory,
	HDNodeWallet,
	JsonRpcProvider,
	keccak256,
	Mnemonic,
	toUtf8Bytes,
} from "ethers";

/**
 * CONFIG
 */
const RPC_URL = "http://127.0.0.1:8545";
const CHAIN_ID = 31337;
const ANVIL_ACCOUNTS = 110; // enough to fund first 100 depositors + deployer, etc.
const ANVIL_BALANCE = "1000000000000000000000"; // 1000 ETH (in wei) for each test account
const MNEMONIC = "test test test test test test test test test test test junk"; // deterministic, do not use in prod

// Deposit settings
const NUM_DEPOSITORS = 100;
const DEPOSIT_WEI = 100000000000000000n; // 0.1 ETH per depositor

// Contract artifacts (Foundry default output paths)
const OUT_DIR = path.resolve(process.cwd(), "out");
const VAULT_ARTIFACT = path.join(OUT_DIR, "Vault.sol", "Vault.json");
const CLAIM_ARTIFACT = path.join(OUT_DIR, "Claim.sol", "Claim.json");

// Claim constructor args (adjust to your Claim.sol constructor)
const CLAIM_NAME = "Airdrop";
const CLAIM_SYMBOL = "AIR";

/**
 * Helper: read ABI/bytecode from Foundry artifact
 */
async function loadArtifact(artifactPath: string): Promise<{
	abi: any[];
	bytecode: string;
}> {
	const raw = await fs.readFile(artifactPath, "utf8");
	const json = JSON.parse(raw);
	const abi = json.abi;
	// Foundry places bytecode at .bytecode.object
	const bytecode =
		json.bytecode?.object ??
		json.deployedBytecode?.object ??
		json.bytecode ??
		(() => {
			throw new Error(`Bytecode not found in ${artifactPath}`);
		})();
	return { abi, bytecode };
}

/**
 * Helper: wait until RPC is ready
 */
async function waitForRpc(url: string, timeoutMs = 15_000) {
	const start = Date.now();

	const provider = new JsonRpcProvider(url, undefined, {
		staticNetwork: false,
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

/**
 * Helper: derive an array of funded wallets from the mnemonic
 */
function deriveWallets(n: number, provider: JsonRpcProvider): HDNodeWallet[] {
	const m = Mnemonic.fromPhrase(MNEMONIC);
	const wallets: HDNodeWallet[] = [];
	for (let i = 0; i < n; i++) {
		const w = HDNodeWallet.fromMnemonic(m, `m/44'/60'/0'/0/${i}`).connect(
			provider,
		);
		wallets.push(w);
	}
	return wallets;
}

/**
 * Merkle tree helpers (sorted pair hashing)
 */

const coder = AbiCoder.defaultAbiCoder();

function leafHash(index: bigint, account: string, amount: bigint): string {
	const encoded = coder.encode(
		["uint256", "address", "uint256"],
		[index, account, amount],
	);
	return keccak256(encoded);
}

function hashPairSafe(a: string, b: string): string {
	// emulate: keccak256(abi.encodePacked(min(a,b), max(a,b)))
	const [x, y] = a.toLowerCase() < b.toLowerCase() ? [a, b] : [b, a];
	const packed = new Uint8Array([...hexToBytes(x), ...hexToBytes(y)]);
	return keccak256(packed);
}

function hexToBytes(hex: string): Uint8Array {
	if (hex.startsWith("0x")) hex = hex.slice(2);
	if (hex.length % 2 !== 0) hex = "0" + hex;
	const len = hex.length / 2;
	const out = new Uint8Array(len);
	for (let i = 0; i < len; i++) {
		out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
	}
	return out;
}

type Proof = string[];

function buildMerkle(leaves: string[]): {
	root: string;
	layers: string[][];
	proofs: Proof[];
} {
	if (leaves.length === 0) {
		return { root: keccak256("0x"), layers: [], proofs: [] };
	}

	const layers: string[][] = [];
	layers.push(leaves);

	while (layers[layers.length - 1].length > 1) {
		const prev = layers[layers.length - 1];
		const next: string[] = [];
		for (let i = 0; i < prev.length; i += 2) {
			const left = prev[i];
			const right = i + 1 < prev.length ? prev[i + 1] : prev[i];
			next.push(hashPairSafe(left, right));
		}
		layers.push(next);
	}

	const root = layers[layers.length - 1][0];

	// proofs
	const proofs: Proof[] = leaves.map((_, leafIdx) => {
		const proof: string[] = [];
		let idx = leafIdx;
		for (let layerIdx = 0; layerIdx < layers.length - 1; layerIdx++) {
			const layer = layers[layerIdx];
			const pairIdx = idx ^ 1;
			const sibling = pairIdx < layer.length ? layer[pairIdx] : layer[idx];
			proof.push(sibling);
			idx = Math.floor(idx / 2);
		}
		return proof;
	});

	return { root, layers, proofs };
}

/**
 * Run the full integration
 */
async function main() {
	console.log("==> Building contracts with forge");
	await $`forge build`;

	console.log("==> Starting anvil local node");
	const anvil = Bun.spawn(
		[
			"anvil",
			"--port",
			"8545",
			"--chain-id",
			String(CHAIN_ID),
			"--mnemonic",
			MNEMONIC,
			"--accounts",
			String(ANVIL_ACCOUNTS),
			"--balance",
			ANVIL_BALANCE,
			// Uncomment for logging
			// "--silent"
		],
		{
			stdout: "pipe",
			stderr: "pipe",
		},
	);

	// Ensure we clean up anvil on exit
	const cleanup = async () => {
		try {
			anvil.kill();
		} catch {}
	};

	process.on("SIGINT", cleanup);
	process.on("SIGTERM", cleanup);
	process.on("exit", cleanup);

	console.log("==> Waiting for RPC to be ready…");
	await waitForRpc(RPC_URL);

	const provider = new JsonRpcProvider(RPC_URL, undefined, {
		staticNetwork: false,
	});

	// Derive wallets (0 = deployer/owner; 1..100 = depositors)
	const wallets = deriveWallets(NUM_DEPOSITORS + 5, provider);
	const deployer = wallets[0];

	console.log("Deployer:", await deployer.getAddress());

	// Load artifacts
	const { abi: vaultAbi, bytecode: vaultBytecode } =
		await loadArtifact(VAULT_ARTIFACT);
	const { abi: claimAbi, bytecode: claimBytecode } =
		await loadArtifact(CLAIM_ARTIFACT);

	// Deploy Vault
	console.log("==> Deploying Vault");
	const now = Math.floor(Date.now() / 1000);
	const start = BigInt(now - 60);
	const end = BigInt(now + 24 * 60 * 60);
	const vaultFactory = new ContractFactory(vaultAbi, vaultBytecode, deployer);
	const vault = (await vaultFactory.deploy(start, end)) as Contract;
	await vault.waitForDeployment();
	const vaultAddr = await vault.getAddress();
	console.log("Vault deployed at:", vaultAddr);

	// Event listener for Contributed
	type Contribution = { contributor: string; amount: bigint };
	const contributions: Contribution[] = [];
	vault.on("Contributed", (contributor: string, amount: bigint) => {
		contributions.push({ contributor, amount });
		// console.log("Contributed:", contributor, amount.toString());
	});

	// Make 100 deposits
	console.log(`==> Sending ${NUM_DEPOSITORS} deposits of ${DEPOSIT_WEI} wei`);
	const depositorWallets = wallets.slice(1, 1 + NUM_DEPOSITORS);

	const depositTxs = [];
	for (let i = 0; i < depositorWallets.length; i++) {
		const w = depositorWallets[i];
		const vaultAsDepositor = vault.connect(w);
		// call contribute() with value
		depositTxs.push(vaultAsDepositor.contribute({ value: DEPOSIT_WEI }));
	}
	await Promise.all(depositTxs.map((p) => p.then((tx: any) => tx.wait())));

	// Small wait to ensure all events delivered
	await new Promise((r) => setTimeout(r, 500));

	console.log("Total contribution events received:", contributions.length);

	// Build distribution from events (index in order of receipt)
	const indexed = contributions.map((c, i) => ({
		index: BigInt(i),
		account: c.contributor,
		amount: c.amount,
	}));

	// Build Merkle tree (leaves = keccak256(abi.encode(index, account, amount)))
	const leaves = indexed.map((e) => leafHash(e.index, e.account, e.amount));
	const { root, proofs } = buildMerkle(leaves);
	console.log("Merkle root:", root);

	// Deploy Claim
	console.log("==> Deploying Claim");
	const claimFactory = new ContractFactory(claimAbi, claimBytecode, deployer);
	// Adjust if your Claim constructor differs
	const claim = (await claimFactory.deploy(
		CLAIM_NAME,
		CLAIM_SYMBOL,
		await deployer.getAddress(),
	)) as Contract;
	await claim.waitForDeployment();
	const claimAddr = await claim.getAddress();
	console.log("Claim deployed at:", claimAddr);

	// Set Merkle root (owner or timelock)
	console.log("==> Setting claim Merkle root");
	const setTx = await claim.setClaimMerkle(root);
	await setTx.wait();

	// Execute claims from each depositor
	console.log("==> Claiming for each account…");
	const claimTxs = [];
	for (let i = 0; i < indexed.length; i++) {
		const { index, account, amount } = indexed[i];
		const proof = proofs[i];

		// signer must be the account itself
		let signerWallet = depositorWallets[i];
		for (const w of depositorWallets) {
			if ((await w.getAddress()).toLowerCase() === account.toLowerCase()) {
				signerWallet = w;
				break;
			}
		}

		const claimAsUser = claim.connect(signerWallet);
		claimTxs.push(claimAsUser.claim(index, account, amount, proof));
	}
	await Promise.all(claimTxs.map((p) => p.then((tx: any) => tx.wait())));

	console.log("✅ Integration flow completed.");
	console.log(`Vault: ${vaultAddr}`);
	console.log(`Claim: ${claimAddr}`);

	// Optional: verify a couple of balances
	const bal0 = await claim.balanceOf(await depositorWallets[0].getAddress());
	const bal99 = await claim.balanceOf(await depositorWallets[99].getAddress());
	console.log("Sample balances:", bal0.toString(), bal99.toString());

	// Stop anvil when done
	await cleanup();
}

/**
 * Entry
 */
main().catch(async (err) => {
	console.error("Integration failed:", err);
	process.exitCode = 1;
});
