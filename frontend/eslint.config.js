const js = require("@eslint/js");
const globals = require("globals");

module.exports = [
  { ignores: ["coverage/**", ".stryker-tmp/**"] },
  js.configs.recommended,
  {
    files: ["**/*.js"],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "script",
      globals: {
        ...globals.browser,
        ...globals.node,
        ...globals.jest,
        ethers: "readonly",
        SwapboardLib: "readonly",
      },
    },
    rules: {
      "no-unused-vars": ["error", { argsIgnorePattern: "^_", caughtErrors: "none" }],
      // Added to eslint:recommended in v9; off to keep pre-upgrade behaviour.
      "no-useless-assignment": "off",
      "no-console": "off",
      "prefer-const": "error",
      eqeqeq: ["error", "always"],
      curly: ["error", "multi-line"],
      "no-var": "error",
    },
  },
];
