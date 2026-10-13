"use client";

import Link from "next/link";
import { useAccount } from "wagmi";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { ArrowUpRight, CalendarClock, PiggyBank, TrendingUp, Wallet } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { useMyInstances } from "@/hooks/useInstances";
import { formatUsdc, formatDateShort, FREQUENCY_LABELS, PAYOUT_MODES, shortAddress } from "@/lib/format";

export default function DashboardPage() {
  const { isConnected, address } = useAccount();
  const { myPlans, myGroups, isLoading, totalSaved, totalClaimable } = useMyInstances();

  if (!isConnected) {
    return (
      <div className="container flex flex-col items-center gap-6 py-24 text-center">
        <Wallet className="h-12 w-12 text-primary" />
        <h1 className="text-2xl font-bold">Connect your wallet</h1>
        <p className="max-w-md text-muted-foreground">
          See your thrift contributions, upcoming payouts and savings — all in one place.
        </p>
        <ConnectButton />
      </div>
    );
  }

  return (
    <div className="container py-10">
      <div className="flex flex-col justify-between gap-4 sm:flex-row sm:items-center">
        <div>
          <h1 className="text-2xl font-bold tracking-tight sm:text-3xl">Dashboard</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            {shortAddress(address)} · savings overview
          </p>
        </div>
        <Button asChild>
          <Link href="/create">Start something new</Link>
        </Button>
      </div>

      {/* Stats */}
      <div className="mt-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Card>
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">Total saved</CardTitle>
            <PiggyBank className="h-4 w-4 text-primary" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{isLoading ? <Skeleton className="h-7 w-20" /> : formatUsdc(totalSaved)}</div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">Claimable now</CardTitle>
            <TrendingUp className="h-4 w-4 text-gold" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{isLoading ? <Skeleton className="h-7 w-20" /> : formatUsdc(totalClaimable)}</div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">Active plans</CardTitle>
            <CalendarClock className="h-4 w-4 text-primary" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{isLoading ? <Skeleton className="h-7 w-10" /> : myPlans.filter((p) => !p.isComplete).length}</div>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="flex flex-row items-center justify-between pb-2">
            <CardTitle className="text-sm font-medium text-muted-foreground">Savings groups</CardTitle>
            <ArrowUpRight className="h-4 w-4 text-primary" />
          </CardHeader>
          <CardContent>
            <div className="text-2xl font-bold">{isLoading ? <Skeleton className="h-7 w-10" /> : myGroups.length}</div>
          </CardContent>
        </Card>
      </div>

      {/* Plans */}
      <h2 className="mt-10 text-lg font-semibold">My savings plans</h2>
      <div className="mt-4 grid gap-4 sm:grid-cols-2">
        {isLoading ? (
          <>
            <Skeleton className="h-36" />
            <Skeleton className="h-36" />
          </>
        ) : myPlans.length === 0 ? (
          <Card className="sm:col-span-2">
            <CardContent className="py-10 text-center text-muted-foreground">
              No plans yet.{" "}
              <Link href="/create" className="font-medium text-primary hover:underline">
                Create your first Akawo plan →
              </Link>
            </CardContent>
          </Card>
        ) : (
          myPlans.map((p) => (
            <Link key={p.address} href={`/plan/${p.address}`}>
              <Card className="card-hover h-full">
                <CardHeader className="pb-3">
                  <div className="flex items-start justify-between">
                    <CardTitle className="text-base">{p.metadataURI || "Savings plan"}</CardTitle>
                    <Badge variant={p.isComplete ? "secondary" : "success"}>
                      {p.isComplete ? "Completed" : "Active"}
                    </Badge>
                  </div>
                  <CardDescription>
                    {FREQUENCY_LABELS[p.frequency] ?? "Weekly"} · {shortAddress(p.address)}
                  </CardDescription>
                </CardHeader>
                <CardContent>
                  <div className="flex items-end justify-between">
                    <div>
                      <p className="text-xs text-muted-foreground">Contributed</p>
                      <p className="text-lg font-bold">{formatUsdc(p.totalContributed)}</p>
                    </div>
                    <div className="text-right">
                      <p className="text-xs text-muted-foreground">Claimable</p>
                      <p className="text-lg font-bold text-primary">{formatUsdc(p.claimable)}</p>
                    </div>
                  </div>
                  {!p.isComplete && p.cycleEnd > 0n && (
                    <p className="mt-3 text-xs text-muted-foreground">
                      Cycle ends {formatDateShort(p.cycleEnd)}
                    </p>
                  )}
                </CardContent>
              </Card>
            </Link>
          ))
        )}
      </div>

      {/* Groups */}
      <h2 className="mt-10 text-lg font-semibold">My rotating groups</h2>
      <div className="mt-4 grid gap-4 sm:grid-cols-2">
        {isLoading ? (
          <Skeleton className="h-36" />
        ) : myGroups.length === 0 ? (
          <Card className="sm:col-span-2">
            <CardContent className="py-10 text-center text-muted-foreground">
              Not in any group yet.{" "}
              <Link href="/browse" className="font-medium text-primary hover:underline">
                Browse public groups →
              </Link>
            </CardContent>
          </Card>
        ) : (
          myGroups.map((g) => (
            <Link key={g.address} href={`/group/${g.address}`}>
              <Card className="card-hover h-full">
                <CardHeader className="pb-3">
                  <div className="flex items-start justify-between">
                    <CardTitle className="text-base">{g.metadataURI || "Isusu group"}</CardTitle>
                    <Badge variant={g.won ? "gold" : "success"}>{g.won ? "Paid out" : "Active"}</Badge>
                  </div>
                  <CardDescription>
                    {PAYOUT_MODES[g.payoutMode] ?? "Fixed"} · {g.memberCount} members ·{" "}
                    {shortAddress(g.address)}
                  </CardDescription>
                </CardHeader>
                <CardContent>
                  <div className="flex items-end justify-between">
                    <div>
                      <p className="text-xs text-muted-foreground">Stake / round</p>
                      <p className="text-lg font-bold">{formatUsdc(g.contributionAmount)}</p>
                    </div>
                    <div className="text-right">
                      <p className="text-xs text-muted-foreground">Rounds paid</p>
                      <p className="text-lg font-bold text-primary">{g.roundsPaid}/{g.memberCount}</p>
                    </div>
                  </div>
                </CardContent>
              </Card>
            </Link>
          ))
        )}
      </div>
    </div>
  );
}
