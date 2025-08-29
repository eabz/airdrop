import type { HardhatUserConfig } from "hardhat/config";

const config: HardhatUserConfig = {
  solidity: {
    profiles: {
      default: {
        version: "0.8.30",
      },
    },
  },
  networks: {},
};

export default config;
