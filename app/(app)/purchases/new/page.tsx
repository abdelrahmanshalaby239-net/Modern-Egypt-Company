import type { Metadata } from "next";
import Link from "next/link";

import { getTreasuryAccounts } from "@/lib/accounts";
import { requireUser } from "@/lib/auth";
import { formatDate, todayIso } from "@/lib/format";
import { ITEM_TYPE_LABELS, isItemType } from "@/lib/labels";
import { PurchaseForm } from "./purchase-form";

export const metadata: Metadata = { title: "فاتورة مشتريات جديدة" };

export default async function NewPurchasePage() {
  const { supabase } = await requireUser();
  const [{ data: suppliers }, { data: items }, { data: balances }, treasuries, { data: supplierBalances }] =
    await Promise.all([
    supabase.from("suppliers").select("id, name").eq("is_active", true).order("name"),
    // فاتورة المشتريات للخامات ومواد التعبئة فقط (المنتج التام يدخل بالإنتاج)
    supabase
      .from("items")
      .select("id, code, name, type, unit")
      .eq("is_active", true)
      .in("type", ["raw_material", "packaging"])
      .order("code"),
    supabase.rpc("stock_balances"),
    getTreasuryAccounts(supabase),
    supabase.rpc("party_balances", { p_party_kind: "supplier" }),
  ]);
  const qtyOf = new Map((balances ?? []).map((b) => [b.item_id, b.qty]));
  const balanceOf = new Map((supplierBalances ?? []).map((b) => [b.party_id, b.balance]));

  const missing = (suppliers ?? []).length === 0 || (items ?? []).length === 0;

  return (
    <div className="grid max-w-4xl gap-4">
      <h1 className="text-xl font-bold">فاتورة مشتريات جديدة</h1>
      {missing ? (
        <p className="text-sm text-muted-foreground">
          أضف{" "}
          <Link href="/suppliers" className="font-semibold text-foreground underline">
            الموردين
          </Link>{" "}
          و
          <Link href="/items" className="font-semibold text-foreground underline">
            الأصناف
          </Link>{" "}
          (خامات أو مواد تعبئة) أولًا.
        </p>
      ) : (
        <PurchaseForm
          defaultDate={formatDate(todayIso())}
          suppliers={(suppliers ?? []).map((s) => ({ ...s, balance: balanceOf.get(s.id) ?? "0.00" }))}
          items={(items ?? []).map((i) => ({
            id: i.id,
            code: i.code,
            name: i.name,
            unit: i.unit,
            typeLabel: isItemType(i.type) ? ITEM_TYPE_LABELS[i.type] : i.type,
            qty: qtyOf.get(i.id) ?? "0",
          }))}
          treasuries={treasuries}
        />
      )}
    </div>
  );
}
