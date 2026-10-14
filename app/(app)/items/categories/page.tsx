import type { Metadata } from "next";
import Link from "next/link";

import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { requireUser } from "@/lib/auth";
import { CategoryDialog, DeleteCategoryButton } from "./category-dialogs";

export const metadata: Metadata = { title: "تصنيفات الأصناف" };

export default async function CategoriesPage() {
  const { supabase } = await requireUser();
  const [{ data: categories }, { data: items }] = await Promise.all([
    supabase.from("item_categories").select("id, name").order("name"),
    supabase.from("items").select("category_id"),
  ]);
  const countOf = new Map<number, number>();
  for (const i of items ?? []) {
    if (i.category_id) countOf.set(i.category_id, (countOf.get(i.category_id) ?? 0) + 1);
  }

  return (
    <div className="grid max-w-2xl gap-4">
      <Link href="/items" className="text-sm text-muted-foreground underline-offset-4 hover:underline">
        ← الأصناف
      </Link>
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-xl font-bold">تصنيفات الأصناف</h1>
        <CategoryDialog />
      </div>
      <div className="rounded-lg border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>التصنيف</TableHead>
              <TableHead className="text-end">عدد الأصناف</TableHead>
              <TableHead />
            </TableRow>
          </TableHeader>
          <TableBody>
            {(categories ?? []).map((c) => (
              <TableRow key={c.id}>
                <TableCell className="font-semibold">
                  <Link href={`/items?category=${c.id}`} className="underline-offset-4 hover:underline">
                    {c.name}
                  </Link>
                </TableCell>
                <TableCell dir="ltr" className="text-start tabular-nums">
                  {countOf.get(c.id) ?? 0}
                </TableCell>
                <TableCell>
                  <div className="flex justify-end gap-2">
                    <CategoryDialog category={c} />
                    <DeleteCategoryButton id={c.id} name={c.name} />
                  </div>
                </TableCell>
              </TableRow>
            ))}
            {(categories ?? []).length === 0 && (
              <TableRow>
                <TableCell colSpan={3} className="py-6 text-center text-muted-foreground">
                  لا توجد تصنيفات بعد.
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </div>
    </div>
  );
}
