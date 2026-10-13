"use client";

import { useReadContract, useReadContracts } from "wagmi";
import { factoryAbi, planAbi, groupAbi } from "@/lib/abis";
import { FACTORY_ADDRESS, isConfigured } from "@/lib/contracts";
import type { Address } from "viem";

const PAGE = 50n;

/** All plan/group addresses registered in the factory. */
export function useRegistry() {
  const enabled = isConfigured;

  const { data: counts } = useReadContracts({
    allowFailure: true,
    contracts: [
      { address: FACTORY_ADDRESS, abi: factoryAbi, functionName: "planCount" },
      { address: FACTORY_ADDRESS, abi: factoryAbi, functionName: "groupCount" },
    ],
    query: { enabled },
  });

  const planCount = (counts?.[0]?.result as bigint | undefined) ?? 0n;
  const groupCount = (counts?.[1]?.result as bigint | undefined) ?? 0n;

  const planPages = Math.max(1, Math.ceil(Number(planCount) / Number(PAGE)));
  const groupPages = Math.max(1, Math.ceil(Number(groupCount) / Number(PAGE)));

  const planQueries = Array.from({ length: planPages }, (_, i) => ({
    address: FACTORY_ADDRESS,
    abi: factoryAbi,
    functionName: "plans" as const,
    args: [BigInt(i) * PAGE, PAGE] as const,
  }));
  const groupQueries = Array.from({ length: groupPages }, (_, i) => ({
    address: FACTORY_ADDRESS,
    abi: factoryAbi,
    functionName: "groups" as const,
    args: [BigInt(i) * PAGE, PAGE] as const,
  }));

  const { data: planPagesData, isLoading: plansLoading } = useReadContracts({
    contracts: planQueries,
    query: { enabled: enabled && planCount > 0n },
  });
  const { data: groupPagesData, isLoading: groupsLoading } = useReadContracts({
    contracts: groupQueries,
    query: { enabled: enabled && groupCount > 0n },
  });

  const plans: Address[] = (planPagesData ?? [])
    .flatMap((r) => (r.status === "success" ? (r.result as Address[]) : []))
    .slice()
    .reverse(); // newest first
  const groups: Address[] = (groupPagesData ?? [])
    .flatMap((r) => (r.status === "success" ? (r.result as Address[]) : []))
    .slice()
    .reverse();

  return {
    plans,
    groups,
    planCount,
    groupCount,
    isLoading: plansLoading || groupsLoading,
    enabled,
  };
}

export type PlanParams = {
  collector: Address;
  guardian: Address;
  contributionAmount: bigint;
  frequency: number;
  startTime: bigint;
  durationPeriods: number;
  feeBps: number;
  earlyWithdrawPenaltyBps: number;
  protocolFeeBps: number;
  referralShareBps: number;
  treasury: Address;
  reputation: Address;
  approvalRequired: boolean;
  maxMembers: number;
  metadataURI: string;
};

export type GroupParams = {
  collector: Address;
  guardian: Address;
  contributionAmount: bigint;
  frequency: number;
  memberCount: number;
  payoutMode: number;
  feeBps: number;
  lateFeeBps: number;
  protocolFeeBps: number;
  startDelay: bigint;
  treasury: Address;
  reputation: Address;
  collectorPlays: boolean;
  metadataURI: string;
};

export function usePlanSummary(address?: Address) {
  return useReadContract({
    address,
    abi: planAbi,
    functionName: "params",
    query: { enabled: !!address },
  });
}

export function useGroupSummary(address?: Address) {
  return useReadContract({
    address,
    abi: groupAbi,
    functionName: "params",
    query: { enabled: !!address },
  });
}
