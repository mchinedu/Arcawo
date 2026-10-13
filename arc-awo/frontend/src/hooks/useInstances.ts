"use client";

import { useAccount, useReadContracts } from "wagmi";
import { planAbi, groupAbi } from "@/lib/abis";
import type { Address } from "viem";
import { useRegistry } from "./useRegistry";

export type MyPlanRow = {
  address: Address;
  kind: "plan";
  joined: boolean;
  approved: boolean;
  withdrawn: boolean;
  totalContributed: bigint;
  claimable: bigint;
  contributedPeriods: number;
};

export type MyGroupRow = {
  address: Address;
  kind: "group";
  joined: boolean;
  won: boolean;
  roundsPaid: number;
  paidBitmap: bigint;
};

/**
 * Which of the registered instances the connected wallet has joined — computed
 * via multicall (Multicall3 is a canonical Arc predeploy). For an indexer-backed
 * deployment this becomes a subgraph query; the shape stays the same.
 */
export function useMyInstances() {
  const { address: user } = useAccount();
  const { plans, groups, isLoading } = useRegistry();

  const planContracts = plans.flatMap((p) => [
    { address: p, abi: planAbi, functionName: "memberOf" as const, args: [user!] as const },
    { address: p, abi: planAbi, functionName: "claimableOf" as const, args: [user!] as const },
    { address: p, abi: planAbi, functionName: "isComplete" as const },
    { address: p, abi: planAbi, functionName: "cycleEnd" as const },
    { address: p, abi: planAbi, functionName: "params" as const },
  ]);

  const groupContracts = groups.flatMap((g) => [
    { address: g, abi: groupAbi, functionName: "memberOf" as const, args: [user!] as const },
    { address: g, abi: groupAbi, functionName: "state" as const },
    { address: g, abi: groupAbi, functionName: "currentRound" as const },
    { address: g, abi: groupAbi, functionName: "params" as const },
    { address: g, abi: groupAbi, functionName: "startTime" as const },
    { address: g, abi: groupAbi, functionName: "potOf" as const, args: [0n] as const },
  ]);

  const { data: planData, isLoading: planLoading } = useReadContracts({
    contracts: planContracts,
    query: { enabled: !!user && plans.length > 0 },
  });
  const { data: groupData, isLoading: groupLoading } = useReadContracts({
    contracts: groupContracts,
    query: { enabled: !!user && groups.length > 0 },
  });

  const myPlans: (MyPlanRow & {
    isComplete: boolean;
    cycleEnd: bigint;
    metadataURI: string;
    contributionAmount: bigint;
    frequency: number;
    feeBps: number;
  })[] = [];
  plans.forEach((p, i) => {
    const base = i * 5;
    const member = planData?.[base]?.result as any;
    if (!member || member.joinedAt === 0n) return;
    myPlans.push({
      address: p,
      kind: "plan",
      joined: true,
      approved: member.approved,
      withdrawn: member.withdrawn,
      totalContributed: member.totalContributed,
      claimable: (planData?.[base + 1]?.result as bigint) ?? 0n,
      contributedPeriods: Number(member.contributedPeriods),
      isComplete: (planData?.[base + 2]?.result as boolean) ?? false,
      cycleEnd: (planData?.[base + 3]?.result as bigint) ?? 0n,
      metadataURI: ((planData?.[base + 4]?.result as any)?.[14] as string) ?? "",
      contributionAmount: ((planData?.[base + 4]?.result as any)?.[2] as bigint) ?? 0n,
      frequency: Number(((planData?.[base + 4]?.result as any)?.[3] as number) ?? 1),
      feeBps: Number(((planData?.[base + 4]?.result as any)?.[6] as number) ?? 0),
    });
  });

  const myGroups: (MyGroupRow & {
    state: number;
    currentRound: bigint;
    metadataURI: string;
    contributionAmount: bigint;
    memberCount: number;
    payoutMode: number;
    startTime: bigint;
  })[] = [];
  groups.forEach((g, i) => {
    const base = i * 6;
    const member = groupData?.[base]?.result as any;
    if (!member || !member.joined) return;
    myGroups.push({
      address: g,
      kind: "group",
      joined: true,
      won: member.won,
      roundsPaid: Number(member.roundsPaid),
      paidBitmap: member.paidBitmap,
      state: Number(groupData?.[base + 1]?.result ?? 0),
      currentRound: (groupData?.[base + 2]?.result as bigint) ?? 0n,
      metadataURI: ((groupData?.[base + 3]?.result as any)?.[13] as string) ?? "",
      contributionAmount: ((groupData?.[base + 3]?.result as any)?.[2] as bigint) ?? 0n,
      memberCount: Number(((groupData?.[base + 3]?.result as any)?.[4] as number) ?? 0),
      payoutMode: Number(((groupData?.[base + 3]?.result as any)?.[5] as number) ?? 0),
      startTime: (groupData?.[base + 4]?.result as bigint) ?? 0n,
    });
  });

  return {
    myPlans,
    myGroups,
    isLoading: isLoading || planLoading || groupLoading,
    totalSaved: myPlans.reduce((acc, p) => acc + p.totalContributed, 0n),
    totalClaimable: myPlans.reduce((acc, p) => acc + (p.withdrawn ? 0n : p.claimable), 0n),
  };
}
