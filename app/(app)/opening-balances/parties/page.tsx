import type { Metadata } from "next";
import Link from "next/link";

import { requireUser } from "@/lib/auth";
import { formatDate, yearStartIso } from "@/lib/format";
import { OpeningBalancesForm } from "../opening-balances-form";
import { OpeningTabs } from "../opening-tabs";
import { PostedOpening } from "../posted-opening";
import { postPartyOpeningBalances } from "./actions";

export const metadata: Metadata = { title: "أرصدة العملاء والموردين الافتتاحية" };

export default async function PartyOpeningBalancesPage() {
  const { supabase } = await requireUser();

  // جزء الأطراف النشط (غير الملغى). أرصدة الحسابات جزء مستقل لا يمنعه.
  const { data: openings } = await supabase.rpc("active_openings");
  const active = (openings ?? []).find((o) => o.part === "parties");

  const [{ data: customers }, { data: suppliers }, { data: capital }] = active
    ? [{ data: [] }, { data: [] }, { data: null }]
    : await Promise.all([
        supabase.from("customers").select("id, name").eq("is_active", true).order("name"),
        supabase.from("suppliers").select("id, name").eq("is_active", true).order("name"),
        supabase
          .from("system_accounts")
          .select("account:accounts(code, name)")
          .eq("key", "capital")
          .single(),
      ]);

  const groups = [
    {
      title: "العملاء",
      rows: (customers ?? []).map((c) => ({ key: `c${c.id}`, label: c.name, line: { customer_id: String(c.id) } })),
    },
    {
      title: "الموردين",
      rows: (suppliers ?? []).map((s) => ({ key: `s${s.id}`, label: s.name, line: { supplier_id: String(s.id) } })),
    },
  ];
  const hasParties = groups.some((g) => g.rows.length > 0);

  return (
    <div className="grid max-w-4xl gap-4">
      <h1 className="text-xl font-bold">الأرصدة الافتتاحية</h1>
      <OpeningTabs active="parties" />
      {active ? (
        <PostedOpening title="أرصدة العملاء والموردين الافتتاحية" entry={active} />
      ) : !hasParties ? (
        <p className="text-sm text-muted-foreground">
          أضف{" "}
          <Link href="/customers" className="font-semibold text-foreground underline">
            العملاء
          </Link>{" "}
          و
          <Link href="/suppliers" className="font-semibold text-foreground underline">
            الموردين
          </Link>{" "}
          أولًا، ثم سجّل أرصدتهم هنا.
        </p>
      ) : (
        <>
          <p className="text-sm text-muted-foreground">
            رصيد كل عميل ومورد في أول المدة، في قيد واحد على حسابي العملاء والموردين. المستحق على
            العميل في المدين، والمستحق للمورد في الدائن (والدفعات المقدمة بالعكس).
          </p>
          <OpeningBalancesForm
            groups={groups}
            columnLabel="الطرف"
            defaultDate={formatDate(yearStartIso())}
            capitalLabel={capital?.account ? `${capital.account.code} - ${capital.account.name}` : "رأس المال"}
            action={postPartyOpeningBalances}
          />
        </>
      )}
    </div>
  );
}
