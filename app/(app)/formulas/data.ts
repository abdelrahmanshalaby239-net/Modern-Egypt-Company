import type { createClient } from "@/lib/supabase/server";
import { ITEM_TYPE_LABELS, isItemType } from "@/lib/labels";
import type { FormulaItem } from "./formula-form";

type Client = Awaited<ReturnType<typeof createClient>>;

// المنتجات التامة والمواد (خام وتعبئة) بوحداتها ومتوسط تكلفتها الحالي، لنموذج الوصفة
export async function loadFormulaItems(supabase: Client) {
  const [{ data: items }, { data: units }, { data: balances }] = await Promise.all([
    supabase.from("items").select("id, code, name, type, unit, is_active").order("code"),
    supabase.from("item_units").select("id, item_id, name, factor::text, is_active").order("id"),
    supabase.rpc("stock_balances"),
  ]);
  const avgOf = new Map((balances ?? []).map((b) => [b.item_id, b.avg_cost]));
  const toItem = (i: NonNullable<typeof items>[number]): FormulaItem => ({
    id: i.id,
    code: i.code,
    name: i.name,
    unit: i.unit,
    typeLabel: isItemType(i.type) ? ITEM_TYPE_LABELS[i.type] : i.type,
    is_active: i.is_active,
    avg_cost: avgOf.get(i.id) ?? "0",
    units: (units ?? [])
      .filter((u) => u.item_id === i.id)
      .map(({ id, name, factor, is_active }) => ({ id, name, factor, is_active })),
  });
  return {
    products: (items ?? []).filter((i) => i.type === "finished_good").map(toItem),
    materials: (items ?? []).filter((i) => i.type !== "finished_good").map(toItem),
  };
}
