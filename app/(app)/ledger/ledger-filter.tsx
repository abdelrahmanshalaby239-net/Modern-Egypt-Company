"use client";

import { useState } from "react";

import { DateInput } from "@/components/date-input";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { NativeSelect } from "@/components/ui/native-select";

export type SubjectKind = "account" | "customer" | "supplier";
type Option = { id: number; label: string };

const KIND_LABELS: Record<SubjectKind, string> = { account: "الحساب", customer: "العميل", supplier: "المورد" };

// كشف حساب لحساب أو عميل أو مورد (SPEC §6.4). اسم حقل الاختيار = نوع الكشف (account/customer/supplier).
export function LedgerFilter({
  options,
  kind: initialKind,
  subjectId,
  from,
  to,
}: {
  options: Record<SubjectKind, Option[]>;
  kind: SubjectKind;
  subjectId: number | null;
  from: string | null;
  to: string | null;
}) {
  const [kind, setKind] = useState<SubjectKind>(initialKind);

  return (
    <form className="flex flex-wrap items-end gap-3 print:hidden">
      <div className="grid gap-1">
        <Label htmlFor="subject_kind">نوع الكشف</Label>
        <NativeSelect
          id="subject_kind"
          value={kind}
          onChange={(e) => setKind(e.target.value as SubjectKind)}
          className="w-28"
        >
          <option value="account">حساب</option>
          <option value="customer">عميل</option>
          <option value="supplier">مورد</option>
        </NativeSelect>
      </div>
      <div className="grid gap-1">
        <Label htmlFor="subject">{KIND_LABELS[kind]}</Label>
        <NativeSelect
          key={kind}
          id="subject"
          name={kind}
          defaultValue={kind === initialKind ? (subjectId ?? "") : ""}
          className="w-72"
        >
          <option value="">اختر {KIND_LABELS[kind]}</option>
          {options[kind].map((o) => (
            <option key={o.id} value={o.id}>
              {o.label}
            </option>
          ))}
        </NativeSelect>
      </div>
      <div className="grid gap-1">
        <Label htmlFor="from">من تاريخ</Label>
        <DateInput id="from" name="from" defaultValue={from} className="w-36 text-end" />
      </div>
      <div className="grid gap-1">
        <Label htmlFor="to">إلى تاريخ</Label>
        <DateInput id="to" name="to" defaultValue={to} className="w-36 text-end" />
      </div>
      <Button type="submit" variant="outline">
        عرض
      </Button>
    </form>
  );
}
