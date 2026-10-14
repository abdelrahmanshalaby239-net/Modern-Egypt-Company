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
import { deleteItem } from "./actions";

export function DeleteItemButton({ id, name }: { id: number; name: string }) {
  const [open, setOpen] = useState(false);

  return (
    <AlertDialog open={open} onOpenChange={setOpen}>
      <AlertDialogTrigger asChild>
        <Button variant="outline" size="sm">
          حذف
        </Button>
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>حذف صنف</AlertDialogTitle>
          <AlertDialogDescription>هل تريد حذف «{name}»؟ لا يمكن التراجع عن الحذف.</AlertDialogDescription>
        </AlertDialogHeader>
        <DeleteForm id={id} onDone={() => setOpen(false)} />
      </AlertDialogContent>
    </AlertDialog>
  );
}

function DeleteForm({ id, onDone }: { id: number; onDone: () => void }) {
  const [state, onSubmit, pending] = useFormAction(deleteItem, onDone);

  return (
    <form onSubmit={onSubmit} className="grid gap-4">
      <input type="hidden" name="id" value={id} />
      {state.error && <Alert>{state.error}</Alert>}
      <AlertDialogFooter>
        <Button type="submit" disabled={pending}>
          {pending ? "جارٍ الحذف..." : "حذف"}
        </Button>
        <AlertDialogCancel>إلغاء</AlertDialogCancel>
      </AlertDialogFooter>
    </form>
  );
}
