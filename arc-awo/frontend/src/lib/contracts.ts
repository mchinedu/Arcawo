import type { Address } from "viem";

const ZERO = "0x0000000000000000000000000000000000000000" as Address;

/** Deployed protocol addresses — set after `forge script` runs (see README). */
export const FACTORY_ADDRESS = (process.env.NEXT_PUBLIC_FACTORY_ADDRESS ?? ZERO) as Address;
export const REPUTATION_ADDRESS = (process.env.NEXT_PUBLIC_REPUTATION_ADDRESS ?? ZERO) as Address;

export const isConfigured = FACTORY_ADDRESS !== ZERO;

/** Deterministic CREATE2 salt binding (creator, userSalt) — mirrors ArcawoFactory. */
export function randomUserSalt(): `0x${string}` {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return `0x${Array.from(bytes).map((b) => b.toString(16).padStart(2, "0")).join("")}` as `0x${string}`;
}

export const ZERO_ADDRESS = ZERO;
