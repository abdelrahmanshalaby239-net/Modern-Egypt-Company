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
import { useFormAction } from "@/lib/use-form-action";
import { cancelStockAdjustment } from "../actions";

export function CancelAdjustmentButton({ id, title }: { id: number; title: string }) {
  const [open, setOpen] = useState(false);

  return (
    <AlertDialog open={open} onOpenChange={setOpen}>
      <AlertDialogTrigger asChild>
        <Button variant="outline" className="print:hidden">
          إلغاء التسوية
        </Button>
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>إلغاء {title}</AlertDialogTitle>
          <AlertDialogDescription>
            سيُسجَّل قيد عكسي بنفس تاريخ التسوية، وتعود الكمية للمخزون أو تخرج منه بنفس التكلفة. لا يمكن
            التراجع عن الإلغاء، وللتصحيح أدخل التسوية من جديد.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <CancelForm id={id} />
      </AlertDialogContent>
    </AlertDialog>
  );
}

function CancelForm({ id }: { id: number }) {
  const [state, onSubmit, pending] = useFormAction(cancelStockAdjustment);

  return (
    <form onSubmit={onSubmit} className="grid gap-4">
      <input type="hidden" name="id" value={id} />
      {state.error && <Alert>{state.error}</Alert>}
      <AlertDialogFooter>
        <Button type="submit" disabled={pending}>
          {pending ? "جارٍ الإلغاء..." : "إلغاء التسوية"}
        </Button>
        <AlertDialogCancel>رجوع</AlertDialogCancel>
      </AlertDialogFooter>
    </form>
  );
}
