import { describe, it, expect, beforeAll, afterAll } from "vitest";
import {
  createTestClient,
  createPublicClient,
  createWalletClient,
  http,
  parseEther,
  parseUnits,
  formatEther,
  formatUnits,
  getContract,
  type Address,
  type Hex,
} from "viem";
import { foundry } from "viem/chains";
import { spawn, ChildProcess } from "child_process";
import { readFileSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));

const OTCBOARD_ABI = [
  {
    type: "function",
    name: "createOrder",
    inputs: [
      { name: "tokenA", type: "address" },
      { name: "amountA", type: "uint256" },
      { name: "tokenB", type: "address" },
      { name: "amountB", type: "uint256" },
    ],
    outputs: [{ name: "orderId", type: "uint256" }],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "fillOrder",
    inputs: [{ name: "orderId", type: "uint256" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "cancelOrder",
    inputs: [{ name: "orderId", type: "uint256" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "getOrder",
    inputs: [{ name: "orderId", type: "uint256" }],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "maker", type: "address" },
          { name: "tokenA", type: "address" },
          { name: "amountA", type: "uint256" },
          { name: "tokenB", type: "address" },
          { name: "amountB", type: "uint256" },
          { name: "active", type: "bool" },
        ],
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "canFill",
    inputs: [{ name: "orderId", type: "uint256" }],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "nextOrderId",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "event",
    name: "OrderCreated",
    inputs: [
      { name: "orderId", type: "uint256", indexed: true },
      { name: "maker", type: "address", indexed: true },
      { name: "tokenA", type: "address", indexed: false },
      { name: "amountA", type: "uint256", indexed: false },
      { name: "tokenB", type: "address", indexed: false },
      { name: "amountB", type: "uint256", indexed: false },
    ],
  },
  {
    type: "event",
    name: "OrderFilled",
    inputs: [
      { name: "orderId", type: "uint256", indexed: true },
      { name: "taker", type: "address", indexed: true },
    ],
  },
  {
    type: "event",
    name: "OrderCanceled",
    inputs: [{ name: "orderId", type: "uint256", indexed: true }],
  },
] as const;

const ERC20_ABI = [
  {
    type: "function",
    name: "name",
    inputs: [],
    outputs: [{ name: "", type: "string" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "symbol",
    inputs: [],
    outputs: [{ name: "", type: "string" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "decimals",
    inputs: [],
    outputs: [{ name: "", type: "uint8" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "balanceOf",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "approve",
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "mint",
    inputs: [
      { name: "to", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
] as const;

const MOCK_ERC20_BYTECODE = readFileSync(
  join(__dirname, "../contracts/out/MockERC20.sol/MockERC20.json"),
  "utf-8"
).match(/"bytecode":\s*{\s*"object":\s*"([^"]+)"/)?.[1] as Hex;

const OTCBOARD_BYTECODE = readFileSync(
  join(__dirname, "../contracts/out/OTCBoard.sol/OTCBoard.json"),
  "utf-8"
).match(/"bytecode":\s*{\s*"object":\s*"([^"]+)"/)?.[1] as Hex;

const MOCK_ERC20_ABI = JSON.parse(
  readFileSync(join(__dirname, "../contracts/out/MockERC20.sol/MockERC20.json"), "utf-8")
).abi;

let anvil: ChildProcess;
let publicClient: ReturnType<typeof createPublicClient>;
let testClient: ReturnType<typeof createTestClient>;

const TEST_ACCOUNTS = [
  "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
  "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
  "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC",
  "0x90F79bf6EB2c4f870365E785982E1f101E93b906",
] as const;

const TEST_PRIVATE_KEYS = [
  "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
  "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d",
  "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a",
  "0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6",
] as const;

async function startAnvil(): Promise<void> {
  return new Promise((resolve, reject) => {
    anvil = spawn("anvil", ["--port", "8545", "--block-time", "1"], {
      stdio: ["ignore", "pipe", "pipe"],
    });

    let started = false;

    anvil.stdout?.on("data", (data: Buffer) => {
      const output = data.toString();
      if (output.includes("Listening on") && !started) {
        started = true;
        setTimeout(resolve, 500);
      }
    });

    anvil.stderr?.on("data", (data: Buffer) => {
      console.error("Anvil stderr:", data.toString());
    });

    anvil.on("error", reject);

    setTimeout(() => {
      if (!started) {
        reject(new Error("Anvil failed to start within timeout"));
      }
    }, 10000);
  });
}

function stopAnvil(): void {
  if (anvil) {
    anvil.kill("SIGTERM");
  }
}

async function deployContract(
  bytecode: Hex,
  abi: readonly unknown[],
  args: unknown[],
  privateKey: Hex
): Promise<Address> {
  const walletClient = createWalletClient({
    chain: foundry,
    transport: http("http://127.0.0.1:8545"),
    account: privateKey,
  });

  const finalBytecode = bytecode.startsWith("0x") ? bytecode : `0x${bytecode}`;

  const hash = await walletClient.deployContract({
    abi,
    bytecode: finalBytecode as Hex,
    args,
    account: TEST_ACCOUNTS[0],
  });

  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  return receipt.contractAddress!;
}

describe("OTCBoard E2E Tests", () => {
  let boardAddress: Address;
  let tokenAAddress: Address;
  let tokenBAddress: Address;

  beforeAll(async () => {
    await startAnvil();

    publicClient = createPublicClient({
      chain: foundry,
      transport: http("http://127.0.0.1:8545"),
    });

    testClient = createTestClient({
      chain: foundry,
      transport: http("http://127.0.0.1:8545"),
      mode: "anvil",
    });

    const blockNumber = await publicClient.getBlockNumber();
    expect(blockNumber).toBeGreaterThanOrEqual(0n);

    tokenAAddress = await deployContract(
      MOCK_ERC20_BYTECODE,
      MOCK_ERC20_ABI,
      ["Token A", "TKA", 18],
      TEST_PRIVATE_KEYS[0]
    );

    tokenBAddress = await deployContract(
      MOCK_ERC20_BYTECODE,
      MOCK_ERC20_ABI,
      ["Token B", "TKB", 6],
      TEST_PRIVATE_KEYS[0]
    );

    boardAddress = await deployContract(
      OTCBOARD_BYTECODE,
      OTCBOARD_ABI,
      [],
      TEST_PRIVATE_KEYS[0]
    );

    console.log("Deployed contracts:");
    console.log("  TokenA:", tokenAAddress);
    console.log("  TokenB:", tokenBAddress);
    console.log("  OTCBoard:", boardAddress);
  }, 30000);

  afterAll(() => {
    stopAnvil();
  });

  it("should have deployed contracts", async () => {
    expect(boardAddress).toBeDefined();
    expect(tokenAAddress).toBeDefined();
    expect(tokenBAddress).toBeDefined();

    const nextOrderId = await publicClient.readContract({
      address: boardAddress,
      abi: OTCBOARD_ABI,
      functionName: "nextOrderId",
    });

    expect(nextOrderId).toBe(0n);
  });

  it("should create an order", async () => {
    const alice = TEST_ACCOUNTS[0];
    const aliceWallet = createWalletClient({
      chain: foundry,
      transport: http("http://127.0.0.1:8545"),
      account: TEST_PRIVATE_KEYS[0],
    });

    const mintHash = await aliceWallet.writeContract({
      address: tokenAAddress,
      abi: ERC20_ABI,
      functionName: "mint",
      args: [alice, parseEther("1000")],
      account: alice,
    });
    await publicClient.waitForTransactionReceipt({ hash: mintHash });

    const approveHash = await aliceWallet.writeContract({
      address: tokenAAddress,
      abi: ERC20_ABI,
      functionName: "approve",
      args: [boardAddress, parseEther("100")],
      account: alice,
    });
    await publicClient.waitForTransactionReceipt({ hash: approveHash });

    const createHash = await aliceWallet.writeContract({
      address: boardAddress,
      abi: OTCBOARD_ABI,
      functionName: "createOrder",
      args: [tokenAAddress, parseEther("100"), tokenBAddress, parseUnits("300000", 6)],
      account: alice,
    });
    const receipt = await publicClient.waitForTransactionReceipt({ hash: createHash });

    expect(receipt.status).toBe("success");

    const order = await publicClient.readContract({
      address: boardAddress,
      abi: OTCBOARD_ABI,
      functionName: "getOrder",
      args: [0n],
    });

    expect(order.maker.toLowerCase()).toBe(alice.toLowerCase());
    expect(order.amountA).toBe(parseEther("100"));
    expect(order.amountB).toBe(parseUnits("300000", 6));
    expect(order.active).toBe(true);
  });

  it("should fill an order", async () => {
    const bob = TEST_ACCOUNTS[1];
    const alice = TEST_ACCOUNTS[0];
    const bobWallet = createWalletClient({
      chain: foundry,
      transport: http("http://127.0.0.1:8545"),
      account: TEST_PRIVATE_KEYS[1],
    });

    const mintHash = await bobWallet.writeContract({
      address: tokenBAddress,
      abi: ERC20_ABI,
      functionName: "mint",
      args: [bob, parseUnits("1000000", 6)],
      account: bob,
    });
    await publicClient.waitForTransactionReceipt({ hash: mintHash });

    const approveHash = await bobWallet.writeContract({
      address: tokenBAddress,
      abi: ERC20_ABI,
      functionName: "approve",
      args: [boardAddress, parseUnits("300000", 6)],
      account: bob,
    });
    await publicClient.waitForTransactionReceipt({ hash: approveHash });

    const bobTokenABefore = await publicClient.readContract({
      address: tokenAAddress,
      abi: ERC20_ABI,
      functionName: "balanceOf",
      args: [bob],
    });

    const fillHash = await bobWallet.writeContract({
      address: boardAddress,
      abi: OTCBOARD_ABI,
      functionName: "fillOrder",
      args: [0n],
      account: bob,
    });
    const receipt = await publicClient.waitForTransactionReceipt({ hash: fillHash });

    expect(receipt.status).toBe("success");

    const order = await publicClient.readContract({
      address: boardAddress,
      abi: OTCBOARD_ABI,
      functionName: "getOrder",
      args: [0n],
    });

    expect(order.active).toBe(false);

    const bobTokenAAfter = await publicClient.readContract({
      address: tokenAAddress,
      abi: ERC20_ABI,
      functionName: "balanceOf",
      args: [bob],
    });

    expect(bobTokenAAfter - bobTokenABefore).toBe(parseEther("100"));

    const aliceTokenB = await publicClient.readContract({
      address: tokenBAddress,
      abi: ERC20_ABI,
      functionName: "balanceOf",
      args: [alice],
    });

    expect(aliceTokenB).toBe(parseUnits("300000", 6));
  });

  it("should cancel an order", async () => {
    const alice = TEST_ACCOUNTS[0];
    const aliceWallet = createWalletClient({
      chain: foundry,
      transport: http("http://127.0.0.1:8545"),
      account: TEST_PRIVATE_KEYS[0],
    });

    const approveHash = await aliceWallet.writeContract({
      address: tokenAAddress,
      abi: ERC20_ABI,
      functionName: "approve",
      args: [boardAddress, parseEther("50")],
      account: alice,
    });
    await publicClient.waitForTransactionReceipt({ hash: approveHash });

    const createHash = await aliceWallet.writeContract({
      address: boardAddress,
      abi: OTCBOARD_ABI,
      functionName: "createOrder",
      args: [tokenAAddress, parseEther("50"), tokenBAddress, parseUnits("150000", 6)],
      account: alice,
    });
    await publicClient.waitForTransactionReceipt({ hash: createHash });

    const orderId = 1n;

    const balanceBefore = await publicClient.readContract({
      address: tokenAAddress,
      abi: ERC20_ABI,
      functionName: "balanceOf",
      args: [alice],
    });

    const cancelHash = await aliceWallet.writeContract({
      address: boardAddress,
      abi: OTCBOARD_ABI,
      functionName: "cancelOrder",
      args: [orderId],
      account: alice,
    });
    const receipt = await publicClient.waitForTransactionReceipt({ hash: cancelHash });

    expect(receipt.status).toBe("success");

    const order = await publicClient.readContract({
      address: boardAddress,
      abi: OTCBOARD_ABI,
      functionName: "getOrder",
      args: [orderId],
    });

    expect(order.active).toBe(false);

    const balanceAfter = await publicClient.readContract({
      address: tokenAAddress,
      abi: ERC20_ABI,
      functionName: "balanceOf",
      args: [alice],
    });

    expect(balanceAfter - balanceBefore).toBe(parseEther("50"));
  });

  it("should prevent filling an already filled order", async () => {
    const charlie = TEST_ACCOUNTS[2];
    const charlieWallet = createWalletClient({
      chain: foundry,
      transport: http("http://127.0.0.1:8545"),
      account: TEST_PRIVATE_KEYS[2],
    });

    const mintHash = await charlieWallet.writeContract({
      address: tokenBAddress,
      abi: ERC20_ABI,
      functionName: "mint",
      args: [charlie, parseUnits("1000000", 6)],
      account: charlie,
    });
    await publicClient.waitForTransactionReceipt({ hash: mintHash });

    const approveHash = await charlieWallet.writeContract({
      address: tokenBAddress,
      abi: ERC20_ABI,
      functionName: "approve",
      args: [boardAddress, parseUnits("300000", 6)],
      account: charlie,
    });
    await publicClient.waitForTransactionReceipt({ hash: approveHash });

    const fillHash = await charlieWallet.writeContract({
      address: boardAddress,
      abi: OTCBOARD_ABI,
      functionName: "fillOrder",
      args: [0n],
      account: charlie,
    });
    const receipt = await publicClient.waitForTransactionReceipt({ hash: fillHash });

    expect(receipt.status).toBe("reverted");
  });

  it("should prevent non-maker from canceling", async () => {
    const alice = TEST_ACCOUNTS[0];
    const bob = TEST_ACCOUNTS[1];
    const aliceWallet = createWalletClient({
      chain: foundry,
      transport: http("http://127.0.0.1:8545"),
      account: TEST_PRIVATE_KEYS[0],
    });
    const bobWallet = createWalletClient({
      chain: foundry,
      transport: http("http://127.0.0.1:8545"),
      account: TEST_PRIVATE_KEYS[1],
    });

    const approveHash = await aliceWallet.writeContract({
      address: tokenAAddress,
      abi: ERC20_ABI,
      functionName: "approve",
      args: [boardAddress, parseEther("10")],
      account: alice,
    });
    await publicClient.waitForTransactionReceipt({ hash: approveHash });

    const createHash = await aliceWallet.writeContract({
      address: boardAddress,
      abi: OTCBOARD_ABI,
      functionName: "createOrder",
      args: [tokenAAddress, parseEther("10"), tokenBAddress, parseUnits("30000", 6)],
      account: alice,
    });
    await publicClient.waitForTransactionReceipt({ hash: createHash });

    const nextOrderId = await publicClient.readContract({
      address: boardAddress,
      abi: OTCBOARD_ABI,
      functionName: "nextOrderId",
    });

    const orderId = nextOrderId - 1n;

    const cancelHash = await bobWallet.writeContract({
      address: boardAddress,
      abi: OTCBOARD_ABI,
      functionName: "cancelOrder",
      args: [orderId],
      account: bob,
    });
    const receipt = await publicClient.waitForTransactionReceipt({ hash: cancelHash });

    expect(receipt.status).toBe("reverted");
  });

  it("should handle multiple concurrent orders", async () => {
    const alice = TEST_ACCOUNTS[0];
    const bob = TEST_ACCOUNTS[1];
    const aliceWallet = createWalletClient({
      chain: foundry,
      transport: http("http://127.0.0.1:8545"),
      account: TEST_PRIVATE_KEYS[0],
    });
    const bobWallet = createWalletClient({
      chain: foundry,
      transport: http("http://127.0.0.1:8545"),
      account: TEST_PRIVATE_KEYS[1],
    });

    const approveHash = await aliceWallet.writeContract({
      address: tokenAAddress,
      abi: ERC20_ABI,
      functionName: "approve",
      args: [boardAddress, parseEther("300")],
      account: alice,
    });
    await publicClient.waitForTransactionReceipt({ hash: approveHash });

    const orderIds: bigint[] = [];
    for (let i = 0; i < 3; i++) {
      const hash = await aliceWallet.writeContract({
        address: boardAddress,
        abi: OTCBOARD_ABI,
        functionName: "createOrder",
        args: [tokenAAddress, parseEther("100"), tokenBAddress, parseUnits("300000", 6)],
        account: alice,
      });
      await publicClient.waitForTransactionReceipt({ hash });

      const nextId = await publicClient.readContract({
        address: boardAddress,
        abi: OTCBOARD_ABI,
        functionName: "nextOrderId",
      });
      orderIds.push(nextId - 1n);
    }

    expect(orderIds.length).toBe(3);

    for (const orderId of orderIds) {
      const canFill = await publicClient.readContract({
        address: boardAddress,
        abi: OTCBOARD_ABI,
        functionName: "canFill",
        args: [orderId],
      });
      expect(canFill).toBe(true);
    }

    const approveBobHash = await bobWallet.writeContract({
      address: tokenBAddress,
      abi: ERC20_ABI,
      functionName: "approve",
      args: [boardAddress, parseUnits("900000", 6)],
      account: bob,
    });
    await publicClient.waitForTransactionReceipt({ hash: approveBobHash });

    const fillHash = await bobWallet.writeContract({
      address: boardAddress,
      abi: OTCBOARD_ABI,
      functionName: "fillOrder",
      args: [orderIds[1]],
      account: bob,
    });
    await publicClient.waitForTransactionReceipt({ hash: fillHash });

    const cancelHash = await aliceWallet.writeContract({
      address: boardAddress,
      abi: OTCBOARD_ABI,
      functionName: "cancelOrder",
      args: [orderIds[0]],
      account: alice,
    });
    await publicClient.waitForTransactionReceipt({ hash: cancelHash });

    expect(
      await publicClient.readContract({
        address: boardAddress,
        abi: OTCBOARD_ABI,
        functionName: "canFill",
        args: [orderIds[0]],
      })
    ).toBe(false);

    expect(
      await publicClient.readContract({
        address: boardAddress,
        abi: OTCBOARD_ABI,
        functionName: "canFill",
        args: [orderIds[1]],
      })
    ).toBe(false);

    expect(
      await publicClient.readContract({
        address: boardAddress,
        abi: OTCBOARD_ABI,
        functionName: "canFill",
        args: [orderIds[2]],
      })
    ).toBe(true);
  });
});
