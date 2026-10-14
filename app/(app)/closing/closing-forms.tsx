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
} from "@/components/ui/alert-dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import type { FormState } from "@/lib/errors";
import { formatDate } from "@/lib/format";
import { useFormAction } from "@/lib/use-form-action";
import { closeFiscalYear, lockPeriod, saveFiscalYear } from "./actions";

function FormMessage({ state }: { state: FormState }) {
  if (state.error) return <Alert>{state.error}</Alert>;
  if (state.success) return <Alert variant="success">{state.success}</Alert>;
  return null;
}

// تعريف السنة المالية المفتوحة أو تعديلها. بداية السنة التالية لسنة مقفلة ثابتة.
export function FiscalYearForm({
  year,
  startLocked,
}: {
  year: { name: string; start_date: string; end_date: string } | null;
  startLocked: boolean;
}) {
  const [state, onSubmit, pending] = useFormAction(saveFiscalYear);

  return (
    <form onSubmit={onSubmit} className="grid gap-4">
      <div className="grid gap-3 sm:grid-cols-[1fr_9rem_9rem]">
        <div className="grid gap-2">
          <Label htmlFor="name">اسم السنة المالية</Label>
          <Input id="name" name="name" defaultValue={year?.name ?? ""} placeholder="مثل: السنة المالية 2026" required />
        </div>
        <div className="grid gap-2">
          <Label htmlFor="start_date">البداية (أول الشهر)</Label>
          <Input
            id="start_date"
            name="start_date"
            dir="ltr"
            inputMode="numeric"
            placeholder="يوم/شهر/سنة"
            className="text-end"
            defaultValue={formatDate(year?.start_date)}
            readOnly={startLocked}
            required
          />
        </div>
        <div className="grid gap-2">
          <Label htmlFor="end_date">النهاية (آخر الشهر)</Label>
          <Input
            id="end_date"
            name="end_date"
            dir="ltr"
            inputMode="numeric"
            placeholder="يوم/شهر/سنة"
            className="text-end"
            defaultValue={formatDate(year?.end_date)}
            required
          />
        </div>
      </div>
      <FormMessage state={state} />
      <div>
        <Button type="submit" disabled={pending}>
          {pending ? "جارٍ الحفظ..." : year ? "حفظ التعديل" : "تعريف السنة المالية"}
        </Button>
      </div>
    </form>
  );
}

export function LockPeriodForm({ suggested }: { suggested: string }) {
  const [open, setOpen] = useState(false);
  const [date, setDate] = useState(suggested);
  const [state, onSubmit, pending] = useFormAction(lockPeriod, () => setOpen(false));

  return (
    <div className="grid gap-3">
      <div className="grid max-w-xs gap-2">
        <Label htmlFor="lock_date">قفل الفترة حتى (آخر يوم في شهر انتهى)</Label>
        <Input
          id="lock_date"
          dir="ltr"
          inputMode="numeric"
          placeholder="يوم/شهر/سنة"
          className="text-end"
          value={date}
          onChange={(e) => setDate(e.target.value)}
        />
      </div>
      {!open && <FormMessage state={state} />}
      <div>
        <Button type="button" variant="outline" disabled={!date.trim()} onClick={() => setOpen(true)}>
          قفل الفترة
        </Button>
      </div>
      <AlertDialog open={open} onOpenChange={setOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>تأكيد قفل الفترة حتى {date}</AlertDialogTitle>
            <AlertDialogDescription>
              بعد القفل يُرفض أي مستند أو قيد أو إلغاء بتاريخ حتى {date}. القفل للأمام فقط ولا يمكن التراجع عنه.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <form onSubmit={onSubmit} className="grid gap-4">
            <input type="hidden" name="lock_date" value={date} />
            <FormMessage state={state} />
            <AlertDialogFooter>
              <Button type="submit" disabled={pending}>
                {pending ? "جارٍ القفل..." : "قفل"}
              </Button>
              <AlertDialogCancel>رجوع</AlertDialogCancel>
            </AlertDialogFooter>
          </form>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}

export function CloseYearButton({
  yearName,
  endDate,
  netProfit,
  disabled,
}: {
  yearName: string;
  endDate: string;
  netProfit: string;
  disabled: boolean;
}) {
  const [open, setOpen] = useState(false);
  const [state, onSubmit, pending] = useFormAction(closeFiscalYear, () => setOpen(false));

  return (
    <div className="grid gap-3">
      {!open && <FormMessage state={state} />}
      <div>
        <Button type="button" disabled={disabled} onClick={() => setOpen(true)}>
          إقفال {yearName}
        </Button>
      </div>
      <AlertDialog open={open} onOpenChange={setOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>تأكيد إقفال {yearName}</AlertDialogTitle>
            <AlertDialogDescription>
              سيُسجَّل قيد الإقفال بتاريخ {formatDate(endDate)} ويصفّر الإيرادات والمصروفات في الأرباح المرحّلة (صافي
              الربح {netProfit})، ثم تُقفل الفترة حتى نهاية السنة وتُفتح السنة التالية. لا يمكن إلغاء الإقفال أو إعادة فتح
              السنة.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <form onSubmit={onSubmit} className="grid gap-4">
            <FormMessage state={state} />
            <AlertDialogFooter>
              <Button type="submit" disabled={pending}>
                {pending ? "جارٍ الإقفال..." : "إقفال السنة"}
              </Button>
              <AlertDialogCancel>رجوع</AlertDialogCancel>
            </AlertDialogFooter>
          </form>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
