"use client";

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
import { cancelProductionOrder } from "../actions";

// extra = التكاليف الإضافية وحسابها: تُعكس مع القيد، فننبه إليها
export function CancelProductionButton({
  id,
  title,
  extra,
}: {
  id: number;
  title: string;
  extra: { amount: string; account: string } | null;
}) {
  const [open, setOpen] = useState(false);
  const [state, onSubmit, pending] = useFormAction(cancelProductionOrder);

  return (
    <AlertDialog open={open} onOpenChange={setOpen}>
      <AlertDialogTrigger asChild>
        <Button variant="outline" className="print:hidden">
          إلغاء أمر الإنتاج
        </Button>
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>إلغاء {title}</AlertDialogTitle>
          <AlertDialogDescription>
            سيُسجَّل قيد عكسي بنفس تاريخ أمر الإنتاج: ترجع المواد للمخزون بتكلفتها الأصلية، ويخرج المنتج التام
            بتكلفته. يُرفض الإلغاء لو صُرف أو بيع جزء من الكمية المنتجة (رصيد سالب) أو لو التاريخ في فترة
            مقفولة. لا يمكن التراجع عن الإلغاء، وللتصحيح سجّل الإنتاج من جديد.
          </AlertDialogDescription>
        </AlertDialogHeader>
        {extra && (
          <Alert variant="warning">
            التكاليف الإضافية {formatAmount(extra.amount)} تُعكس أيضًا على حساب {extra.account}. لو دُفعت فعلًا ولن
            يُعاد تسجيل الإنتاج، سجّلها بعد الإلغاء كمصروف بسند صرف أو قيد يومية.
          </Alert>
        )}
        <form onSubmit={onSubmit} className="grid gap-4">
          <input type="hidden" name="id" value={id} />
          {state.error && <Alert>{state.error}</Alert>}
          <AlertDialogFooter>
            <Button type="submit" disabled={pending}>
              {pending ? "جارٍ الإلغاء..." : "إلغاء أمر الإنتاج"}
            </Button>
            <AlertDialogCancel>رجوع</AlertDialogCancel>
          </AlertDialogFooter>
        </form>
      </AlertDialogContent>
    </AlertDialog>
  );
}
