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

// الحسابات المتاحة للقيود اليدوية والأرصدة الافتتاحية: فرعية نشطة، بدون الحسابات المقيّدة.
// نفس القاعدة مفروضة في قاعدة البيانات؛ هذا لعرض الاختيارات الصحيحة فقط.
export async function getManualPostingAccounts(supabase: Client): Promise<PostingAccount[]> {
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
    (system ?? []).filter((s) => RESTRICTED_KEYS.includes(s.key)).map((s) => s.account_id),
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
