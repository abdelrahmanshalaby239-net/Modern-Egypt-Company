import type { Metadata } from "next";
import Link from "next/link";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { NativeSelect } from "@/components/ui/native-select";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { requireUser } from "@/lib/auth";
import { ITEM_TYPES, ITEM_TYPE_LABELS, isItemType } from "@/lib/labels";
import { formatQty, formatUnitCost, parseQty } from "@/lib/quantity";
import { DeleteItemButton } from "./delete-item-button";

export const metadata: Metadata = { title: "الأصناف" };

export default async function ItemsPage({ searchParams }: PageProps<"/items">) {
  const { supabase } = await requireUser();
  const params = await searchParams;
  const q = String(params.q ?? "").trim();
  const categoryFilter = String(params.category ?? "");
  const typeFilter = String(params.type ?? "");

  const [{ data: items }, { data: balances }, { data: categories }] = await Promise.all([
    supabase
      .from("items")
      .select("id, code, name, type, unit, barcode, default_cost::text, min_stock::text, is_active, category_id")
      .order("code"),
    supabase.rpc("stock_balances"),
    supabase.from("item_categories").select("id, name").order("name"),
  ]);
  const stockOf = new Map((balances ?? []).map((b) => [b.item_id, b]));
  const categoryName = new Map((categories ?? []).map((c) => [c.id, c.name]));
  const rows = (items ?? []).filter(
    (i) =>
      (!q || i.code.includes(q) || i.name.includes(q) || i.barcode === q) &&
      (!categoryFilter || String(i.category_id ?? "none") === categoryFilter) &&
      (!typeFilter || i.type === typeFilter),
  );

  return (
    <div className="grid gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-xl font-bold">الأصناف</h1>
        <div className="flex gap-2">
          <Button asChild variant="outline">
            <Link href="/items/categories">التصنيفات</Link>
          </Button>
          <Button asChild>
            <Link href="/items/new">إضافة صنف</Link>
          </Button>
        </div>
      </div>

      <form className="flex flex-wrap items-end gap-3">
        <div className="grid gap-1">
          <Label htmlFor="q">بحث</Label>
          <Input id="q" name="q" defaultValue={q} placeholder="الكود أو الاسم أو الباركود" className="w-60" />
        </div>
        <div className="grid gap-1">
          <Label htmlFor="type">النوع</Label>
          <NativeSelect id="type" name="type" defaultValue={typeFilter} className="w-44">
            <option value="">كل الأنواع</option>
            {ITEM_TYPES.map((t) => (
              <option key={t} value={t}>
                {ITEM_TYPE_LABELS[t]}
              </option>
            ))}
          </NativeSelect>
        </div>
        <div className="grid gap-1">
          <Label htmlFor="category">التصنيف</Label>
          <NativeSelect id="category" name="category" defaultValue={categoryFilter} className="w-44">
            <option value="">كل التصنيفات</option>
            <option value="none">بدون تصنيف</option>
            {(categories ?? []).map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </NativeSelect>
        </div>
        <Button type="submit" variant="outline">
          عرض
        </Button>
      </form>

      <div className="rounded-lg border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>الكود</TableHead>
              <TableHead>الاسم</TableHead>
              <TableHead>النوع</TableHead>
              <TableHead>التصنيف</TableHead>
              <TableHead>الوحدة الأساسية</TableHead>
              <TableHead className="text-end">التكلفة الافتراضية</TableHead>
              <TableHead className="text-end">متوسط التكلفة الفعلي</TableHead>
              <TableHead className="text-end">الرصيد</TableHead>
              <TableHead className="text-end">الحد الأدنى</TableHead>
              <TableHead>الحالة</TableHead>
              <TableHead />
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.map((item) => {
              const stock = stockOf.get(item.id);
              const min = parseQty(item.min_stock) ?? 0n;
              const low = item.is_active && min > 0n && (parseQty(stock?.qty ?? "0") ?? 0n) < min;
              return (
                <TableRow key={item.id}>
                  <TableCell dir="ltr" className="text-end font-mono">
                    {item.code}
                  </TableCell>
                  <TableCell className="font-semibold">
                    <Link href={`/items/${item.id}`} className="underline-offset-4 hover:underline">
                      {item.name}
                    </Link>
                  </TableCell>
                  <TableCell>{isItemType(item.type) ? ITEM_TYPE_LABELS[item.type] : item.type}</TableCell>
                  <TableCell>{item.category_id ? categoryName.get(item.category_id) : ""}</TableCell>
                  <TableCell>{item.unit}</TableCell>
                  <TableCell dir="ltr" className="text-start tabular-nums">
                    {item.default_cost !== "0.0000" ? formatUnitCost(item.default_cost) : ""}
                  </TableCell>
                  <TableCell dir="ltr" className="text-start tabular-nums">
                    {stock && stock.avg_cost !== "0.0000" ? formatUnitCost(stock.avg_cost) : ""}
                  </TableCell>
                  <TableCell dir="ltr" className="text-start tabular-nums">
                    {formatQty(stock?.qty)}
                  </TableCell>
                  <TableCell dir="ltr" className="text-start tabular-nums">
                    {min > 0n ? formatQty(item.min_stock) : ""}
                  </TableCell>
                  <TableCell className={item.is_active ? "" : "text-muted-foreground"}>
                    <div className="flex items-center gap-1">
                      {item.is_active ? "نشط" : "معطّل"}
                      {low && <Badge>تحت الحد الأدنى</Badge>}
                    </div>
                  </TableCell>
                  <TableCell>
                    <div className="flex justify-end gap-2">
                      <Button asChild variant="outline" size="sm">
                        <Link href={`/items/${item.id}`}>البطاقة</Link>
                      </Button>
                      <DeleteItemButton id={item.id} name={item.name} />
                    </div>
                  </TableCell>
                </TableRow>
              );
            })}
            {rows.length === 0 && (
              <TableRow>
                <TableCell colSpan={11} className="py-6 text-center text-muted-foreground">
                  {q || categoryFilter || typeFilter ? "لا توجد نتائج مطابقة." : "لا توجد أصناف بعد."}
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </div>
      <p className="text-xs text-muted-foreground">
        التكلفة الافتراضية تُقترح لمخزون أول المدة فقط. التقييم والإنتاج وتكلفة المبيعات بمتوسط التكلفة الفعلي.
      </p>
    </div>
  );
}
