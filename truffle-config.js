// In order to load environment variables (e.g. API keys)
require("dotenv").config()

module.exports = {
  networks: {
    ropsten: {
      network_id: 3,
      host: "localhost",
      port: 8543,
    },
    rinkeby: {
      network_id: 4,
      host: "localhost",
      port: 8544,
    },
    goerli: {
      network_id: 5,
      host: "localhost",
      port: 8545,
    },
    kovan: {
      network_id: 42,
      host: "localhost",
      port: 8542,
    },
    "conflux.testnet": {
      host: "localhost",
      port: 3000,
      network_id: 1,
      gasPrice: 10,
      skipDryRun: true,
    },
    "conflux.mainnet": {
      host: "localhost",
      port: 3000,
      network_id: 1029,
      gasPrice: 1,
      skipDryRun: true,
    },
  },
  mocha: {
    reporter: "eth-gas-reporter",
    reporterOptions: {
      coinmarketcap: process.env.COINMARKETCAP_API_KEY,
      currency: "USD",
      gasPrice: 100,
      excludeContracts: ["Migrations"],
      src: "contracts",
    },
    timeout: 100000,
    useColors: true,
  },
  compilers: {
    solc: {
      version: "0.8.6",
      settings: {
        optimizer: {
          enabled: true,
          runs: 200,
        },
      },
    },
  },
  plugins: [
    "truffle-verify",
  ],
  api_keys: {
    etherscan: process.env.ETHERSCAN_API_KEY,
  },
}
