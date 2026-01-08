/**
 * Mock ethers.js for testing
 */
const mockProvider = {
  lookupAddress: jest.fn().mockResolvedValue(null),
  estimateGas: jest.fn().mockResolvedValue(BigInt(21000)),
  getFeeData: jest.fn().mockResolvedValue({
    gasPrice: BigInt(20000000000),
    maxFeePerGas: BigInt(25000000000),
  }),
};

const mockSigner = {
  getAddress: jest.fn().mockResolvedValue("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"),
};

const mockContract = {
  createOrder: jest.fn(),
  fillOrder: jest.fn(),
  cancelOrder: jest.fn(),
  getOrder: jest.fn(),
};

class BrowserProvider {
  constructor() {
    return mockProvider;
  }
  getSigner() {
    return Promise.resolve(mockSigner);
  }
}

class Contract {
  constructor() {
    return mockContract;
  }
}

module.exports = {
  BrowserProvider,
  Contract,
  mockProvider,
  mockSigner,
  mockContract,
};
