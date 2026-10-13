import { Coins } from "lucide-react";

export function Footer() {
  return (
    <footer className="border-t bg-card">
      <div className="container flex flex-col items-start justify-between gap-6 py-10 sm:flex-row sm:items-center">
        <div>
          <div className="flex items-center gap-2 font-bold text-primary">
            <Coins className="h-5 w-5" />
            Arc-awo
          </div>
          <p className="mt-2 max-w-sm text-sm text-muted-foreground">
            Decentralized thrift & rotating savings (Akawo · Isusu · Ajo) on Arc — settled in native
            USDC with full on-chain transparency.
          </p>
        </div>
        <div className="grid grid-cols-2 gap-x-10 gap-y-2 text-sm">
          <a href="/create" className="text-muted-foreground hover:text-foreground">Create plan</a>
          <a href="/browse" className="text-muted-foreground hover:text-foreground">Browse groups</a>
          <a href="/dashboard" className="text-muted-foreground hover:text-foreground">Dashboard</a>
          <a href="https://docs.arc.io" target="_blank" rel="noreferrer" className="text-muted-foreground hover:text-foreground">
            Arc docs ↗
          </a>
        </div>
      </div>
      <div className="border-t py-4">
        <p className="container text-xs text-muted-foreground">
          Contracts are non-upgradeable escrows. Funds can only move via the rules written in the
          smart contracts. Contributed amounts are shown in USDC (6-decimal app units).
        </p>
      </div>
    </footer>
  );
}
