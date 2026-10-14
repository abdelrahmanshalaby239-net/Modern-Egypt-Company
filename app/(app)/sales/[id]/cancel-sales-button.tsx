"use client";

import Link from "next/link";
import { useState } from "react";

import { Alert } from "@/components/ui/alert";
import {
  AlertDialog,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog";
import { Button } from "@/components/ui/button";
import { formatAmount } from "@/lib/money";
import { useFormAction } from "@/lib/use-form-action";
import { cancelSalesInvoice } from "../actions";

// voucher = سند القبض الساري: لا يُلغى مع الفاتورة، ويبقى رصيدًا دائنًا للعميل، فننبه إليه
export function CancelSalesButton({
  id,
  title,
  voucher,
}: {
  id: number;
  title: string;
  voucher: { id: number; doc_no: number; amount: string } | null;
}) {
  const [open, setOpen] = useState(false);
  const [state, onSubmit, pending] = useFormAction(cancelSalesInvoice);

  return (
    <AlertDialog open={open} onOpenChange={setOpen}>
      <AlertDialogTrigger asChild>
        <Button variant="outline" className="print:hidden">
          إلغاء الفاتورة
        </Button>
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>إلغاء {title}</AlertDialogTitle>
          <AlertDialogDescription>
            سيُسجَّل قيد عكسي بنفس تاريخ الفاتورة، وترجع الكميات للمخزون بتكلفتها وقت البيع، وتخرج الفاتورة من
            تقرير أرباح الأصناف. يُرفض الإلغاء لو التاريخ في فترة مقفولة. لا يمكن التراجع عن الإلغاء، وللتصحيح أدخل
            الفاتورة من جديد.
          </AlertDialogDescription>
        </AlertDialogHeader>
        {voucher && (
          <Alert variant="warning">
            حُصّل من هذه الفاتورة {formatAmount(voucher.amount)} بـ{" "}
            <Link href={`/vouchers/receipt/${voucher.id}`} className="font-semibold underline">
              سند القبض رقم {voucher.doc_no}
            </Link>
            . السند لا يُلغى مع الفاتورة: يبقى المبلغ رصيدًا دائنًا للعميل (مقبوض مقدمًا). عند إدخال الفاتورة المصححة
            اترك المقبوض الآن صفرًا حتى لا يتكرر التحصيل، أو ألغِ السند من صفحته لو لم يُقبض المبلغ فعلًا.
          </Alert>
        )}
        <form onSubmit={onSubmit} className="grid gap-4">
          <input type="hidden" name="id" value={id} />
          {state.error && <Alert>{state.error}</Alert>}
          <AlertDialogFooter>
            <Button type="submit" disabled={pending}>
              {pending ? "جارٍ الإلغاء..." : "إلغاء الفاتورة"}
            </Button>
            <AlertDialogCancel>رجوع</AlertDialogCancel>
          </AlertDialogFooter>
        </form>
      </AlertDialogContent>
    </AlertDialog>
  );
}
