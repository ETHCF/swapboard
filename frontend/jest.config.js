/**
 * Jest configuration for Swapboard frontend tests
 */
module.exports = {
  testEnvironment: "jsdom",
  testMatch: ["**/*.unit.test.js"],
  collectCoverage: true,
  coverageDirectory: "coverage",
  coverageReporters: ["text", "lcov", "html"],
  // Flat layout: instrument the shipped application scripts, not just the files a
  // test happens to require. Exclusions are the load-bearing part here -- `coverage/`
  // is a generated report full of real .js, and test.js is the Puppeteer e2e runner.
  // See also the eslint --ignore-pattern in package.json.
  collectCoverageFrom: [
    "*.js",
    "!jest.config.js",
    "!stryker.config.js",
    "!test.js",
    "!test.setup.js",
    "!*.unit.test.js",
    "!mock.js",
    "!coverage/**",
    "!__mocks__/**",
  ],
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
