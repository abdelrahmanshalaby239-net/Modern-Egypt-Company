import type { createClient } from "@/lib/supabase/server";

type Client = Awaited<ReturnType<typeof createClient>>;

export type PostingAccount = { id: number; code: string; name: string; type: string };

// العملاء والموردون يتحركون من السندات والأرصدة الافتتاحية للأطراف، والمخزون من مستنداته فقط
const RESTRICTED_KEYS = [
  "receivables",
  "payables",
  "inventory_raw",
  "inventory_packaging",
  "inventory_finished",
];

// إيرادات المبيعات وتكلفتها وفروقات الجرد تتحرك من مستنداتها فقط، فلا تُستخدم في السندات
const VOUCHER_RESTRICTED_KEYS = [...RESTRICTED_KEYS, "sales_revenue", "cogs", "inventory_adjustment"];

// الحسابات المتاحة للقيود اليدوية والأرصدة الافتتاحية: فرعية نشطة، بدون الحسابات المقيّدة.
// نفس القاعدة مفروضة في قاعدة البيانات؛ هذا لعرض الاختيارات الصحيحة فقط.
export function getManualPostingAccounts(supabase: Client): Promise<PostingAccount[]> {
  return postingAccountsExcept(supabase, RESTRICTED_KEYS);
}

// «حساب آخر» في سندات القبض والصرف (نفس قاعدة trigger السند في قاعدة البيانات)
export function getVoucherCounterAccounts(supabase: Client): Promise<PostingAccount[]> {
  return postingAccountsExcept(supabase, VOUCHER_RESTRICTED_KEYS);
}

async function postingAccountsExcept(supabase: Client, keys: string[]): Promise<PostingAccount[]> {
  const [{ data: accounts }, { data: system }] = await Promise.all([
    supabase
      .from("accounts")
      .select("id, code, name, type")
      .eq("is_postable", true)
      .eq("is_active", true)
      .order("code"),
    supabase.from("system_accounts").select("key, account_id"),
  ]);
  const restricted = new Set(
    (system ?? []).filter((s) => keys.includes(s.key)).map((s) => s.account_id),
  );
  return (accounts ?? []).filter((a) => !restricted.has(a.id));
}

// الخزائن والبنوك النشطة (لسندات القبض والصرف)
export async function getTreasuryAccounts(supabase: Client): Promise<PostingAccount[]> {
  const { data } = await supabase
    .from("accounts")
    .select("id, code, name, type")
    .eq("is_treasury", true)
    .eq("is_postable", true)
    .eq("is_active", true)
    .order("code");
  return data ?? [];
}
