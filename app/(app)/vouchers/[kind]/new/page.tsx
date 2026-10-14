import type { Metadata } from "next";
import { notFound } from "next/navigation";

import { Alert } from "@/components/ui/alert";
import { getManualPostingAccounts, getTreasuryAccounts } from "@/lib/accounts";
import { requireUser } from "@/lib/auth";
import { formatDate, todayIso } from "@/lib/format";
import { VOUCHER_LABELS, isVoucherKind } from "@/lib/labels";
import { VoucherForm } from "./voucher-form";

export async function generateMetadata({ params }: PageProps<"/vouchers/[kind]/new">): Promise<Metadata> {
  const { kind } = await params;
  return { title: isVoucherKind(kind) ? `${VOUCHER_LABELS[kind].one} جديد` : "سند جديد" };
}

export default async function NewVoucherPage({ params }: PageProps<"/vouchers/[kind]/new">) {
  const { kind } = await params;
  if (!isVoucherKind(kind)) notFound();

  const { supabase } = await requireUser();
  const [treasuries, accounts, { data: customers }, { data: suppliers }] = await Promise.all([
    getTreasuryAccounts(supabase),
    getManualPostingAccounts(supabase),
    supabase.from("customers").select("id, name").eq("is_active", true).order("name"),
    supabase.from("suppliers").select("id, name").eq("is_active", true).order("name"),
  ]);

  return (
    <div className="grid max-w-3xl gap-4">
      <h1 className="text-xl font-bold">{VOUCHER_LABELS[kind].one} جديد</h1>
      {treasuries.length === 0 ? (
        <Alert>لا توجد خزينة أو بنك نشط. حدّد حساب الخزينة من دليل الحسابات أولًا.</Alert>
      ) : (
        <VoucherForm
          kind={kind}
          defaultDate={formatDate(todayIso())}
          treasuries={treasuries}
          accounts={accounts}
          customers={customers ?? []}
          suppliers={suppliers ?? []}
        />
      )}
    </div>
  );
}
