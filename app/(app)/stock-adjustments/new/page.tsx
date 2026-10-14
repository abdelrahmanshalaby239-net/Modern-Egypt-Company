import type { Metadata } from "next";
import Link from "next/link";

import { requireUser } from "@/lib/auth";
import { formatDate, todayIso } from "@/lib/format";
import { ITEM_TYPE_LABELS, isItemType } from "@/lib/labels";
import { AdjustmentForm } from "./adjustment-form";

export const metadata: Metadata = { title: "تسوية جرد جديدة" };

export default async function NewStockAdjustmentPage() {
  const { supabase } = await requireUser();
  const { data: balances } = await supabase.rpc("stock_balances");
  const items = (balances ?? [])
    .filter((b) => b.is_active)
    .map((b) => ({
      id: b.item_id,
      code: b.code,
      name: b.name,
      unit: b.unit,
      typeLabel: isItemType(b.type) ? ITEM_TYPE_LABELS[b.type] : b.type,
      qty: b.qty,
      value: b.value,
      avg_cost: b.avg_cost,
    }));

  return (
    <div className="grid max-w-3xl gap-4">
      <h1 className="text-xl font-bold">تسوية جرد جديدة</h1>
      {items.length === 0 ? (
        <p className="text-sm text-muted-foreground">
          أضف{" "}
          <Link href="/items" className="font-semibold text-foreground underline">
            الأصناف
          </Link>{" "}
          أولًا.
        </p>
      ) : (
        <>
          <p className="text-sm text-muted-foreground">
            أدخل الكمية الفعلية من الجرد لصنف واحد. الفرق عن رصيد النظام يُسجَّل على حساب فروقات جرد
            المخزون: العجز بمتوسط التكلفة الحالي، والزيادة بآخر متوسط تكلفة.
          </p>
          <AdjustmentForm defaultDate={formatDate(todayIso())} items={items} />
        </>
      )}
    </div>
  );
}
