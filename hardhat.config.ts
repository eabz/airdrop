import type { HardhatUserConfig } from "hardhat/config";

const config: HardhatUserConfig = {
  plugins: [],
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
