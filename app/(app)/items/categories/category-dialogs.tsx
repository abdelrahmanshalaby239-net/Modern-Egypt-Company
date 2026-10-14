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
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useFormAction } from "@/lib/use-form-action";
import { deleteCategory, saveCategory } from "../actions";

export function CategoryDialog({ category }: { category?: { id: number; name: string } }) {
  const [open, setOpen] = useState(false);

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        {category ? (
          <Button variant="outline" size="sm">
            تعديل
          </Button>
        ) : (
          <Button>إضافة تصنيف</Button>
        )}
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{category ? "تعديل تصنيف" : "إضافة تصنيف"}</DialogTitle>
        </DialogHeader>
        <CategoryForm category={category} onDone={() => setOpen(false)} />
      </DialogContent>
    </Dialog>
  );
}

function CategoryForm({ category, onDone }: { category?: { id: number; name: string }; onDone: () => void }) {
  const [state, onSubmit, pending] = useFormAction(saveCategory, onDone);

  return (
    <form onSubmit={onSubmit} className="grid gap-4">
      {category && <input type="hidden" name="id" value={category.id} />}
      <div className="grid gap-2">
        <Label htmlFor="name">اسم التصنيف</Label>
        <Input id="name" name="name" defaultValue={category?.name} required />
      </div>
      {state.error && <Alert>{state.error}</Alert>}
      <DialogFooter>
        <Button type="submit" disabled={pending}>
          {pending ? "جارٍ الحفظ..." : "حفظ"}
        </Button>
        <DialogClose asChild>
          <Button type="button" variant="outline">
            إلغاء
          </Button>
        </DialogClose>
      </DialogFooter>
    </form>
  );
}

export function DeleteCategoryButton({ id, name }: { id: number; name: string }) {
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
          <AlertDialogTitle>حذف تصنيف</AlertDialogTitle>
          <AlertDialogDescription>هل تريد حذف التصنيف «{name}»؟</AlertDialogDescription>
        </AlertDialogHeader>
        <DeleteForm id={id} onDone={() => setOpen(false)} />
      </AlertDialogContent>
    </AlertDialog>
  );
}

function DeleteForm({ id, onDone }: { id: number; onDone: () => void }) {
  const [state, onSubmit, pending] = useFormAction(deleteCategory, onDone);

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
