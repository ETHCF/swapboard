/**
 * Jest configuration for Swapboard frontend tests
 */
module.exports = {
  testEnvironment: "jsdom",
  testMatch: ["**/*.unit.test.js"],
  collectCoverage: true,
  coverageDirectory: "coverage",
  coverageReporters: ["text", "lcov", "html"],
  coverageThreshold: {
    global: {
      branches: 89,
      functions: 100,
      lines: 98,
      statements: 97,
    },
  },
  setupFilesAfterEnv: ["<rootDir>/test.setup.js"],
  moduleNameMapper: {
    "^ethers$": "<rootDir>/__mocks__/ethers.js",
  },
  verbose: true,
};
