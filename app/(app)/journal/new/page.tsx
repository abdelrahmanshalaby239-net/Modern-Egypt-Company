import type { Metadata } from "next";

import { getManualPostingAccounts } from "@/lib/accounts";
import { requireUser } from "@/lib/auth";
import { formatDate, todayIso } from "@/lib/format";
import { JournalEntryForm } from "./journal-entry-form";

export const metadata: Metadata = { title: "قيد يدوي جديد" };

export default async function NewJournalEntryPage() {
  const { supabase } = await requireUser();
  const accounts = await getManualPostingAccounts(supabase);

  return (
    <div className="grid max-w-5xl gap-4">
      <h1 className="text-xl font-bold">قيد يدوي جديد</h1>
      <JournalEntryForm accounts={accounts} defaultDate={formatDate(todayIso())} />
    </div>
  );
}
