"use client";

import Link from "next/link";
import { useAccount, useReadContracts } from "wagmi";
import { Search } from "lucide-react";
import { useMemo, useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { planAbi, groupAbi } from "@/lib/abis";
import { useRegistry, type PlanParams, type GroupParams } from "@/hooks/useRegistry";
import { formatUsdc, shortAddress, FREQUENCY_LABELS, PAYOUT_MODES, formatDateShort } from "@/lib/format";
import { ConfigNotice } from "@/components/ConfigNotice";
import { isConfigured } from "@/lib/contracts";

function BrowseInner() {
  const { address } = useAccount();
  const { plans, groups, isLoading } = useRegistry();
  const [q, setQ] = useState("");

  const planContracts = plans.map((p) => ({ address: p, abi: planAbi, functionName: "params" as const }));
  const groupContracts = groups.map((g) => ({ address: g, abi: groupAbi, functionName: "params" as const }));
  const groupStateContracts = groups.map((g) => ({ address: g, abi: groupAbi, functionName: "state" as const }));
  const groupCountContracts = groups.map((g) => ({ address: g, abi: groupAbi, functionName: "memberCount" as const }));

  const { data: planData, isLoading: p1 } = useReadContracts({ contracts: planContracts, query: { enabled: plans.length > 0 } });
  const { data: groupData, isLoading: p2 } = useReadContracts({ contracts: groupContracts, query: { enabled: groups.length > 0 } });
  const { data: groupStates } = useReadContracts({ contracts: groupStateContracts, query: { enabled: groups.length > 0 } });
  const { data: groupCounts } = useReadContracts({ contracts: groupCountContracts, query: { enabled: groups.length > 0 } });

  const planRows = useMemo(
    () =>
      plans.map((addr, i) => ({
        addr,
        params: planData?.[i]?.result as PlanParams | undefined,
      })),
    [plans, planData]
  );
  const groupRows = useMemo(
    () =>
      groups.map((addr, i) => ({
        addr,
        params: groupData?.[i]?.result as GroupParams | undefined,
        state: Number(groupStates?.[i]?.result ?? 0),
        joined: Number(groupCounts?.[i]?.result ?? 0),
      })),
    [groups, groupData, groupStates, groupCounts]
  );

  const query = q.trim().toLowerCase();
  const match = (meta?: string, addr?: string) =>
    !query || (meta ?? "").toLowerCase().includes(query) || (addr ?? "").toLowerCase().includes(query);

  const filteredPlans = planRows.filter((r) => match(r.params?.metadataURI, r.addr));
  const filteredGroups = groupRows.filter((r) => match(r.params?.metadataURI, r.addr));

  return (
    <div className="container py-10">
      <div className="flex flex-col justify-between gap-4 sm:flex-row sm:items-center">
        <div>
          <h1 className="text-2xl font-bold tracking-tight sm:text-3xl">Browse public thrifts</h1>
          <p className="mt-1 text-muted-foreground">
            Every plan and group deployed through the factory — verify the rules before you join.
          </p>
        </div>
        <div className="relative w-full sm:w-72">
          <Search className="absolute left-3 top-3 h-4 w-4 text-muted-foreground" />
          <Input className="pl-9" placeholder="Search by name or address…" value={q} onChange={(e) => setQ(e.target.value)} />
        </div>
      </div>

      {isLoading || p1 || p2 ? (
        <div className="mt-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {Array.from({ length: 6 }).map((_, i) => (
            <Skeleton key={i} className="h-44" />
          ))}
        </div>
      ) : filteredPlans.length === 0 && filteredGroups.length === 0 ? (
        <Card className="mt-8">
          <CardContent className="py-16 text-center text-muted-foreground">
            {plans.length === 0 && groups.length === 0
              ? "Nothing deployed yet. Be the first — create a plan or group."
              : "No results for that search."}
          </CardContent>
        </Card>
      ) : (
        <>
          {filteredGroups.length > 0 && (
            <>
              <h2 className="mt-8 text-lg font-semibold">Rotating groups (Isusu)</h2>
              <div className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
                {filteredGroups.map((r) => (
                  <Link key={r.addr} href={`/group/${r.addr}`}>
                    <Card className="card-hover h-full">
                      <CardHeader className="pb-2">
                        <div className="flex items-start justify-between gap-2">
                          <CardTitle className="text-base">{r.params?.metadataURI || "Isusu group"}</CardTitle>
                          <Badge variant={r.state === 1 ? "success" : r.state === 2 ? "secondary" : "gold"}>
                            {r.state === 0 ? "Open" : r.state === 1 ? "Active" : "Completed"}
                          </Badge>
                        </div>
                        <CardDescription>{shortAddress(r.addr)}</CardDescription>
                      </CardHeader>
                      <CardContent className="text-sm">
                        <div className="flex justify-between">
                          <span className="text-muted-foreground">Stake / round</span>
                          <span className="font-semibold">{formatUsdc(r.params?.contributionAmount ?? 0n)}</span>
                        </div>
                        <div className="mt-1 flex justify-between">
                          <span className="text-muted-foreground">Members</span>
                          <span className="font-medium">
                            {r.joined}/{r.params?.memberCount ?? "?"} · {PAYOUT_MODES[r.params?.payoutMode ?? 0]}
                          </span>
                        </div>
                        <div className="mt-1 flex justify-between">
                          <span className="text-muted-foreground">Frequency</span>
                          <span className="font-medium">{FREQUENCY_LABELS[r.params?.frequency ?? 1]}</span>
                        </div>
                      </CardContent>
                    </Card>
                  </Link>
                ))}
              </div>
            </>
          )}

          {filteredPlans.length > 0 && (
            <>
              <h2 className="mt-10 text-lg font-semibold">Savings plans (Akawo)</h2>
              <div className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
                {filteredPlans.map((r) => (
                  <Link key={r.addr} href={`/plan/${r.addr}`}>
                    <Card className="card-hover h-full">
                      <CardHeader className="pb-2">
                        <CardTitle className="text-base">{r.params?.metadataURI || "Savings plan"}</CardTitle>
                        <CardDescription>
                          {shortAddress(r.addr)} · by {shortAddress(r.params?.collector)}
                          {r.params?.collector?.toLowerCase() === address?.toLowerCase() ? " (you)" : ""}
                        </CardDescription>
                      </CardHeader>
                      <CardContent className="text-sm">
                        <div className="flex justify-between">
                          <span className="text-muted-foreground">Contribution</span>
                          <span className="font-semibold">
                            {formatUsdc(r.params?.contributionAmount ?? 0n)}{" "}
                            {FREQUENCY_LABELS[r.params?.frequency ?? 1]?.toLowerCase()}
                          </span>
                        </div>
                        <div className="mt-1 flex justify-between">
                          <span className="text-muted-foreground">Cycle</span>
                          <span className="font-medium">{r.params?.durationPeriods ?? "?"} periods</span>
                        </div>
                        <div className="mt-1 flex justify-between">
                          <span className="text-muted-foreground">Fee</span>
                          <span className="font-medium">{((r.params?.feeBps ?? 0) / 100).toFixed(2)}%</span>
                        </div>
                        {r.params?.startTime ? (
                          <p className="mt-2 text-xs text-muted-foreground">
                            Started {formatDateShort(r.params.startTime)}
                          </p>
                        ) : null}
                      </CardContent>
                    </Card>
                  </Link>
                ))}
              </div>
            </>
          )}
        </>
      )}
    </div>
  );
}

export default function BrowsePage() {
  if (!isConfigured) return <ConfigNotice />;
  return <BrowseInner />;
}
