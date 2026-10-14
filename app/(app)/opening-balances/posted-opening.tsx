import Link from "next/link";

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { formatDate } from "@/lib/format";

// جزء افتتاحي مسجّل: يُستخدم مرة واحدة، والتصحيح بإلغاء قيده ثم التسجيل من جديد
export function PostedOpening({
  title,
  entry,
}: {
  title: string;
  entry: { entry_id: number; entry_no: number; entry_date: string };
}) {
  return (
    <Card className="max-w-2xl">
      <CardHeader>
        <CardTitle>تم تسجيل {title}</CardTitle>
        <CardDescription>
          سُجّلت في القيد رقم {entry.entry_no} بتاريخ <span dir="ltr">{formatDate(entry.entry_date)}</span>.
          هذه الشاشة تُستخدم مرة واحدة.
        </CardDescription>
      </CardHeader>
      <CardContent className="text-sm text-muted-foreground">
        للتصحيح: افتح{" "}
        <Link href={`/journal/${entry.entry_id}`} className="font-semibold text-foreground underline">
          القيد رقم {entry.entry_no}
        </Link>{" "}
        وألغِه، ثم سجّلها من جديد.
      </CardContent>
    </Card>
  );
}
