"use client";

import { use, useState } from "react";
import { useAccount, useReadContract, useReadContracts, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { toast } from "sonner";
import { ArrowLeft, Banknote, Dices, Loader2, Shuffle, UserPlus } from "lucide-react";
import Link from "next/link";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { groupAbi } from "@/lib/abis";
import { formatUsdc, shortAddress, FREQUENCY_LABELS, PAYOUT_MODES, bpsLabel, formatDate } from "@/lib/format";
import type { Address } from "viem";
import { stringToBytes, keccak256 } from "viem";

const STATE_LABELS = ["Open", "Active", "Completed"];

export default function GroupDetailPage({ params }: { params: Promise<{ address: string }> }) {
  const { address: routeAddress } = use(params);
  const group = routeAddress as Address;
  const { address: user } = useAccount();
  const [secret, setSecret] = useState("");

  const { data: p, isLoading } = useReadContract({ address: group, abi: groupAbi, functionName: "params" });
  const { data: misc } = useReadContracts({
    contracts: [
      { address: group, abi: groupAbi, functionName: "state" },
      { address: group, abi: groupAbi, functionName: "currentRound" },
      { address: group, abi: groupAbi, functionName: "startTime" },
      { address: group, abi: groupAbi, functionName: "memberCount" },
      { address: group, abi: groupAbi, functionName: "totalContributed" },
      { address: group, abi: groupAbi, functionName: "memberOf", args: [user!] },
    ] as any,
    query: { enabled: !!user },
  });

  const state = Number(misc?.[0]?.result ?? 0);
  const currentRound = Number(misc?.[1]?.result ?? 0);
  const startTime = (misc?.[2]?.result as bigint) ?? 0n;
  const joined = Number(misc?.[3]?.result ?? 0);
  const totalContributed = (misc?.[4]?.result as bigint) ?? 0n;
  const me = misc?.[5]?.result as any;

  const paramsTuple = p as any;
  const contributionAmount = (paramsTuple?.[2] as bigint) ?? 0n;
  const frequency = Number(paramsTuple?.[3] ?? 1);
  const memberCount = Number(paramsTuple?.[4] ?? 0);
  const payoutMode = Number(paramsTuple?.[5] ?? 0);
  const feeBps = Number(paramsTuple?.[6] ?? 0);
  const lateFeeBps = Number(paramsTuple?.[7] ?? 0);
  const metadataURI = (paramsTuple?.[13] as string) ?? "";
  const collector = paramsTuple?.[0] as Address | undefined;

  const { writeContract, data: hash, isPending } = useWriteContract();
  const { isLoading: txPending } = useWaitForTransactionReceipt({ hash });
  const busy = isPending || txPending;

  const doWrite = (functionName: string, args: unknown[] = [], value?: bigint) =>
    writeContract(
      { address: group, abi: groupAbi, functionName: functionName as any, args: args as any, value } as any,
      { onSuccess: () => toast.success("Transaction sent"), onError: (e) => toast.error(e.message.slice(0, 120)) }
    );

  const commitSecret = () => {
    if (!secret) return toast.error("Enter a secret word first");
    const hash32 = keccak256(stringToBytes(secret));
    doWrite("commit", [hash32]);
  };

  const revealSecret = (round: number) => {
    if (!secret) return toast.error("Enter the secret you committed");
    const hash32 = keccak256(stringToBytes(secret));
    doWrite("reveal", [hash32, BigInt(round)]);
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
            <h1 className="text-2xl font-bold tracking-tight sm:text-3xl">{metadataURI || "Isusu group"}</h1>
            <Badge variant={state === 1 ? "success" : state === 2 ? "secondary" : "gold"}>{STATE_LABELS[state]}</Badge>
          </div>
          <p className="mt-1 text-sm text-muted-foreground">
            {shortAddress(group)} · coordinator {shortAddress(collector)} · {FREQUENCY_LABELS[frequency]} ·{" "}
            {PAYOUT_MODES[payoutMode]} · fee {bpsLabel(feeBps)} · late {bpsLabel(lateFeeBps)}
          </p>
        </div>
        <div className="flex gap-2">
          {state === 0 ? (
            <Button
              onClick={() => doWrite("join", ["0x0000000000000000000000000000000000000000"])}
              disabled={busy || Boolean(me?.joined)}
            >
              {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <UserPlus className="h-4 w-4" />}
              {me?.joined ? "You're in" : `Join (${joined}/${memberCount})`}
            </Button>
          ) : null}
        </div>
      </div>

      <div className="mt-8 grid gap-4 sm:grid-cols-4">
        <Card>
          <CardHeader className="pb-2"><CardTitle className="text-sm text-muted-foreground">Stake / round</CardTitle></CardHeader>
          <CardContent className="text-xl font-bold">{formatUsdc(contributionAmount)}</CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2"><CardTitle className="text-sm text-muted-foreground">Pot size (est.)</CardTitle></CardHeader>
          <CardContent className="text-xl font-bold">{formatUsdc(contributionAmount * BigInt(memberCount || 0))}</CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2"><CardTitle className="text-sm text-muted-foreground">Total contributed</CardTitle></CardHeader>
          <CardContent className="text-xl font-bold">{formatUsdc(totalContributed)}</CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2"><CardTitle className="text-sm text-muted-foreground">Rounds</CardTitle></CardHeader>
          <CardContent className="text-xl font-bold">{memberCount ? `${currentRound + 1} / ${memberCount}` : "—"}</CardContent>
        </Card>
      </div>

      {/* My contribution */}
      {state === 1 && me?.joined ? (
        <Card className="mt-8">
          <CardHeader>
            <CardTitle>Pay round {currentRound + 1}</CardTitle>
            <CardDescription>
              {formatUsdc(contributionAmount)} due this round. Late payments (after the round window) add{" "}
              {bpsLabel(lateFeeBps)} to the pot.
            </CardDescription>
          </CardHeader>
          <CardContent className="flex flex-col gap-2 sm:flex-row">
            <Button
              onClick={() =>
                doWrite(
                  "contributeNative",
                  [BigInt(currentRound)],
                  contributionAmount * 10n ** 12n
                )
              }
              disabled={busy}
            >
              {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <Banknote className="h-4 w-4" />}
              Pay round {currentRound + 1}
            </Button>
            {payoutMode === 1 ? (
              <Button variant="outline" onClick={() => doWrite("requestSelection", [BigInt(currentRound)])} disabled={busy}>
                <Dices className="h-4 w-4" /> Request round selection
              </Button>
            ) : null}
          </CardContent>
        </Card>
      ) : null}

      {/* Lottery controls */}
      {payoutMode === 1 && state === 1 ? (
        <Card className="mt-6">
          <CardHeader>
            <CardTitle>Lottery (commit-reveal)</CardTitle>
            <CardDescription>
              The coordinator commits one secret before round 1 and reveals it per round. Anyone can
              open the fallback selection if the reveal is withheld.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-3">
            <div className="grid gap-3 sm:grid-cols-[1fr_auto_auto] sm:items-end">
              <div className="space-y-1.5">
                <Label>Secret word</Label>
                <Input type="password" value={secret} onChange={(e) => setSecret(e.target.value)} placeholder="••••••" />
              </div>
              <Button variant="secondary" onClick={commitSecret} disabled={busy}>
                Commit hash
              </Button>
              <Button variant="gold" onClick={() => revealSecret(currentRound)} disabled={busy}>
                <Shuffle className="h-4 w-4" /> Reveal round {currentRound + 1}
              </Button>
            </div>
            <Button
              variant="outline"
              onClick={() => doWrite("fallbackSelect", [BigInt(currentRound)])}
              disabled={busy}
            >
              Fallback selection (after timeout)
            </Button>
          </CardContent>
        </Card>
      ) : null}

      {/* Rounds table */}
      <Card className="mt-8">
        <CardHeader>
          <CardTitle>Rounds</CardTitle>
          <CardDescription>
            {payoutMode === 0
              ? "Fixed order — member #1 is paid first, in join order."
              : "Lottery — winner selected per round by commit-reveal."}
          </CardDescription>
        </CardHeader>
        <CardContent>
          <RoundsTable group={group} memberCount={memberCount} startTime={startTime} frequency={frequency} me={me} busy={busy}
            onClaim={(r) => doWrite("claimPot", [BigInt(r)])}
            onRedistribute={(r) => doWrite("redistribute", [BigInt(r)])}
          />
        </CardContent>
      </Card>
    </div>
  );
}

function RoundsTable({
  group,
  memberCount,
  startTime,
  frequency,
  me,
  busy,
  onClaim,
  onRedistribute,
}: {
  group: Address;
  memberCount: number;
  startTime: bigint;
  frequency: number;
  me: any;
  busy: boolean;
  onClaim: (r: number) => void;
  onRedistribute: (r: number) => void;
}) {
  const rounds = Array.from({ length: Math.max(memberCount, 0) }, (_, i) => i);

  const { data } = useReadContracts({
    contracts: rounds.flatMap((r) => [
      { address: group, abi: groupAbi, functionName: "potOf", args: [BigInt(r)] as const },
      { address: group, abi: groupAbi, functionName: "winnerOf", args: [BigInt(r)] as const },
      { address: group, abi: groupAbi, functionName: "potClaimed", args: [BigInt(r)] as const },
    ]),
    query: { enabled: rounds.length > 0 },
  });

  const paidBit = me?.paidBitmap ? BigInt(me.paidBitmap) : 0n;

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Round</TableHead>
          <TableHead>Window ends</TableHead>
          <TableHead>Pot</TableHead>
          <TableHead>Winner</TableHead>
          <TableHead>You paid</TableHead>
          <TableHead></TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {rounds.map((r) => {
          const pot = (data?.[r * 3]?.result as unknown as bigint) ?? 0n;
          const winner = (data?.[r * 3 + 1]?.result as unknown as Address) ?? undefined;
          const claimed = Boolean(data?.[r * 3 + 2]?.result) ?? false;
          const endTs = startTime > 0n ? startTime + BigInt(r + 1) * (frequency === 0 ? 86400n : frequency === 1 ? 604800n : 2592000n) : 0n;
          const paid = (paidBit & (1n << BigInt(r))) !== 0n;
          return (
            <TableRow key={r}>
              <TableCell className="font-medium">#{r + 1}</TableCell>
              <TableCell>{endTs > 0n ? formatDate(endTs) : "—"}</TableCell>
              <TableCell>{formatUsdc(pot)}</TableCell>
              <TableCell>
                {winner && winner !== "0x0000000000000000000000000000000000000000" ? shortAddress(winner) : claimed ? "—" : "TBD"}
              </TableCell>
              <TableCell>{paid ? <Badge variant="success">Paid</Badge> : <Badge variant="outline">Due</Badge>}</TableCell>
              <TableCell>
                {claimed ? (
                  <Badge variant="secondary">Claimed</Badge>
                ) : (
                  <div className="flex justify-end gap-1">
                    <Button size="sm" variant="outline" onClick={() => onClaim(r)} disabled={busy}>
                      Claim
                    </Button>
                    <Button size="sm" variant="ghost" onClick={() => onRedistribute(r)} disabled={busy}>
                      Redistribute
                    </Button>
                  </div>
                )}
              </TableCell>
            </TableRow>
          );
        })}
        {rounds.length === 0 ? (
          <TableRow>
            <TableCell colSpan={6} className="py-8 text-center text-muted-foreground">
              Group has not filled yet — {0}/{memberCount} members joined.
            </TableCell>
          </TableRow>
        ) : null}
      </TableBody>
    </Table>
  );
}
