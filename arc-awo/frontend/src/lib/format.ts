import { formatUnits, parseUnits } from "viem";

/** Format 6-dec USDC app units as a dollar string: 1980000n → "1.98". */
export function formatUsdc(amount: bigint, withSymbol = true): string {
  const s = formatUnits(amount, 6);
  const [int, frac] = s.split(".");
  const pretty = frac ? `${int}.${frac.slice(0, 2).replace(/0+$/, "").replace(/\.$/, "")}` : int;
  return withSymbol ? `$${pretty}` : pretty;
}

/** Parse a human USDC amount ("12.5") into 6-dec app units. */
export function parseUsdc(input: string): bigint {
  return parseUnits(input || "0", 6);
}

export function shortAddress(addr?: string): string {
  if (!addr) return "—";
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

export function formatDate(ts: number | bigint): string {
  return new Date(Number(ts) * 1000).toLocaleString(undefined, {
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

export function formatDateShort(ts: number | bigint): string {
  return new Date(Number(ts) * 1000).toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

export const FREQUENCY_LABELS = ["Daily", "Weekly", "Monthly"] as const;
export const FREQUENCY_SECONDS = [86400n, 7n * 86400n, 30n * 86400n] as const;

export function periodLengthSeconds(frequency: number): bigint {
  return FREQUENCY_SECONDS[frequency] ?? FREQUENCY_SECONDS[1];
}

/** Period index → window start/end timestamps. */
export function periodWindow(startTime: bigint, frequency: number, period: number) {
  const p = periodLengthSeconds(frequency);
  const start = startTime + BigInt(period) * p;
  return { start, end: start + p };
}

export function roundWindow(startTime: bigint, frequency: number, round: number) {
  return periodWindow(startTime, frequency, round);
}

export const PAYOUT_MODES = ["Fixed order", "Lottery"] as const;

export function statusBadge(complete: boolean, ended: boolean, active: boolean) {
  if (complete || ended) return { label: "Completed", tone: "muted" as const };
  if (active) return { label: "Active", tone: "green" as const };
  return { label: "Starting", tone: "gold" as const };
}

/** BPS display: 100 → "1%". */
export function bpsLabel(bps: number): string {
  return `${(bps / 100).toFixed(bps % 100 === 0 ? 0 : 2)}%`;
}
