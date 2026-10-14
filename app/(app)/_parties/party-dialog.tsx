"use client";

import { useState } from "react";

import { Alert } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
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
import type { Tables } from "@/lib/database.types";
import { PARTY_LABELS, type PartyKind } from "@/lib/labels";
import { useFormAction } from "@/lib/use-form-action";
import { saveParty } from "./actions";

type Party = Tables<"customers">;

export function PartyDialog({ kind, party }: { kind: PartyKind; party?: Party }) {
  const [open, setOpen] = useState(false);
  const { one } = PARTY_LABELS[kind];

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        {party ? (
          <Button variant="outline" size="sm">
            تعديل
          </Button>
        ) : (
          <Button>إضافة {one}</Button>
        )}
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{party ? `تعديل ${one}` : `إضافة ${one}`}</DialogTitle>
        </DialogHeader>
        <PartyForm kind={kind} party={party} onDone={() => setOpen(false)} />
      </DialogContent>
    </Dialog>
  );
}

function PartyForm({ kind, party, onDone }: { kind: PartyKind; party?: Party; onDone: () => void }) {
  const [state, onSubmit, pending] = useFormAction(saveParty, onDone);

  return (
    <form onSubmit={onSubmit} className="grid gap-4">
      <input type="hidden" name="kind" value={kind} />
      {party && <input type="hidden" name="id" value={party.id} />}

      <div className="grid gap-2">
        <Label htmlFor="name">الاسم</Label>
        <Input id="name" name="name" defaultValue={party?.name} required />
      </div>
      <div className="grid gap-3 sm:grid-cols-2">
        <div className="grid gap-2">
          <Label htmlFor="phone">الهاتف</Label>
          <Input id="phone" name="phone" dir="ltr" className="text-end" defaultValue={party?.phone ?? ""} />
        </div>
        <div className="grid gap-2">
          <Label htmlFor="address">العنوان</Label>
          <Input id="address" name="address" defaultValue={party?.address ?? ""} />
        </div>
      </div>
      <div className="grid gap-2">
        <Label htmlFor="notes">ملاحظات</Label>
        <Input id="notes" name="notes" defaultValue={party?.notes ?? ""} />
      </div>
      {party && (
        <Label>
          <Checkbox name="is_active" defaultChecked={party.is_active} />
          نشط (المعطّل لا يظهر في السندات الجديدة)
        </Label>
      )}

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
