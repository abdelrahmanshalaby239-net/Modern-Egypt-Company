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
import { cancelJournalEntry } from "../actions";

export function CancelEntryButton({ id, entryNo }: { id: number; entryNo: number }) {
  const [open, setOpen] = useState(false);

  return (
    <AlertDialog open={open} onOpenChange={setOpen}>
      <AlertDialogTrigger asChild>
        <Button variant="outline">إلغاء القيد</Button>
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>إلغاء القيد رقم {entryNo}</AlertDialogTitle>
          <AlertDialogDescription>
            سيُسجَّل قيد عكسي بنفس التاريخ يلغي أثر هذا القيد. لا يمكن التراجع عن الإلغاء.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <CancelForm id={id} />
      </AlertDialogContent>
    </AlertDialog>
  );
}

function CancelForm({ id }: { id: number }) {
  const [state, onSubmit, pending] = useFormAction(cancelJournalEntry);

  return (
    <form onSubmit={onSubmit} className="grid gap-4">
      <input type="hidden" name="id" value={id} />
      {state.error && <Alert>{state.error}</Alert>}
      <AlertDialogFooter>
        <Button type="submit" disabled={pending}>
          {pending ? "جارٍ الإلغاء..." : "إلغاء القيد"}
        </Button>
        <AlertDialogCancel>رجوع</AlertDialogCancel>
      </AlertDialogFooter>
    </form>
  );
}
