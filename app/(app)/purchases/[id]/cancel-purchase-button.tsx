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
import { useFormAction } from "@/lib/use-form-action";
import { cancelPurchaseInvoice } from "../actions";

// voucher = سند «مدفوع الآن» الساري: لا يُلغى مع الفاتورة (قرار المرحلة 4)، فننبه إليه
export function CancelPurchaseButton({
  id,
  title,
  voucher,
}: {
  id: number;
  title: string;
  voucher: { id: number; doc_no: number } | null;
}) {
  const [open, setOpen] = useState(false);

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
            سيُسجَّل قيد عكسي بنفس تاريخ الفاتورة، وتخرج كمياتها من المخزون بتكلفتها الأصلية. يُرفض
            الإلغاء لو صُرف جزء من الكمية (رصيد سالب). لا يمكن التراجع عن الإلغاء، وللتصحيح أدخل الفاتورة
            من جديد.
          </AlertDialogDescription>
        </AlertDialogHeader>
        {voucher && (
          <Alert variant="warning">
            هذه الفاتورة سُددت بـ{" "}
            <Link href={`/vouchers/payment/${voucher.id}`} className="font-semibold underline">
              سند الصرف رقم {voucher.doc_no}
            </Link>
            ، والسند لا يُلغى مع الفاتورة ويبقى رصيده للمورد. لو لم يعد السداد صحيحًا ألغِ السند من صفحته،
            حتى لا يتكرر السداد عند إدخال الفاتورة من جديد.
          </Alert>
        )}
        <CancelForm id={id} />
      </AlertDialogContent>
    </AlertDialog>
  );
}

function CancelForm({ id }: { id: number }) {
  const [state, onSubmit, pending] = useFormAction(cancelPurchaseInvoice);

  return (
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
  );
}
