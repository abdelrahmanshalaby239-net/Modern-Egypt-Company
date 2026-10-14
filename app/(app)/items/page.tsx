import type { Metadata } from "next";
import Link from "next/link";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { requireUser } from "@/lib/auth";
import { ITEM_TYPE_LABELS, isItemType } from "@/lib/labels";
import { formatAmount } from "@/lib/money";
import { formatQty } from "@/lib/quantity";
import { DeleteItemButton } from "./delete-item-button";
import { ItemDialog } from "./item-dialog";

export const metadata: Metadata = { title: "الأصناف" };

export default async function ItemsPage({ searchParams }: PageProps<"/items">) {
  const { supabase } = await requireUser();
  const q = String((await searchParams).q ?? "").trim();

  const [{ data: items }, { data: balances }] = await Promise.all([
    supabase.from("items").select("id, code, name, type, unit, sale_price::text, is_active").order("code"),
    supabase.rpc("stock_balances"),
  ]);
  const stockOf = new Map((balances ?? []).map((b) => [b.item_id, b]));
  const rows = (items ?? []).filter((i) => !q || i.code.includes(q) || i.name.includes(q));

  return (
    <div className="grid gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-xl font-bold">الأصناف</h1>
        <ItemDialog />
      </div>

      <form className="flex max-w-md gap-2">
        <Input name="q" defaultValue={q} placeholder="بحث بالكود أو الاسم" />
        <Button type="submit" variant="outline">
          بحث
        </Button>
      </form>

      <div className="rounded-lg border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>الكود</TableHead>
              <TableHead>الاسم</TableHead>
              <TableHead>النوع</TableHead>
              <TableHead>الوحدة</TableHead>
              <TableHead className="text-end">سعر البيع</TableHead>
              <TableHead className="text-end">الرصيد</TableHead>
              <TableHead>الحالة</TableHead>
              <TableHead />
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.map((item) => {
              const stock = stockOf.get(item.id);
              // للصنف حركات سابقة لو له رصيد أو متوسط تكلفة (المتوسط يبقى بعد نفاد الرصيد)
              const used = !!stock && (stock.qty !== "0.000" || stock.avg_cost !== "0.0000");
              return (
                <TableRow key={item.id}>
                  <TableCell dir="ltr" className="text-end font-mono">
                    {item.code}
                  </TableCell>
                  <TableCell className="font-semibold">{item.name}</TableCell>
                  <TableCell>{isItemType(item.type) ? ITEM_TYPE_LABELS[item.type] : item.type}</TableCell>
                  <TableCell>{item.unit}</TableCell>
                  <TableCell dir="ltr" className="text-start tabular-nums">
                    {formatAmount(item.sale_price)}
                  </TableCell>
                  <TableCell dir="ltr" className="text-start tabular-nums">
                    {formatQty(stock?.qty)}
                  </TableCell>
                  <TableCell className={item.is_active ? "" : "text-muted-foreground"}>
                    {item.is_active ? "نشط" : "معطّل"}
                  </TableCell>
                  <TableCell>
                    <div className="flex justify-end gap-2">
                      <Button asChild variant="outline" size="sm">
                        <Link href={`/inventory/movements?item=${item.id}`}>حركة الصنف</Link>
                      </Button>
                      <ItemDialog item={item} used={used} />
                      <DeleteItemButton id={item.id} name={item.name} />
                    </div>
                  </TableCell>
                </TableRow>
              );
            })}
            {rows.length === 0 && (
              <TableRow>
                <TableCell colSpan={8} className="py-6 text-center text-muted-foreground">
                  {q ? "لا توجد نتائج مطابقة." : "لا توجد أصناف بعد."}
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </div>
    </div>
  );
}
