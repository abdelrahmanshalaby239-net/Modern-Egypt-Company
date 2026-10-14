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
import { deleteFormula } from "../actions";

export function DeleteFormulaButton({ id, name }: { id: number; name: string }) {
  const [open, setOpen] = useState(false);
  const [state, onSubmit, pending] = useFormAction(deleteFormula);

  return (
    <AlertDialog open={open} onOpenChange={setOpen}>
      <AlertDialogTrigger asChild>
        <Button variant="outline" size="sm">
          حذف الوصفة
        </Button>
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>حذف وصفة</AlertDialogTitle>
          <AlertDialogDescription>
            هل تريد حذف الوصفة «{name}»؟ الوصفة التي استُخدمت في الإنتاج لا تُحذف، وعطّلها بدل الحذف.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <form onSubmit={onSubmit} className="grid gap-4">
          <input type="hidden" name="id" value={id} />
          {state.error && <Alert>{state.error}</Alert>}
          <AlertDialogFooter>
            <Button type="submit" disabled={pending}>
              {pending ? "جارٍ الحذف..." : "حذف"}
            </Button>
            <AlertDialogCancel>رجوع</AlertDialogCancel>
          </AlertDialogFooter>
        </form>
      </AlertDialogContent>
    </AlertDialog>
  );
}
