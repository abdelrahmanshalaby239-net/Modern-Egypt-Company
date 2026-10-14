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
import { NativeSelect } from "@/components/ui/native-select";
import { ITEM_TYPES, ITEM_TYPE_LABELS } from "@/lib/labels";
import { useFormAction } from "@/lib/use-form-action";
import { saveItem } from "./actions";

export type ItemRow = {
  id: number;
  code: string;
  name: string;
  type: string;
  unit: string;
  sale_price: string | null;
  is_active: boolean;
};

// used = للصنف حركات، فنوعه ثابت (يحدد حساب المخزون؛ مفروض في قاعدة البيانات)
export function ItemDialog({ item, used = false }: { item?: ItemRow; used?: boolean }) {
  const [open, setOpen] = useState(false);

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        {item ? (
          <Button variant="outline" size="sm">
            تعديل
          </Button>
        ) : (
          <Button>إضافة صنف</Button>
        )}
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{item ? "تعديل صنف" : "إضافة صنف"}</DialogTitle>
        </DialogHeader>
        <ItemForm item={item} used={used} onDone={() => setOpen(false)} />
      </DialogContent>
    </Dialog>
  );
}

function ItemForm({ item, used, onDone }: { item?: ItemRow; used: boolean; onDone: () => void }) {
  const [state, onSubmit, pending] = useFormAction(saveItem, onDone);

  return (
    <form onSubmit={onSubmit} className="grid gap-4">
      {item && <input type="hidden" name="id" value={item.id} />}

      <div className="grid gap-3 sm:grid-cols-[10rem_1fr]">
        <div className="grid gap-2">
          <Label htmlFor="code">الكود</Label>
          <Input id="code" name="code" dir="ltr" className="text-end" defaultValue={item?.code} required />
        </div>
        <div className="grid gap-2">
          <Label htmlFor="name">الاسم</Label>
          <Input id="name" name="name" defaultValue={item?.name} required />
        </div>
      </div>
      <div className="grid gap-3 sm:grid-cols-2">
        <div className="grid gap-2">
          <Label htmlFor="type">النوع</Label>
          {used && <input type="hidden" name="type" value={item?.type} />}
          <NativeSelect id="type" name={used ? undefined : "type"} defaultValue={item?.type ?? "raw_material"} disabled={used}>
            {ITEM_TYPES.map((t) => (
              <option key={t} value={t}>
                {ITEM_TYPE_LABELS[t]}
              </option>
            ))}
          </NativeSelect>
          {used && <p className="text-xs text-muted-foreground">النوع لا يتغير بعد وجود حركات على الصنف.</p>}
        </div>
        <div className="grid gap-2">
          <Label htmlFor="unit">وحدة القياس</Label>
          <Input id="unit" name="unit" defaultValue={item?.unit} placeholder="كجم، لتر، قطعة، عبوة" required />
        </div>
      </div>
      <div className="grid max-w-xs gap-2">
        <Label htmlFor="sale_price">سعر البيع المقترح (اختياري)</Label>
        <Input id="sale_price" name="sale_price" dir="ltr" inputMode="decimal" defaultValue={item?.sale_price ?? ""} />
      </div>
      {item && (
        <Label>
          <Checkbox name="is_active" defaultChecked={item.is_active} />
          نشط (المعطّل لا يظهر في المستندات الجديدة)
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
