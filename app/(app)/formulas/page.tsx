import type { Metadata } from "next";
import Link from "next/link";

import { Button } from "@/components/ui/button";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { requireUser } from "@/lib/auth";
import { formatQty } from "@/lib/quantity";

export const metadata: Metadata = { title: "الوصفات" };

export default async function FormulasPage() {
  const { supabase } = await requireUser();
  const [{ data: formulas }, { data: lines }] = await Promise.all([
    supabase
      .from("formulas")
      .select(
        "id, name, batch_qty::text, is_active, notes, item:items!formulas_finished_item_id_fkey(id, code, name, unit), batch_unit:item_units!formulas_batch_unit_fkey(name)",
      )
      .order("name"),
    supabase.from("formula_lines").select("formula_id"),
  ]);
  const countOf = new Map<number, number>();
  for (const l of lines ?? []) countOf.set(l.formula_id, (countOf.get(l.formula_id) ?? 0) + 1);

  return (
    <div className="grid gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-xl font-bold">الوصفات</h1>
        <Button asChild>
          <Link href="/formulas/new">وصفة جديدة</Link>
        </Button>
      </div>

      <div className="rounded-lg border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>الوصفة</TableHead>
              <TableHead>المنتج التام</TableHead>
              <TableHead className="text-end">ناتج الدفعة</TableHead>
              <TableHead className="text-end">عدد المواد</TableHead>
              <TableHead>الحالة</TableHead>
              <TableHead />
            </TableRow>
          </TableHeader>
          <TableBody>
            {(formulas ?? []).map((f) => (
              <TableRow key={f.id}>
                <TableCell className="font-semibold">
                  <Link href={`/formulas/${f.id}`} className="underline-offset-4 hover:underline">
                    {f.name}
                  </Link>
                </TableCell>
                <TableCell>{f.item && `${f.item.code} - ${f.item.name}`}</TableCell>
                <TableCell className="text-start tabular-nums">
                  <span dir="ltr">{formatQty(f.batch_qty)}</span> {f.batch_unit?.name ?? f.item?.unit}
                </TableCell>
                <TableCell dir="ltr" className="text-start tabular-nums">
                  {countOf.get(f.id) ?? 0}
                </TableCell>
                <TableCell className={f.is_active ? "" : "text-muted-foreground"}>
                  {f.is_active ? "نشطة" : "معطّلة"}
                </TableCell>
                <TableCell>
                  <div className="flex justify-end gap-2">
                    <Button asChild variant="outline" size="sm">
                      <Link href={`/formulas/${f.id}`}>فتح</Link>
                    </Button>
                    {f.is_active && (
                      <Button asChild variant="outline" size="sm">
                        <Link href={`/production/new?formula=${f.id}`}>تسجيل إنتاج</Link>
                      </Button>
                    )}
                  </div>
                </TableCell>
              </TableRow>
            ))}
            {(formulas ?? []).length === 0 && (
              <TableRow>
                <TableCell colSpan={6} className="py-6 text-center text-muted-foreground">
                  لا توجد وصفات بعد.
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </div>
      <p className="text-xs text-muted-foreground">
        الوصفة تحدد المواد لكل دفعة. عند تسجيل الإنتاج تتولّد سطور الاستهلاك منها وتقبل التعديل، والفرق عن الوصفة
        هو الهالك.
      </p>
    </div>
  );
}
