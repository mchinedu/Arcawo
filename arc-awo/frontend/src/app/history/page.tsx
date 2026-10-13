"use client";

import { useEffect, useMemo, useState } from "react";
import { useAccount, usePublicClient } from "wagmi";
import { parseAbiItem } from "viem";
import { Download, FileText, History as HistoryIcon, Loader2 } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { useRegistry } from "@/hooks/useRegistry";
import { formatUsdc, shortAddress, formatDate } from "@/lib/format";
import { downloadCsv, printReceipt } from "@/lib/csv";
import type { Address } from "viem";

type Row = {
  kind: "Contribution" | "Withdrawal" | "Pot claimed";
  instance: Address;
  amount: bigint;
  detail: string;
  timestamp: number;
  txHash: string;
};

const contributedPlan = parseAbiItem("event Contributed(address indexed member, uint256 indexed period, uint256 amount, bool nativeRail)");
const withdrawnPlan = parseAbiItem("event Withdrawn(address indexed member, uint256 gross, uint256 payout, uint256 collectorFee, uint256 protocolFee, uint256 penalty, bool early)");
const contributedGroup = parseAbiItem("event Contributed(address indexed member, uint256 indexed round, uint256 amount, uint256 lateFee, bool nativeRail, bool arrearsSettlement)");
const potClaimed = parseAbiItem("event PotClaimed(uint256 indexed round, address indexed winner, uint256 pot, uint256 collectorFee)");

export default function HistoryPage() {
  const { address, isConnected } = useAccount();
  const publicClient = usePublicClient();
  const { plans, groups, isLoading: registryLoading } = useRegistry();
  const [rows, setRows] = useState<Row[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!isConnected || !address || !publicClient || registryLoading) return;
    let cancelled = false;
    setLoading(true);
    setError(null);

    (async () => {
      try {
        const latest = await publicClient.getBlockNumber();
        const fromBlock = latest > 500_000n ? latest - 500_000n : 0n;
        const user = address.toLowerCase() as `0x${string}`;
        const out: Row[] = [];

        const fetchLogs = async (instance: Address, event: any, mapper: (log: any) => Row | null) => {
          const logs = await publicClient.getLogs({
            address: instance,
            event,
            args: { member: address },
            fromBlock,
            toBlock: latest,
          });
          for (const log of logs) {
            const block = await publicClient.getBlock({ blockNumber: log.blockNumber });
            const row = mapper(log);
            if (row) out.push({ ...row, timestamp: Number(block.timestamp), txHash: log.transactionHash ?? "" });
          }
        };

        // Pot claims where user is the winner (indexed by winner, not member).
        const fetchPotClaims = async (instance: Address) => {
          const logs = await publicClient.getLogs({
            address: instance,
            event: potClaimed,
            args: { winner: address },
            fromBlock,
            toBlock: latest,
          });
          for (const log of logs) {
            const block = await publicClient.getBlock({ blockNumber: log.blockNumber });
            out.push({
              kind: "Pot claimed",
              instance,
              amount: (log.args as any).pot,
              detail: `Round ${Number((log.args as any).round) + 1}`,
              timestamp: Number(block.timestamp),
              txHash: log.transactionHash ?? "",
            });
          }
        };

        await Promise.all([
          ...plans.map((p) =>
            fetchLogs(p, contributedPlan, (log) => ({
              kind: "Contribution",
              instance: p,
              amount: (log.args as any).amount,
              detail: `Period ${Number((log.args as any).period) + 1}${(log.args as any).nativeRail ? " · native rail" : ""}`,
              timestamp: 0,
              txHash: "",
            }))
          ),
          ...plans.map((p) =>
            fetchLogs(p, withdrawnPlan, (log) => ({
              kind: "Withdrawal",
              instance: p,
              amount: (log.args as any).payout,
              detail: (log.args as any).early ? "Early exit (after fees & penalty)" : "Cycle-end withdrawal",
              timestamp: 0,
              txHash: "",
            }))
          ),
          ...groups.map((g) =>
            fetchLogs(g, contributedGroup, (log) => ({
              kind: "Contribution",
              instance: g,
              amount: (log.args as any).amount,
              detail: `Round ${Number((log.args as any).round) + 1}${(log.args as any).arrearsSettlement ? " · arrears" : ""}`,
              timestamp: 0,
              txHash: "",
            }))
          ),
          ...groups.map((g) => fetchPotClaims(g)),
        ]);

        if (!cancelled) {
          out.sort((a, b) => b.timestamp - a.timestamp);
          setRows(out);
        }
      } catch (e: any) {
        if (!cancelled) setError(e?.message?.slice(0, 140) ?? "Failed to load logs");
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [address, isConnected, publicClient, plans, groups, registryLoading]);

  const totals = useMemo(() => {
    const contributed = rows.filter((r) => r.kind === "Contribution").reduce((a, r) => a + r.amount, 0n);
    const received = rows.filter((r) => r.kind !== "Contribution").reduce((a, r) => a + r.amount, 0n);
    return { contributed, received };
  }, [rows]);

  const exportCsv = () =>
    downloadCsv(
      "arc-awo-history.csv",
      rows.map((r) => ({
        type: r.kind,
        instance: r.instance,
        amount_usdc: Number(r.amount) / 1e6,
        detail: r.detail,
        date: new Date(r.timestamp * 1000).toISOString(),
        tx: r.txHash,
      }))
    );

  const exportPdf = () =>
    printReceipt(
      "Contribution history",
      `<table><tr><th>Type</th><th>Instance</th><th>Amount</th><th>Detail</th><th>Date</th></tr>
      ${rows
        .map(
          (r) =>
            `<tr><td>${r.kind}</td><td>${shortAddress(r.instance)}</td><td>${formatUsdc(r.amount)}</td><td>${r.detail}</td><td>${formatDate(r.timestamp)}</td></tr>`
        )
        .join("")}</table>`
    );

  if (!isConnected) {
    return (
      <div className="container flex flex-col items-center gap-6 py-24 text-center">
        <HistoryIcon className="h-12 w-12 text-primary" />
        <h1 className="text-2xl font-bold">Connect to see your history</h1>
        <p className="max-w-md text-muted-foreground">Every contribution and payout, exportable as CSV or PDF.</p>
      </div>
    );
  }

  return (
    <div className="container py-10">
      <div className="flex flex-col justify-between gap-4 sm:flex-row sm:items-center">
        <div>
          <h1 className="text-2xl font-bold tracking-tight sm:text-3xl">Contribution history</h1>
          <p className="mt-1 text-muted-foreground">
            {rows.length} on-chain events · {formatUsdc(totals.contributed)} in · {formatUsdc(totals.received)} out
          </p>
        </div>
        <div className="flex gap-2">
          <Button variant="outline" onClick={exportCsv} disabled={rows.length === 0}>
            <Download className="h-4 w-4" /> CSV
          </Button>
          <Button variant="gold" onClick={exportPdf} disabled={rows.length === 0}>
            <FileText className="h-4 w-4" /> PDF receipt
          </Button>
        </div>
      </div>

      <Card className="mt-8">
        <CardHeader>
          <CardTitle>Events</CardTitle>
          <CardDescription>Read directly from Arc — no intermediary database.</CardDescription>
        </CardHeader>
        <CardContent>
          {loading || registryLoading ? (
            <div className="flex items-center justify-center gap-2 py-16 text-muted-foreground">
              <Loader2 className="h-5 w-5 animate-spin" /> Scanning the chain…
            </div>
          ) : error ? (
            <p className="py-16 text-center text-sm text-muted-foreground">{error}</p>
          ) : rows.length === 0 ? (
            <p className="py-16 text-center text-muted-foreground">No events found yet.</p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Type</TableHead>
                  <TableHead>Thrift</TableHead>
                  <TableHead>Detail</TableHead>
                  <TableHead>Amount</TableHead>
                  <TableHead>Date</TableHead>
                  <TableHead>Tx</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {rows.map((r, i) => (
                  <TableRow key={`${r.txHash}-${i}`}>
                    <TableCell>
                      <Badge variant={r.kind === "Contribution" ? "secondary" : r.kind === "Pot claimed" ? "gold" : "success"}>
                        {r.kind}
                      </Badge>
                    </TableCell>
                    <TableCell className="font-mono text-xs">{shortAddress(r.instance)}</TableCell>
                    <TableCell>{r.detail}</TableCell>
                    <TableCell className="font-semibold">{formatUsdc(r.amount)}</TableCell>
                    <TableCell className="whitespace-nowrap text-muted-foreground">{formatDate(r.timestamp)}</TableCell>
                    <TableCell className="font-mono text-xs text-muted-foreground">{shortAddress(r.txHash)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
