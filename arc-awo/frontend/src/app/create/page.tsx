"use client";

import { Suspense } from "react";
import { useSearchParams } from "next/navigation";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { CreateGroupForm, CreatePlanForm } from "@/components/forms";
import { isConfigured } from "@/lib/contracts";
import { ConfigNotice } from "@/components/ConfigNotice";

function CreateInner() {
  const params = useSearchParams();
  const initial = params.get("mode") === "group" ? "group" : "plan";

  return (
    <div className="container max-w-3xl py-10">
      <h1 className="text-2xl font-bold tracking-tight sm:text-3xl">Create</h1>
      <p className="mt-1 text-muted-foreground">
        Lock the rules on-chain before a single naira-equivalent moves. Fees are capped by the
        factory — members can verify before joining.
      </p>

      <Tabs defaultValue={initial} className="mt-8">
        <TabsList className="grid w-full grid-cols-2">
          <TabsTrigger value="plan">Akawo plan</TabsTrigger>
          <TabsTrigger value="group">Isusu group</TabsTrigger>
        </TabsList>
        <TabsContent value="plan">
          <CreatePlanForm />
        </TabsContent>
        <TabsContent value="group">
          <CreateGroupForm />
        </TabsContent>
      </Tabs>
    </div>
  );
}

export default function CreatePage() {
  if (!isConfigured) return <ConfigNotice />;
  return (
    <Suspense>
      <CreateInner />
    </Suspense>
  );
}
