import { defineChain, type Chain } from "viem";

/**
 * Arc — Circle's stablecoin-native L1 where USDC is the gas asset.
 *
 * Critical Arc detail (see ../../ARCHITECTURE.md §1): USDC is ONE balance with TWO views —
 * native 18-dec (gas / msg.value) and ERC-20 6-dec at 0x3600…0000. This app displays and
 * transacts in the 6-dec ERC-20 view everywhere (wallet/CCTP/exchange parity).
 */
export const arcMainnet: Chain = defineChain({
  id: 5042,
  name: "Arc",
  nativeCurrency: {
    name: "USDC",
    symbol: "USDC",
    decimals: 18, // native view precision (ERC-20 face is 6 — handled at the app layer)
  },
  rpcUrls: {
    default: { http: [process.env.NEXT_PUBLIC_RPC_URL_MAINNET ?? "https://rpc.mainnet.arc.io"] },
  },
  blockExplorers: {
    default: { name: "Arc Explorer", url: "https://explorer.arc.io" },
  },
  testnet: false,
});

export const arcTestnet: Chain = defineChain({
  id: 5042002,
  name: "Arc Testnet",
  nativeCurrency: {
    name: "USDC",
    symbol: "USDC",
    decimals: 18,
  },
  rpcUrls: {
    default: { http: [process.env.NEXT_PUBLIC_RPC_URL_TESTNET ?? "https://rpc.testnet.arc.io"] },
  },
  blockExplorers: {
    default: { name: "Arcscan", url: "https://testnet.arcscan.app" },
  },
  testnet: true,
});

/** Canonical Arc USDC ERC-20 face (6 decimals). Same address on mainnet & testnet. */
export const ARC_USDC_ADDRESS = "0x3600000000000000000000000000000000000000" as const;

/** 6-dec app units per 1 whole USDC. */
export const USDC_DECIMALS = 6;

export const SUPPORTED_CHAINS = [arcMainnet, arcTestnet] as const;
