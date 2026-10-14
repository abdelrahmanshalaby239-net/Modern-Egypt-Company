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
import { cancelVoucher } from "../../actions";

export function CancelVoucherButton({ kind, id, title }: { kind: string; id: number; title: string }) {
  const [open, setOpen] = useState(false);

  return (
    <AlertDialog open={open} onOpenChange={setOpen}>
      <AlertDialogTrigger asChild>
        <Button variant="outline" className="print:hidden">
          إلغاء السند
        </Button>
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>إلغاء {title}</AlertDialogTitle>
          <AlertDialogDescription>
            سيُسجَّل قيد عكسي بنفس تاريخ السند يلغي أثره على الخزينة والطرف. لا يمكن التراجع عن الإلغاء،
            وللتصحيح أدخل السند من جديد.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <CancelForm kind={kind} id={id} />
      </AlertDialogContent>
    </AlertDialog>
  );
}

function CancelForm({ kind, id }: { kind: string; id: number }) {
  const [state, onSubmit, pending] = useFormAction(cancelVoucher);

  return (
    <form onSubmit={onSubmit} className="grid gap-4">
      <input type="hidden" name="kind" value={kind} />
      <input type="hidden" name="id" value={id} />
      {state.error && <Alert>{state.error}</Alert>}
      <AlertDialogFooter>
        <Button type="submit" disabled={pending}>
          {pending ? "جارٍ الإلغاء..." : "إلغاء السند"}
        </Button>
        <AlertDialogCancel>رجوع</AlertDialogCancel>
      </AlertDialogFooter>
    </form>
  );
}
