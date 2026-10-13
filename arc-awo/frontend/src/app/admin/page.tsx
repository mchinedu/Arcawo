"use client";

import { useAccount, useReadContracts, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { toast } from "sonner";
import { BadgeCheck, Coins, Loader2, PauseCircle, ShieldCheck, UserCheck, XCircle } from "lucide-react";
import Link from "next/link";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { planAbi, groupAbi, reputationAbi } from "@/lib/abis";
import { REPUTATION_ADDRESS } from "@/lib/contracts";
import { useRegistry } from "@/hooks/useRegistry";
import { formatUsdc, shortAddress, FREQUENCY_LABELS } from "@/lib/format";
import type { Address } from "viem";

export default function AdminPage() {
  const { address } = useAccount();
  const { plans, groups, isLoading } = useRegistry();

  const { writeContract, data: hash, isPending } = useWriteContract();
  const { isLoading: txPending } = useWaitForTransactionReceipt({ hash });
  const busy = isPending || txPending;

  // Plans where the connected wallet is the collector.
  const planContracts = plans.map((p) => ({ address: p, abi: planAbi, functionName: "params" as const }));
  const groupContracts = groups.map((g) => ({ address: g, abi: groupAbi, functionName: "params" as const }));

  const { data: planData } = useReadContracts({ contracts: planContracts, query: { enabled: plans.length > 0 && !!address } });
  const { data: groupData } = useReadContracts({ contracts: groupContracts, query: { enabled: groups.length > 0 && !!address } });

  const myPlans = plans.filter((p, i) => ((planData?.[i]?.result as any)?.[0] as string | undefined)?.toLowerCase() === address?.toLowerCase());
  const myGroups = groups.filter((g, i) => ((groupData?.[i]?.result as any)?.[0] as string | undefined)?.toLowerCase() === address?.toLowerCase());

  const myPlanDetails = myPlans.map((p) => {
    const idx = plans.indexOf(p);
    const t = planData?.[idx]?.result as any;
    return {
      address: p,
      metadataURI: (t?.[14] as string) ?? "",
      contributionAmount: (t?.[2] as bigint) ?? 0n,
      frequency: Number(t?.[3] ?? 1),
    };
  });
  const myGroupDetails = myGroups.map((g) => {
    const idx = groups.indexOf(g);
    const t = groupData?.[idx]?.result as any;
    return {
      address: g,
      metadataURI: (t?.[13] as string) ?? "",
      contributionAmount: (t?.[2] as bigint) ?? 0n,
      memberCount: Number(t?.[4] ?? 0),
    };
  });

  const { data: fees } = useReadContracts({
    contracts: myPlanDetails.map((p) => ({ address: p.address, abi: planAbi, functionName: "accruedCollectorFees" as const })),
    query: { enabled: myPlanDetails.length > 0 },
  });
  const { data: groupFees } = useReadContracts({
    contracts: myGroupDetails.map((g) => ({ address: g.address, abi: groupAbi, functionName: "accruedCollectorFees" as const })),
    query: { enabled: myGroupDetails.length > 0 },
  });

  const { data: score } = useReadContracts({
    contracts: [
      { address: REPUTATION_ADDRESS, abi: reputationAbi, functionName: "score", args: [address!] as const },
    ],
    query: { enabled: !!address },
  });

  const write = (addr: Address, abi: any, functionName: string, args: unknown[] = []) =>
    writeContract(
      { address: addr, abi, functionName: functionName as any, args: args as any },
      { onSuccess: () => toast.success("Transaction sent"), onError: (e) => toast.error(e.message.slice(0, 120)) }
    );

  return (
    <div className="container py-10">
      <div className="flex flex-col justify-between gap-4 sm:flex-row sm:items-center">
        <div>
          <h1 className="text-2xl font-bold tracking-tight sm:text-3xl">Collector panel</h1>
          <p className="mt-1 text-muted-foreground">
            Manage the plans and groups you host. Reputation score:{" "}
            <Badge variant="gold">
              <BadgeCheck className="mr-1 h-3 w-3" />
              {score?.[0]?.result !== undefined ? `${(score[0].result as bigint).toString()} / 1000` : "—"}
            </Badge>
          </p>
        </div>
        <Button asChild>
          <Link href="/create">Host something new</Link>
        </Button>
      </div>

      {isLoading ? (
        <div className="mt-8 grid gap-4">
          <Skeleton className="h-40" />
          <Skeleton className="h-40" />
        </div>
      ) : myPlans.length === 0 && myGroups.length === 0 ? (
        <Card className="mt-8">
          <CardContent className="py-16 text-center text-muted-foreground">
            You are not hosting any thrift yet.{" "}
            <Link href="/create" className="font-medium text-primary hover:underline">
              Create your first plan →
            </Link>
          </CardContent>
        </Card>
      ) : (
        <>
          {myPlanDetails.length > 0 && (
            <>
              <h2 className="mt-8 text-lg font-semibold">Your plans</h2>
              <div className="mt-4 grid gap-4">
                {myPlanDetails.map((p, i) => (
                  <Card key={p.address}>
                    <CardHeader className="pb-3">
                      <div className="flex flex-col justify-between gap-2 sm:flex-row sm:items-center">
                        <div>
                          <CardTitle className="text-base">{p.metadataURI || "Savings plan"}</CardTitle>
                          <CardDescription>
                            {shortAddress(p.address)} · {formatUsdc(p.contributionAmount)}{" "}
                            {FREQUENCY_LABELS[p.frequency]?.toLowerCase()}
                          </CardDescription>
                        </div>
                        <div className="flex flex-wrap gap-2">
                          <Button size="sm" variant="outline" onClick={() => write(p.address, planAbi, "approveMember", ["0x0000000000000000000000000000000000000000"])} disabled={busy}>
                            <UserCheck className="h-4 w-4" /> Approve member…
                          </Button>
                          <Button size="sm" variant="secondary" onClick={() => write(p.address, planAbi, "claimFees")} disabled={busy}>
                            <Coins className="h-4 w-4" />
                            Claim fees ({formatUsdc((fees?.[i]?.result as bigint) ?? 0n)})
                          </Button>
                          <Button size="sm" variant="destructive" onClick={() => write(p.address, planAbi, "endPlan")} disabled={busy}>
                            <XCircle className="h-4 w-4" /> End plan
                          </Button>
                        </div>
                      </div>
                    </CardHeader>
                  </Card>
                ))}
              </div>
            </>
          )}

          {myGroupDetails.length > 0 && (
            <>
              <h2 className="mt-8 text-lg font-semibold">Your groups</h2>
              <div className="mt-4 grid gap-4">
                {myGroupDetails.map((g, i) => (
                  <Card key={g.address}>
                    <CardHeader className="pb-3">
                      <div className="flex flex-col justify-between gap-2 sm:flex-row sm:items-center">
                        <div>
                          <CardTitle className="text-base">{g.metadataURI || "Isusu group"}</CardTitle>
                          <CardDescription>
                            {shortAddress(g.address)} · {g.memberCount} members ·{" "}
                            {formatUsdc(g.contributionAmount)} stake
                          </CardDescription>
                        </div>
                        <div className="flex flex-wrap gap-2">
                          <Button size="sm" variant="secondary" onClick={() => write(g.address, groupAbi, "claimFees")} disabled={busy}>
                            <Coins className="h-4 w-4" />
                            Claim fees ({formatUsdc((groupFees?.[i]?.result as bigint) ?? 0n)})
                          </Button>
                        </div>
                      </div>
                    </CardHeader>
                  </Card>
                ))}
              </div>
            </>
          )}

          <Card className="mt-10 border-gold/40 bg-accent/20">
            <CardHeader>
              <div className="flex items-center gap-2">
                <ShieldCheck className="h-5 w-5 text-primary" />
                <CardTitle className="text-base">Guardian actions</CardTitle>
              </div>
              <CardDescription>
                Pause switches live in the guardian wallet (ops multisig in production) and only
                block new joins/contributions — never withdrawals.
              </CardDescription>
            </CardHeader>
            <CardContent className="flex flex-wrap gap-2">
              {myPlanDetails.map((p) => (
                <Button
                  key={p.address}
                  size="sm"
                  variant="outline"
                  onClick={() => write(p.address, planAbi, "pause")}
                  disabled={busy}
                >
                  <PauseCircle className="h-4 w-4" /> Pause {p.metadataURI || shortAddress(p.address)}
                </Button>
              ))}
            </CardContent>
          </Card>
        </>
      )}
    </div>
  );
}
