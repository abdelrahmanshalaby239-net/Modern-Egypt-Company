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
import type { Tables } from "@/lib/database.types";
import { ACCOUNT_TYPES, ACCOUNT_TYPE_LABELS, type AccountType } from "@/lib/labels";
import { useFormAction } from "@/lib/use-form-action";
import { saveAccount } from "./actions";

type Account = Tables<"accounts">;
type Group = Pick<Account, "id" | "code" | "name" | "type">;

type Props = {
  account?: Account; // بدونه = إضافة
  groups: Group[]; // الحسابات التجميعية المتاحة كأب
  isSystem?: boolean;
};

export function AccountDialog({ account, groups, isSystem = false }: Props) {
  const [open, setOpen] = useState(false);

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        {account ? (
          <Button variant="outline" size="sm">
            تعديل
          </Button>
        ) : (
          <Button>إضافة حساب</Button>
        )}
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{account ? "تعديل حساب" : "إضافة حساب"}</DialogTitle>
        </DialogHeader>
        <AccountForm
          account={account}
          groups={groups.filter((g) => g.id !== account?.id)}
          isSystem={isSystem}
          onDone={() => setOpen(false)}
        />
      </DialogContent>
    </Dialog>
  );
}

function AccountForm({
  account,
  groups,
  isSystem,
  onDone,
}: Props & { onDone: () => void }) {
  const [state, onSubmit, pending] = useFormAction(saveAccount, onDone);

  const [parentId, setParentId] = useState(account?.parent_id ? String(account.parent_id) : "");
  const [ownType, setOwnType] = useState<AccountType>(
    (account?.type as AccountType) ?? "asset",
  );
  const [isPostable, setIsPostable] = useState(account?.is_postable ?? true);

  const parent = groups.find((g) => String(g.id) === parentId);
  const type = (parent?.type as AccountType) ?? ownType;
  const canBeTreasury = type === "asset" && isPostable;

  return (
    <form onSubmit={onSubmit} className="grid gap-4">
      {account && <input type="hidden" name="id" value={account.id} />}

      <div className="grid grid-cols-3 gap-3">
        <div className="grid gap-2">
          <Label htmlFor="code">الكود</Label>
          <Input
            id="code"
            name="code"
            dir="ltr"
            inputMode="numeric"
            defaultValue={account?.code}
            required
          />
        </div>
        <div className="col-span-2 grid gap-2">
          <Label htmlFor="name">اسم الحساب</Label>
          <Input id="name" name="name" defaultValue={account?.name} required />
        </div>
      </div>

      <div className="grid gap-2">
        <Label htmlFor="parent_id">الحساب الأب</Label>
        <NativeSelect
          id="parent_id"
          name="parent_id"
          value={parentId}
          onChange={(e) => setParentId(e.target.value)}
        >
          <option value="">— حساب رئيسي —</option>
          {groups.map((g) => (
            <option key={g.id} value={g.id}>
              {g.code} - {g.name}
            </option>
          ))}
        </NativeSelect>
      </div>

      <div className="grid gap-2">
        <Label htmlFor="type">النوع</Label>
        <NativeSelect
          id="type"
          name="type"
          value={type}
          onChange={(e) => setOwnType(e.target.value as AccountType)}
          disabled={Boolean(parent) || isSystem}
        >
          {ACCOUNT_TYPES.map((t) => (
            <option key={t} value={t}>
              {ACCOUNT_TYPE_LABELS[t]}
            </option>
          ))}
        </NativeSelect>
        {parent && (
          <p className="text-xs text-muted-foreground">النوع يُؤخذ من الحساب الأب.</p>
        )}
        {/* الحقل المعطّل لا يُرسَل، فنرسل النوع في حقل مخفي */}
        {isSystem && !parent && <input type="hidden" name="type" value={type} />}
      </div>

      <div className="grid gap-3">
        <Label>
          <Checkbox
            name="is_postable"
            checked={isPostable}
            onChange={(e) => setIsPostable(e.target.checked)}
            disabled={isSystem}
          />
          حساب فرعي يقبل القيود (أزل العلامة للحساب التجميعي)
        </Label>
        {isSystem && <input type="hidden" name="is_postable" value="on" />}
        <Label>
          <Checkbox
            name="is_treasury"
            defaultChecked={account?.is_treasury}
            disabled={!canBeTreasury}
          />
          خزينة أو بنك
        </Label>
        {account && (
          <Label>
            <Checkbox name="is_active" defaultChecked={account.is_active} disabled={isSystem} />
            نشط
          </Label>
        )}
        {account && isSystem && <input type="hidden" name="is_active" value="on" />}
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
