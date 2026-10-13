"use client";

import { use, useState } from "react";
import { useAccount, useReadContract, useReadContracts, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { toast } from "sonner";
import { ArrowLeft, Download, Loader2, LogOut, PiggyBank, UserPlus } from "lucide-react";
import Link from "next/link";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { erc20Abi, planAbi } from "@/lib/abis";
import { ARC_USDC_ADDRESS } from "@/lib/chains";
import { formatUsdc, formatDateShort, shortAddress, FREQUENCY_LABELS, bpsLabel, periodWindow, formatDate } from "@/lib/format";
import { printReceipt } from "@/lib/csv";
import type { Address } from "viem";

export default function PlanDetailPage({ params }: { params: Promise<{ address: string }> }) {
  const { address: routeAddress } = use(params);
  const plan = routeAddress as Address;
  const { address: user } = useAccount();
  const [selected, setSelected] = useState<number[]>([]);

  const { data: p, isLoading } = useReadContract({ address: plan, abi: planAbi, functionName: "params" });
  const { data: misc } = useReadContracts({
    contracts: [
      { address: plan, abi: planAbi, functionName: "isComplete" },
      { address: plan, abi: planAbi, functionName: "currentPeriod" },
      { address: plan, abi: planAbi, functionName: "cycleEnd" },
      { address: plan, abi: planAbi, functionName: "totalContributed" },
      { address: plan, abi: planAbi, functionName: "memberCount" },
      { address: plan, abi: planAbi, functionName: "usdcBalance" },
      { address: plan, abi: planAbi, functionName: "memberOf", args: [user!] },
      { address: plan, abi: planAbi, functionName: "claimableOf", args: [user!] },
    ] as any,
    query: { enabled: !!user },
  });

  const isComplete = (misc?.[0]?.result as boolean) ?? false;
  const currentPeriod = Number(misc?.[1]?.result ?? 0);
  const cycleEnd = (misc?.[2]?.result as bigint) ?? 0n;
  const totalContributed = (misc?.[3]?.result as bigint) ?? 0n;
  const memberCount = Number(misc?.[4]?.result ?? 0);
  const escrowBalance = (misc?.[5]?.result as bigint) ?? 0n;
  const me = misc?.[6]?.result as any;
  const myClaimable = (misc?.[7]?.result as bigint) ?? 0n;

  const paramsTuple = p as any;
  const frequency = Number(paramsTuple?.[3] ?? 1);
  const durationPeriods = Number(paramsTuple?.[5] ?? 0);
  const contributionAmount = (paramsTuple?.[2] as bigint) ?? 0n;
  const feeBps = Number(paramsTuple?.[6] ?? 0);
  const penaltyBps = Number(paramsTuple?.[7] ?? 0);
  const startTime = (paramsTuple?.[4] as bigint) ?? 0n;
  const metadataURI = (paramsTuple?.[14] as string) ?? "";
  const approvalRequired = Boolean(paramsTuple?.[12]);
  const collector = paramsTuple?.[0] as Address | undefined;

  const { writeContract, data: hash, isPending } = useWriteContract();
  const { isLoading: txPending, isSuccess } = useWaitForTransactionReceipt({ hash });
  const busy = isPending || txPending;

  const doWrite = (functionName: string, args: unknown[] = [], value?: bigint) =>
    writeContract(
      { address: plan, abi: planAbi, functionName: functionName as any, args: args as any, value } as any,
      { onSuccess: () => toast.success("Transaction sent"), onError: (e) => toast.error(e.message.slice(0, 120)) }
    );

  const doContribute = (native: boolean) => {
    if (selected.length === 0) return toast.error("Select at least one period");
    if (native) {
      doWrite("contributeNative", [selected], contributionAmount * BigInt(selected.length) * 10n ** 12n);
    } else {
      doWrite("contribute", [selected]);
    }
    setSelected([]);
  };

  const approveAndContribute = async () => {
    if (selected.length === 0) return toast.error("Select at least one period");
    const amount = contributionAmount * BigInt(selected.length);
    writeContract(
      { address: ARC_USDC_ADDRESS, abi: erc20Abi, functionName: "approve", args: [plan, amount] },
      {
        onSuccess: () => {
          toast.success("USDC approved — confirm the contribution next");
          setTimeout(() => doWrite("contribute", [selected]), 1500);
        },
        onError: (e) => toast.error(e.message.slice(0, 120)),
      }
    );
    setSelected([]);
  };

  const exportReceipt = () => {
    const rows = Array.from({ length: durationPeriods }, (_, i) => {
      const w = periodWindow(startTime, frequency, i);
      return {
        period: i,
        windowStart: formatDate(w.start),
        windowEnd: formatDate(w.end),
        amount: Number(contributionAmount) / 1e6,
        paid: me?.contributionBitmap ? (BigInt(me.contributionBitmap) & (1n << BigInt(i))) !== 0n : false,
      };
    });
    printReceipt(
      `Akawo plan — ${metadataURI || shortAddress(plan)}`,
      `<table><tr><th>Plan</th><td>${plan}</td></tr>
       <tr><th>Collector</th><td>${collector ?? "—"}</td></tr>
       <tr><th>Contribution</th><td>${formatUsdc(contributionAmount)} ${FREQUENCY_LABELS[frequency]}</td></tr>
       <tr><th>Fee</th><td>${bpsLabel(feeBps)} · early penalty ${bpsLabel(penaltyBps)}</td></tr>
       <tr><th>Cycle end</th><td>${formatDate(cycleEnd)}</td></tr></table>
       <br/><table><tr><th>#</th><th>Window</th><th>Amount</th><th>Paid</th></tr>
       ${rows.map((r) => `<tr><td>${r.period}</td><td>${r.windowStart} → ${r.windowEnd}</td><td>$${r.amount}</td><td>${r.paid ? "✓" : "—"}</td></tr>`).join("")}</table>`
    );
  };

  if (isLoading) return <div className="container py-10"><Skeleton className="h-96" /></div>;

  return (
    <div className="container py-10">
      <Link href="/browse" className="inline-flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground">
        <ArrowLeft className="h-4 w-4" /> All thrifts
      </Link>

      <div className="mt-4 flex flex-col justify-between gap-4 sm:flex-row sm:items-start">
        <div>
          <div className="flex items-center gap-3">
            <h1 className="text-2xl font-bold tracking-tight sm:text-3xl">{metadataURI || "Savings plan"}</h1>
            <Badge variant={isComplete ? "secondary" : "success"}>{isComplete ? "Completed" : "Active"}</Badge>
          </div>
          <p className="mt-1 text-sm text-muted-foreground">
            {shortAddress(plan)} · collector {shortAddress(collector)} · {FREQUENCY_LABELS[frequency]} ·{" "}
            {durationPeriods} periods · fee {bpsLabel(feeBps)}
            {penaltyBps > 0 ? ` · early exit penalty ${bpsLabel(penaltyBps)}` : ""}
          </p>
        </div>
        <div className="flex gap-2">
          <Button variant="outline" onClick={exportReceipt}>
            <Download className="h-4 w-4" /> Receipt
          </Button>
          {me?.joined && !me?.withdrawn ? (
            isComplete ? (
              <Button onClick={() => doWrite("withdraw")} disabled={busy}>
                {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <PiggyBank className="h-4 w-4" />}
                Withdraw {formatUsdc(myClaimable)}
              </Button>
            ) : (
              <Button variant="gold" onClick={() => doWrite("withdrawEarly")} disabled={busy}>
                {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <LogOut className="h-4 w-4" />}
                Exit early ({formatUsdc(myClaimable)})
              </Button>
            )
          ) : !me?.joined ? (
            <Button onClick={() => doWrite("join", ["0x0000000000000000000000000000000000000000"])} disabled={busy}>
              {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <UserPlus className="h-4 w-4" />}
              Join plan
            </Button>
          ) : null}
        </div>
      </div>

      {/* Stats */}
      <div className="mt-8 grid gap-4 sm:grid-cols-4">
        <Card>
          <CardHeader className="pb-2"><CardTitle className="text-sm text-muted-foreground">Escrow balance</CardTitle></CardHeader>
          <CardContent className="text-xl font-bold">{formatUsdc(escrowBalance)}</CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2"><CardTitle className="text-sm text-muted-foreground">Total contributed</CardTitle></CardHeader>
          <CardContent className="text-xl font-bold">{formatUsdc(totalContributed)}</CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2"><CardTitle className="text-sm text-muted-foreground">Members</CardTitle></CardHeader>
          <CardContent className="text-xl font-bold">{memberCount}</CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2"><CardTitle className="text-sm text-muted-foreground">Cycle ends</CardTitle></CardHeader>
          <CardContent className="text-xl font-bold">{cycleEnd ? formatDateShort(cycleEnd) : "—"}</CardContent>
        </Card>
      </div>

      {/* Contribution */}
      {me?.joined && me?.approved && !me?.withdrawn && !isComplete ? (
        <Card className="mt-8">
          <CardHeader>
            <CardTitle>Contribute periods</CardTitle>
            <CardDescription>
              {formatUsdc(contributionAmount)} per period · currently in period {currentPeriod + 1} of{" "}
              {durationPeriods}. Catch-up for missed periods is allowed.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <div className="grid grid-cols-2 gap-2 sm:grid-cols-4 md:grid-cols-6">
              {Array.from({ length: durationPeriods }, (_, i) => {
                const paid = me?.contributionBitmap ? (BigInt(me.contributionBitmap) & (1n << BigInt(i))) !== 0n : false;
                return (
                  <label
                    key={i}
                    className={`flex cursor-pointer items-center gap-2 rounded-md border px-3 py-2 text-sm ${
                      paid ? "border-primary/30 bg-primary/5 text-muted-foreground" : "hover:bg-secondary"
                    }`}
                  >
                    <Checkbox
                      checked={selected.includes(i)}
                      disabled={paid}
                      onCheckedChange={(v) =>
                        setSelected((s) => (v ? [...s, i] : s.filter((x) => x !== i)))
                      }
                    />
                    P{i + 1}
                    {paid ? <span className="ml-auto text-xs text-primary">✓</span> : null}
                  </label>
                );
              })}
            </div>
            <div className="mt-4 flex flex-col gap-2 sm:flex-row">
              <Button onClick={approveAndContribute} disabled={busy || selected.length === 0}>
                Pay {selected.length > 0 ? formatUsdc(contributionAmount * BigInt(selected.length)) : ""} with USDC
              </Button>
              <Button
                variant="gold"
                onClick={() => doContribute(true)}
                disabled={busy || selected.length === 0}
              >
                Pay with wallet balance (native)
              </Button>
            </div>
            <p className="mt-2 text-xs text-muted-foreground">
              Both buttons move the same Arc USDC — the first uses the ERC-20 rail (approve + transferFrom),
              the second sends native value. Balances are one pool on Arc.
            </p>
          </CardContent>
        </Card>
      ) : null}

      {/* Members */}
      <Card className="mt-8">
        <CardHeader>
          <CardTitle>Members & contributions</CardTitle>
          <CardDescription>{approvalRequired ? "Joining requires collector approval" : "Open join policy"}</CardDescription>
        </CardHeader>
        <CardContent>
          <MembersTable plan={plan} total={memberCount} />
        </CardContent>
      </Card>
    </div>
  );
}

function MembersTable({ plan, total }: { plan: Address; total: number }) {
  const { data } = useReadContract({
    address: plan,
    abi: planAbi,
    functionName: "members",
    args: [0n, BigInt(Math.max(total, 50))],
  });
  const members = (data as Address[] | undefined) ?? [];

  const { data: details } = useReadContracts({
    contracts: members.map((m) => ({ address: plan, abi: planAbi, functionName: "memberOf", args: [m] as const })),
    query: { enabled: members.length > 0 },
  });

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Member</TableHead>
          <TableHead>Periods paid</TableHead>
          <TableHead>Total contributed</TableHead>
          <TableHead>Status</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {members.map((m, i) => {
          const d = details?.[i]?.result as any;
          return (
            <TableRow key={m}>
              <TableCell className="font-medium">{shortAddress(m)}</TableCell>
              <TableCell>{d ? Number(d.contributedPeriods) : "—"}</TableCell>
              <TableCell>{d ? formatUsdc(d.totalContributed) : "—"}</TableCell>
              <TableCell>
                {d?.withdrawn ? (
                  <Badge variant="secondary">Withdrawn</Badge>
                ) : d?.approved ? (
                  <Badge variant="success">Active</Badge>
                ) : (
                  <Badge variant="warning">Pending approval</Badge>
                )}
              </TableCell>
            </TableRow>
          );
        })}
      </TableBody>
    </Table>
  );
}
