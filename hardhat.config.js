require("@nomicfoundation/hardhat-toolbox");
require("hardhat-gas-reporter");
require("solidity-coverage");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.17",
        settings: {
          optimizer: { // Keeps the amount of gas used in check
            enabled: true,
            runs: 10000000
          }
        }
      }
    ],
  },
  gasReporter: {
    enabled: true,
    currency: "USD",
    gasPrice: 100,
  },
  networks: {
    hardhat: {
      chainId: 1337,
      gas: "auto",
      gasPrice: "auto",
      saveDeployments: false,
      mining: {
        auto: false,
        order: 'fifo',
        interval: 1500,
      }
    }
  }
};
