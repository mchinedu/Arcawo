import Link from "next/link";
import { ArrowRight, BadgeCheck, Coins, Lock, RefreshCw, ShieldCheck, Users, Zap } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

const steps = [
  {
    title: "Create or join",
    body: "A collector opens an Akawo savings plan, or friends open an Isusu rotating group. Rules are locked in a smart contract — not a WhatsApp promise.",
  },
  {
    title: "Contribute in USDC",
    body: "Save daily, weekly or monthly on Arc. Gas is paid in USDC too — no volatile token, fees are a fraction of a cent.",
  },
  {
    title: "Get paid automatically",
    body: "Withdraw at cycle end, or receive the rotating pot on your round. The contract holds everyone's money until the rules say otherwise.",
  },
];

const features = [
  { icon: ShieldCheck, title: "Collector can't run away", body: "Funds sit in non-upgradeable contract escrow. No admin key can touch member principal — only the rules can." },
  { icon: Zap, title: "Settled on Arc", body: "Sub-second deterministic finality and USDC-native gas. Contributions confirm faster than a bank transfer." },
  { icon: RefreshCw, title: "Two modes, one app", body: "Classic Akawo (collector-led daily savings) and Isusu (peer-to-peer rotating pot) — pick what your circle already trusts." },
  { icon: BadgeCheck, title: "On-chain reputation", body: "Collectors build a transparent score from completed cycles. See the record before you join." },
  { icon: Lock, title: "Your keys, your money", body: "Self-custody throughout. Withdraw to your own wallet anytime the plan rules allow." },
  { icon: Users, title: "Built for groups", body: "Approval gates, member limits, catch-up payments for missed days, and receipts you can export." },
];

export default function LandingPage() {
  return (
    <>
      {/* Hero */}
      <section className="hero-gradient text-white">
        <div className="container flex flex-col items-start gap-8 py-20 sm:py-28">
          <div className="inline-flex items-center gap-2 rounded-full border border-white/20 bg-white/10 px-4 py-1.5 text-xs font-medium text-white/90">
            <Coins className="h-3.5 w-3.5" />
            Powered by Arc — USDC is the native gas token
          </div>
          <h1 className="max-w-3xl text-4xl font-bold leading-tight tracking-tight sm:text-6xl">
            Thrift contribution,
            <span className="text-[hsl(43_90%_72%)]"> without the risk</span>
          </h1>
          <p className="max-w-2xl text-lg leading-relaxed text-white/85">
            Arc-awo brings the Nigerian <em>Akawo / Isusu / Ajo</em> tradition on-chain. Save
            daily, weekly or monthly in USDC with full transparency — no collector running away
            with the money, no manual record-keeping, automatic payouts.
          </p>
          <div className="flex flex-col gap-3 sm:flex-row">
            <Button asChild size="lg" variant="gold">
              <Link href="/create">
                Start a plan <ArrowRight className="h-4 w-4" />
              </Link>
            </Button>
            <Button
              asChild
              size="lg"
              className="border border-white/30 bg-white/10 text-white hover:bg-white/20"
            >
              <Link href="/browse">Browse public groups</Link>
            </Button>
          </div>
          <dl className="mt-6 grid grid-cols-2 gap-6 sm:grid-cols-4">
            {[
              ["$0", "Collector lock-ups"],
              ["1%", "Max collector fee"],
              ["<1s", "Finality on Arc"],
              ["6 dec", "USDC precision"],
            ].map(([v, l]) => (
              <div key={l}>
                <dt className="text-2xl font-bold text-[hsl(43_90%_72%)]">{v}</dt>
                <dd className="text-sm text-white/70">{l}</dd>
              </div>
            ))}
          </dl>
        </div>
      </section>

      {/* How it works */}
      <section className="container py-16 sm:py-24">
        <div className="mx-auto max-w-2xl text-center">
          <h2 className="text-3xl font-bold tracking-tight sm:text-4xl">How it works</h2>
          <p className="mt-3 text-muted-foreground">
            The same system your community already uses — with an escrow everyone can audit.
          </p>
        </div>
        <div className="mt-12 grid gap-6 sm:grid-cols-3">
          {steps.map((s, i) => (
            <Card key={s.title} className="card-hover">
              <CardHeader>
                <div className="flex h-10 w-10 items-center justify-center rounded-full bg-accent font-bold text-accent-foreground">
                  {i + 1}
                </div>
                <CardTitle className="mt-2">{s.title}</CardTitle>
              </CardHeader>
              <CardContent>
                <CardDescription className="text-sm leading-relaxed">{s.body}</CardDescription>
              </CardContent>
            </Card>
          ))}
        </div>
      </section>

      {/* Two modes */}
      <section className="border-y bg-card">
        <div className="container grid gap-8 py-16 sm:grid-cols-2 sm:py-20">
          <div className="rounded-lg border-2 border-primary/20 bg-secondary/50 p-8">
            <h3 className="text-2xl font-bold text-primary">Classic Akawo</h3>
            <p className="mt-1 text-sm font-medium text-gold-foreground">Collector-led savings plan</p>
            <p className="mt-4 leading-relaxed text-muted-foreground">
              A trusted collector hosts the plan. Members contribute a fixed amount every day,
              week or month. At the end of the cycle everyone withdraws their full savings minus a
              small, capped collector fee (max 1%).
            </p>
            <Button asChild className="mt-6">
              <Link href="/create">Create a plan</Link>
            </Button>
          </div>
          <div className="rounded-lg border-2 border-gold/40 bg-accent/30 p-8">
            <h3 className="text-2xl font-bold text-primary">Isusu / Ajo</h3>
            <p className="mt-1 text-sm font-medium text-gold-foreground">Rotating savings group</p>
            <p className="mt-4 leading-relaxed text-muted-foreground">
              Pure peer-to-peer. N members contribute every cycle and one member receives the
              whole pot each round — in a fixed transparent order, or by on-chain lottery. No
              coordinator ever holds the funds.
            </p>
            <Button asChild variant="gold" className="mt-6">
              <Link href="/create?mode=group">Create a group</Link>
            </Button>
          </div>
        </div>
      </section>

      {/* Features */}
      <section className="container py-16 sm:py-24">
        <div className="mx-auto max-w-2xl text-center">
          <h2 className="text-3xl font-bold tracking-tight sm:text-4xl">
            Trust the code, not the collector
          </h2>
          <p className="mt-3 text-muted-foreground">
            Every contribution, fee and payout is on-chain, verifiable, and exportable.
          </p>
        </div>
        <div className="mt-12 grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
          {features.map((f) => (
            <Card key={f.title} className="card-hover">
              <CardHeader>
                <div className="flex h-10 w-10 items-center justify-center rounded-md bg-primary/10">
                  <f.icon className="h-5 w-5 text-primary" />
                </div>
                <CardTitle className="mt-3 text-lg">{f.title}</CardTitle>
              </CardHeader>
              <CardContent>
                <CardDescription className="leading-relaxed">{f.body}</CardDescription>
              </CardContent>
            </Card>
          ))}
        </div>
      </section>

      {/* CTA */}
      <section className="container pb-20">
        <div className="hero-gradient rounded-2xl p-10 text-center text-white sm:p-16">
          <h2 className="text-3xl font-bold tracking-tight sm:text-4xl">
            Ready to start your circle?
          </h2>
          <p className="mx-auto mt-3 max-w-xl text-white/80">
            Connect a wallet on Arc, create your first plan in under a minute, and share the link
            with your group.
          </p>
          <div className="mt-8 flex flex-col items-center justify-center gap-3 sm:flex-row">
            <Button asChild size="lg" variant="gold">
              <Link href="/dashboard">Open dashboard</Link>
            </Button>
            <Button asChild size="lg" className="border border-white/30 bg-white/10 text-white hover:bg-white/20">
              <Link href="https://faucet.circle.com" target="_blank" rel="noreferrer">
                Get testnet USDC ↗
              </Link>
            </Button>
          </div>
        </div>
      </section>
    </>
  );
}
