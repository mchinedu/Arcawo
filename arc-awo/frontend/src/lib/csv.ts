export type CsvRow = Record<string, string | number | bigint>;

/** Build a CSV document from rows and trigger a browser download. */
export function downloadCsv(filename: string, rows: CsvRow[]) {
  if (rows.length === 0) return;
  const headers = Object.keys(rows[0]);
  const escape = (v: unknown) => {
    const s = String(v ?? "");
    return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  const lines = [headers.join(","), ...rows.map((r) => headers.map((h) => escape(r[h])).join(","))];
  const blob = new Blob([lines.join("\n")], { type: "text/csv;charset=utf-8;" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

/** Render an HTML receipt and open the browser print dialog (→ PDF). */
export function printReceipt(title: string, bodyHtml: string) {
  const win = window.open("", "_blank");
  if (!win) return;
  win.document.write(`<!doctype html><html><head><title>${title}</title>
<style>
  body { font-family: ui-sans-serif, system-ui, sans-serif; padding: 32px; color: #0c1f16; }
  h1 { font-size: 20px; margin: 0 0 4px; }
  .sub { color: #4b6357; margin-bottom: 24px; font-size: 13px; }
  table { width: 100%; border-collapse: collapse; font-size: 13px; }
  td, th { text-align: left; padding: 8px 10px; border-bottom: 1px solid #d7e3db; }
  th { color: #4b6357; font-weight: 600; }
  .brand { color: #14532d; font-weight: 700; letter-spacing: 0.5px; font-size: 12px; margin-bottom: 16px; }
</style></head><body>
  <div class="brand">ARC-AWO · ON-CHAIN RECEIPT · ARC USDC</div>
  <h1>${title}</h1>
  <div class="sub">Generated ${new Date().toLocaleString()} · amounts in USDC (6 decimals)</div>
  ${bodyHtml}
  <script>window.onload = () => window.print();</script>
</body></html>`);
  win.document.close();
}
