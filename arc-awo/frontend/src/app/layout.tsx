import type { Metadata, Viewport } from "next";
import { Providers } from "./providers";
import { Header } from "@/components/Header";
import { Footer } from "@/components/Footer";
import "./globals.css";

export const metadata: Metadata = {
  title: "Arc-awo — Decentralized Thrift & Rotating Savings on Arc",
  description:
    "Save daily, weekly or monthly in USDC with full transparency. Classic Akawo collector plans and peer-to-peer Isusu rotating savings — powered by Arc's native USDC.",
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  themeColor: "hsl(152 60% 24%)",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="min-h-screen font-sans antialiased">
        <Providers>
          <div className="flex min-h-screen flex-col">
            <Header />
            <main className="flex-1">{children}</main>
            <Footer />
          </div>
        </Providers>
      </body>
    </html>
  );
}
