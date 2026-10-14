import type { Metadata } from "next";
import Link from "next/link";

import { getTreasuryAccounts } from "@/lib/accounts";
import { requireUser } from "@/lib/auth";
import { formatDate, todayIso } from "@/lib/format";
import { SalesForm } from "./sales-form";

export const metadata: Metadata = { title: "فاتورة مبيعات جديدة" };

export default async function NewSalesPage() {
  const { supabase } = await requireUser();
  const [{ data: customers }, { data: items }, { data: balances }, treasuries, { data: customerBalances }, { data: units }] =
    await Promise.all([
      supabase.from("customers").select("id, name").eq("is_active", true).order("name"),
      // فاتورة المبيعات للمنتج التام فقط
      supabase
        .from("items")
        .select("id, code, name, unit, barcode, sale_price::text, default_sale_unit_id")
        .eq("is_active", true)
        .eq("type", "finished_good")
        .order("code"),
      supabase.rpc("stock_balances"),
      getTreasuryAccounts(supabase),
      supabase.rpc("party_balances", { p_party_kind: "customer" }),
      supabase
        .from("item_units")
        .select("id, item_id, name, factor::text, sale_price::text")
        .eq("is_active", true)
        .order("id"),
    ]);
  const qtyOf = new Map((balances ?? []).map((b) => [b.item_id, b.qty]));
  const balanceOf = new Map((customerBalances ?? []).map((b) => [b.party_id, b.balance]));

  const missing = (customers ?? []).length === 0 || (items ?? []).length === 0;

  return (
    <div className="grid max-w-5xl gap-4">
      <Link href="/sales" className="text-sm text-muted-foreground underline-offset-4 hover:underline">
        ← فواتير المبيعات
      </Link>
      <h1 className="text-xl font-bold">فاتورة مبيعات جديدة</h1>
      {missing ? (
        <p className="text-sm text-muted-foreground">
          أضف{" "}
          <Link href="/customers" className="font-semibold text-foreground underline">
            العملاء
          </Link>{" "}
          و
          <Link href="/items" className="font-semibold text-foreground underline">
            منتجًا تامًا
          </Link>{" "}
          أولًا.
        </p>
      ) : (
        <SalesForm
          defaultDate={formatDate(todayIso())}
          customers={(customers ?? []).map((c) => ({ ...c, balance: balanceOf.get(c.id) ?? "0.00" }))}
          items={(items ?? []).map((i) => ({
            id: i.id,
            code: i.code,
            name: i.name,
            unit: i.unit,
            barcode: i.barcode ?? "",
            sale_price: i.sale_price ?? "",
            qty: qtyOf.get(i.id) ?? "0",
            default_unit_id: i.default_sale_unit_id ? String(i.default_sale_unit_id) : "",
            units: (units ?? [])
              .filter((u) => u.item_id === i.id)
              .map(({ id, name, factor, sale_price }) => ({ id, name, factor, sale_price: sale_price ?? "" })),
          }))}
          treasuries={treasuries}
        />
      )}
    </div>
  );
}
