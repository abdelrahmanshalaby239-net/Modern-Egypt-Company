import type { Metadata } from "next";

import { getManualPostingAccounts } from "@/lib/accounts";
import { requireUser } from "@/lib/auth";
import { formatDate, yearStartIso } from "@/lib/format";
import { ACCOUNT_TYPES, ACCOUNT_TYPE_LABELS } from "@/lib/labels";
import { postOpeningBalances } from "./actions";
import { OpeningBalancesForm } from "./opening-balances-form";
import { OpeningTabs } from "./opening-tabs";
import { PostedOpening } from "./posted-opening";

export const metadata: Metadata = { title: "الأرصدة الافتتاحية" };

export default async function OpeningBalancesPage() {
  const { supabase } = await requireUser();

  // جزء الحسابات النشط (غير الملغى). أرصدة الأطراف جزء مستقل لا يمنعه.
  const { data: openings } = await supabase.rpc("active_openings");
  const active = (openings ?? []).find((o) => o.part === "accounts");

  const [accounts, { data: capital }] = active
    ? [[], { data: null }]
    : await Promise.all([
        getManualPostingAccounts(supabase),
        supabase
          .from("system_accounts")
          .select("account:accounts(code, name)")
          .eq("key", "capital")
          .single(),
      ]);

  const groups = ACCOUNT_TYPES.map((type) => ({
    title: ACCOUNT_TYPE_LABELS[type],
    rows: accounts
      .filter((a) => a.type === type)
      .map((a) => ({ key: `a${a.id}`, label: `${a.code} - ${a.name}`, line: { account_id: String(a.id) } })),
  }));

  return (
    <div className="grid max-w-4xl gap-4">
      <h1 className="text-xl font-bold">الأرصدة الافتتاحية</h1>
      <OpeningTabs active="accounts" />
      {active ? (
        <PostedOpening title="أرصدة الحسابات الافتتاحية" entry={active} />
      ) : (
        <>
          <p className="text-sm text-muted-foreground">
            أرصدة الحسابات في أول المدة. أرصدة العملاء والموردين ومخزون أول المدة لها تبويبات
            مستقلة.
          </p>
          <OpeningBalancesForm
            groups={groups}
            columnLabel="الحساب"
            defaultDate={formatDate(yearStartIso())}
            capitalLabel={capital?.account ? `${capital.account.code} - ${capital.account.name}` : "رأس المال"}
            action={postOpeningBalances}
          />
        </>
      )}
    </div>
  );
}
