import Link from "next/link";
import { AlertTriangle } from "lucide-react";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

export function ConfigNotice() {
  return (
    <div className="container flex max-w-2xl py-20">
      <Card className="w-full">
        <CardHeader>
          <div className="flex items-center gap-2">
            <AlertTriangle className="h-5 w-5 text-gold" />
            <CardTitle>Deployment not configured</CardTitle>
          </div>
          <CardDescription>
            The factory address has not been set for this frontend build.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-3 text-sm text-muted-foreground">
          <p>
            1. Deploy the contracts:{" "}
            <code className="rounded bg-secondary px-1.5 py-0.5 text-xs">
              forge script script/Deploy.s.sol --rpc-url arc_testnet --broadcast
            </code>
          </p>
          <p>
            2. Set{" "}
            <code className="rounded bg-secondary px-1.5 py-0.5 text-xs">
              NEXT_PUBLIC_FACTORY_ADDRESS
            </code>{" "}
            and{" "}
            <code className="rounded bg-secondary px-1.5 py-0.5 text-xs">
              NEXT_PUBLIC_REPUTATION_ADDRESS
            </code>{" "}
            in <code className="rounded bg-secondary px-1.5 py-0.5 text-xs">.env.local</code>.
          </p>
          <p>
            3. Restart the dev server. See the{" "}
            <Link href="/" className="font-medium text-primary hover:underline">
              README
            </Link>{" "}
            for full instructions.
          </p>
        </CardContent>
      </Card>
    </div>
  );
}
