"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useAccount, useWriteContract, useWaitForTransactionReceipt, useReadContract } from "wagmi";
import { toast } from "sonner";
import { Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select } from "@/components/ui/select";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { factoryAbi } from "@/lib/abis";
import { FACTORY_ADDRESS, ZERO_ADDRESS, randomUserSalt } from "@/lib/contracts";
import { parseUsdc, formatUsdc, bpsLabel } from "@/lib/format";

function Field({ label, hint, children }: { label: string; hint?: string; children: React.ReactNode }) {
  return (
    <div className="space-y-1.5">
      <Label>{label}</Label>
      {children}
      {hint ? <p className="text-xs text-muted-foreground">{hint}</p> : null}
    </div>
  );
}

function Pending({ hash, label }: { hash?: `0x${string}`; label: string }) {
  const { isLoading, isSuccess } = useWaitForTransactionReceipt({ hash });
  if (!hash) return null;
  return (
    <p className="mt-3 flex items-center gap-2 text-sm text-muted-foreground">
      {isLoading ? (
        <>
          <Loader2 className="h-4 w-4 animate-spin" /> {label}…
        </>
      ) : isSuccess ? (
        <span className="text-primary">Confirmed on Arc ✓</span>
      ) : null}
    </p>
  );
}

export function CreatePlanForm() {
  const { address } = useAccount();
  const router = useRouter();
  const [amount, setAmount] = useState("5");
  const [frequency, setFrequency] = useState("1");
  const [periods, setPeriods] = useState("12");
  const [feeBps, setFeeBps] = useState("100");
  const [penaltyBps, setPenaltyBps] = useState("200");
  const [approval, setApproval] = useState("0");
  const [maxMembers, setMaxMembers] = useState("0");
  const [meta, setMeta] = useState("");
  const [referrer, setReferrer] = useState("");
  const [salt] = useState(randomUserSalt);

  const { writeContract, data: hash, isPending, error } = useWriteContract();

  const submit = () => {
    if (!address) return toast.error("Connect a wallet first");
    const startTime = BigInt(Math.floor(Date.now() / 1000) + 60);
    writeContract(
      {
        address: FACTORY_ADDRESS,
        abi: factoryAbi,
        functionName: "createPlan",
        args: [
          {
            collector: address,
            guardian: ZERO_ADDRESS, // stamped by factory
            contributionAmount: parseUsdc(amount),
            frequency: Number(frequency),
            startTime,
            durationPeriods: Number(periods),
            feeBps: Number(feeBps),
            earlyWithdrawPenaltyBps: Number(penaltyBps),
            protocolFeeBps: 0, // stamped by factory
            referralShareBps: 0, // stamped by factory
            treasury: ZERO_ADDRESS, // stamped by factory
            reputation: ZERO_ADDRESS, // stamped by factory
            approvalRequired: approval === "1",
            maxMembers: Number(maxMembers),
            metadataURI: meta || "Akawo savings plan",
          },
          salt,
          (referrer || ZERO_ADDRESS) as `0x${string}`,
        ],
      },
      {
        onSuccess: () => toast.success("Plan creation submitted"),
        onError: (e) => toast.error(e.message.slice(0, 120)),
      }
    );
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>Classic Akawo — savings plan</CardTitle>
        <CardDescription>
          Members contribute {formatUsdc(parseUsdc(amount) || 0n)}{" "}
          {(Number(frequency) === 0 && "daily") || (Number(frequency) === 1 && "weekly") || "monthly"}
          {Number(feeBps) > 0 && `, collector fee ${bpsLabel(Number(feeBps))}`}. You are the collector.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="Contribution per period (USDC)">
            <Input type="number" min="0.01" step="0.01" value={amount} onChange={(e) => setAmount(e.target.value)} />
          </Field>
          <Field label="Frequency">
            <Select
              value={frequency}
              onChange={(e) => setFrequency(e.target.value)}
              options={[
                { value: "0", label: "Daily" },
                { value: "1", label: "Weekly" },
                { value: "2", label: "Monthly (30 days)" },
              ]}
            />
          </Field>
          <Field label="Number of periods" hint={`1–256 · a full cycle of ${periods} periods`}>
            <Input type="number" min="1" max="256" value={periods} onChange={(e) => setPeriods(e.target.value)} />
          </Field>
          <Field label="Collector fee (bps)" hint={`${bpsLabel(Number(feeBps))} — capped at 1% by the factory`}>
            <Input type="number" min="0" max="100" value={feeBps} onChange={(e) => setFeeBps(e.target.value)} />
          </Field>
          <Field label="Early-withdraw penalty (bps)" hint={`${bpsLabel(Number(penaltyBps))} — capped at 5%`}>
            <Input type="number" min="0" max="500" value={penaltyBps} onChange={(e) => setPenaltyBps(e.target.value)} />
          </Field>
          <Field label="Join approval">
            <Select
              value={approval}
              onChange={(e) => setApproval(e.target.value)}
              options={[
                { value: "0", label: "Open — anyone can join" },
                { value: "1", label: "Approval required" },
              ]}
            />
          </Field>
          <Field label="Max members" hint="0 = unlimited">
            <Input type="number" min="0" max="5000" value={maxMembers} onChange={(e) => setMaxMembers(e.target.value)} />
          </Field>
          <Field label="Plan name / description">
            <Input value={meta} onChange={(e) => setMeta(e.target.value)} placeholder="e.g. Adewale family thrift" />
          </Field>
        </div>
        <Field label="Referrer (optional)" hint="Earns a share of protocol fees when enabled">
          <Input value={referrer} onChange={(e) => setReferrer(e.target.value)} placeholder="0x…" />
        </Field>
        <Button onClick={submit} disabled={isPending} className="w-full" size="lg">
          {isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : null} Create plan
        </Button>
        <Pending hash={hash} label="Creating plan" />
        {error ? <p className="text-sm text-destructive">{error.message.slice(0, 140)}</p> : null}
      </CardContent>
    </Card>
  );
}

export function CreateGroupForm() {
  const { address } = useAccount();
  const [amount, setAmount] = useState("10");
  const [frequency, setFrequency] = useState("1");
  const [members, setMembers] = useState("6");
  const [mode, setMode] = useState("0");
  const [feeBps, setFeeBps] = useState("100");
  const [lateFeeBps, setLateFeeBps] = useState("200");
  const [startDelay, setStartDelay] = useState("1");
  const [plays, setPlays] = useState("1");
  const [meta, setMeta] = useState("");
  const [referrer, setReferrer] = useState("");
  const [salt] = useState(randomUserSalt);

  const { writeContract, data: hash, isPending, error } = useWriteContract();

  const submit = () => {
    if (!address) return toast.error("Connect a wallet first");
    writeContract(
      {
        address: FACTORY_ADDRESS,
        abi: factoryAbi,
        functionName: "createGroup",
        args: [
          {
            collector: address,
            guardian: ZERO_ADDRESS,
            contributionAmount: parseUsdc(amount),
            frequency: Number(frequency),
            memberCount: Number(members),
            payoutMode: Number(mode),
            feeBps: Number(feeBps),
            lateFeeBps: Number(lateFeeBps),
            protocolFeeBps: 0,
            startDelay: BigInt(Number(startDelay) * 86400),
            treasury: ZERO_ADDRESS,
            reputation: ZERO_ADDRESS,
            collectorPlays: plays === "1",
            metadataURI: meta || "Isusu rotating group",
          },
          salt,
          (referrer || ZERO_ADDRESS) as `0x${string}`,
        ],
      },
      {
        onSuccess: () => toast.success("Group creation submitted"),
        onError: (e) => toast.error(e.message.slice(0, 120)),
      }
    );
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>Isusu / Ajo — rotating group</CardTitle>
        <CardDescription>
          {members} members × {formatUsdc(parseUsdc(amount) || 0n)} per cycle ·{" "}
          {mode === "0" ? "fixed payout order" : "lottery selection"} · {members} rounds.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="Stake per member per round (USDC)">
            <Input type="number" min="0.01" step="0.01" value={amount} onChange={(e) => setAmount(e.target.value)} />
          </Field>
          <Field label="Frequency">
            <Select
              value={frequency}
              onChange={(e) => setFrequency(e.target.value)}
              options={[
                { value: "0", label: "Daily" },
                { value: "1", label: "Weekly" },
                { value: "2", label: "Monthly (30 days)" },
              ]}
            />
          </Field>
          <Field label="Group size (N members = N rounds)" hint="2–100">
            <Input type="number" min="2" max="100" value={members} onChange={(e) => setMembers(e.target.value)} />
          </Field>
          <Field label="Payout order">
            <Select
              value={mode}
              onChange={(e) => setMode(e.target.value)}
              options={[
                { value: "0", label: "Fixed — join order (transparent)" },
                { value: "1", label: "Lottery — commit-reveal per round" },
              ]}
            />
          </Field>
          <Field label="Collector fee (bps)" hint={`${bpsLabel(Number(feeBps))} of each claimed pot`}>
            <Input type="number" min="0" max="100" value={feeBps} onChange={(e) => setFeeBps(e.target.value)} />
          </Field>
          <Field label="Late payment fee (bps)" hint={`${bpsLabel(Number(lateFeeBps))} added to the round pot`}>
            <Input type="number" min="0" max="500" value={lateFeeBps} onChange={(e) => setLateFeeBps(e.target.value)} />
          </Field>
          <Field label="Start delay (days after group fills)" hint="Time for members to get ready">
            <Input type="number" min="0" max="30" value={startDelay} onChange={(e) => setStartDelay(e.target.value)} />
          </Field>
          <Field label="Collector participates?">
            <Select
              value={plays}
              onChange={(e) => setPlays(e.target.value)}
              options={[
                { value: "1", label: "Yes — join as member #1" },
                { value: "0", label: "No — coordinate only" },
              ]}
            />
          </Field>
          <Field label="Group name / description">
            <Input value={meta} onChange={(e) => setMeta(e.target.value)} placeholder="e.g. Lagos Techies Isusu" />
          </Field>
          <Field label="Referrer (optional)">
            <Input value={referrer} onChange={(e) => setReferrer(e.target.value)} placeholder="0x…" />
          </Field>
        </div>
        <Button onClick={submit} disabled={isPending} className="w-full" size="lg" variant="gold">
          {isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : null} Create group
        </Button>
        <Pending hash={hash} label="Creating group" />
        {error ? <p className="text-sm text-destructive">{error.message.slice(0, 140)}</p> : null}
      </CardContent>
    </Card>
  );
}
