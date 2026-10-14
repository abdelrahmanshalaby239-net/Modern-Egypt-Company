"use client";

import { startTransition, useActionState, useState } from "react";

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
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { NativeSelect } from "@/components/ui/native-select";
import type { PostingAccount } from "@/lib/accounts";
import type { FormState } from "@/lib/errors";
import { parseDate } from "@/lib/format";
import { COUNTERPART_LABELS, VOUCHER_LABELS, type VoucherKind } from "@/lib/labels";
import { formatCents, parseCents, plainCents } from "@/lib/money";
import { postVoucher } from "../../actions";

type Party = { id: number; name: string };
type PartyKind = "customer" | "supplier" | "account";

export function VoucherForm({
  kind,
  defaultDate,
  treasuries,
  accounts,
  customers,
  suppliers,
}: {
  kind: VoucherKind;
  defaultDate: string;
  treasuries: PostingAccount[];
  accounts: PostingAccount[];
  customers: Party[];
  suppliers: Party[];
}) {
  const labels = VOUCHER_LABELS[kind];
  const [state, action, pending] = useActionState<FormState, FormData>(postVoucher, {});
  const [docDate, setDocDate] = useState(defaultDate);
  const [treasuryId, setTreasuryId] = useState(String(treasuries[0]?.id ?? ""));
  const [partyKind, setPartyKind] = useState<PartyKind>(kind === "receipt" ? "customer" : "supplier");
  const [partyId, setPartyId] = useState("");
  const [amount, setAmount] = useState("");
  const [notes, setNotes] = useState("");
  const [clientError, setClientError] = useState("");
  const [confirmOpen, setConfirmOpen] = useState(false);

  // الحساب الآخر لا يكون نفس الخزينة المختارة
  const options =
    partyKind === "customer"
      ? customers.map((c) => ({ id: String(c.id), label: c.name }))
      : partyKind === "supplier"
        ? suppliers.map((s) => ({ id: String(s.id), label: s.name }))
        : accounts
            .filter((a) => String(a.id) !== treasuryId)
            .map((a) => ({ id: String(a.id), label: `${a.code} - ${a.name}` }));
  const party = options.find((o) => o.id === partyId);
  const treasury = treasuries.find((t) => String(t.id) === treasuryId);
  const cents = parseCents(amount); // BigInt — لا float

  const validate = (): string => {
    if (!parseDate(docDate)) return "تاريخ السند غير صحيح. اكتبه بصيغة يوم/شهر/سنة.";
    if (!treasury) return "اختر الخزينة أو البنك.";
    if (!party) return `اختر ${COUNTERPART_LABELS[partyKind]}.`;
    if (cents === null) return "المبلغ غير صالح (رقم موجب بخانتين عشريتين كحد أقصى).";
    if (cents <= 0n) return "المبلغ مطلوب ويجب أن يكون أكبر من صفر.";
    return "";
  };

  const requestPost = () => {
    const error = validate();
    setClientError(error);
    if (!error) setConfirmOpen(true);
  };

  const post = () => {
    setConfirmOpen(false);
    const formData = new FormData();
    formData.set("kind", kind);
    formData.set("doc_date", docDate);
    formData.set("treasury_account_id", treasuryId);
    formData.set("party_kind", partyKind);
    formData.set("party_id", partyId);
    formData.set("amount", plainCents(cents ?? 0n));
    formData.set("notes", notes);
    startTransition(() => action(formData));
  };

  const error = clientError || state.error;

  return (
    <Card>
      <CardContent className="grid gap-4">
        <div className="grid gap-3 sm:grid-cols-2">
          <div className="grid gap-2">
            <Label htmlFor="doc_date">التاريخ</Label>
            <Input
              id="doc_date"
              dir="ltr"
              inputMode="numeric"
              placeholder="يوم/شهر/سنة"
              className="text-end"
              value={docDate}
              onChange={(e) => setDocDate(e.target.value)}
            />
          </div>
          <div className="grid gap-2">
            <Label htmlFor="treasury">{kind === "receipt" ? "إلى الخزينة/البنك" : "من الخزينة/البنك"}</Label>
            <NativeSelect id="treasury" value={treasuryId} onChange={(e) => setTreasuryId(e.target.value)}>
              {treasuries.map((t) => (
                <option key={t.id} value={t.id}>
                  {t.code} - {t.name}
                </option>
              ))}
            </NativeSelect>
          </div>
        </div>

        <div className="grid gap-3 sm:grid-cols-[10rem_1fr]">
          <div className="grid gap-2">
            <Label htmlFor="party_kind">{labels.party}</Label>
            <NativeSelect
              id="party_kind"
              value={partyKind}
              onChange={(e) => {
                setPartyKind(e.target.value as PartyKind);
                setPartyId("");
              }}
            >
              <option value="customer">عميل</option>
              <option value="supplier">مورد</option>
              <option value="account">حساب آخر</option>
            </NativeSelect>
          </div>
          <div className="grid gap-2">
            <Label htmlFor="party">{COUNTERPART_LABELS[partyKind]}</Label>
            <NativeSelect id="party" value={partyId} onChange={(e) => setPartyId(e.target.value)}>
              <option value="">اختر {COUNTERPART_LABELS[partyKind]}</option>
              {options.map((o) => (
                <option key={o.id} value={o.id}>
                  {o.label}
                </option>
              ))}
            </NativeSelect>
          </div>
        </div>

        <div className="grid gap-3 sm:grid-cols-[12rem_1fr]">
          <div className="grid gap-2">
            <Label htmlFor="amount">المبلغ</Label>
            <Input
              id="amount"
              dir="ltr"
              inputMode="decimal"
              value={amount}
              aria-invalid={cents === null}
              onChange={(e) => setAmount(e.target.value)}
            />
          </div>
          <div className="grid gap-2">
            <Label htmlFor="notes">البيان (اختياري)</Label>
            <Input id="notes" value={notes} onChange={(e) => setNotes(e.target.value)} />
          </div>
        </div>

        {error && <Alert>{error}</Alert>}

        <div>
          <Button type="button" onClick={requestPost} disabled={pending}>
            {pending ? "جارٍ الاعتماد..." : `اعتماد ${labels.one}`}
          </Button>
        </div>
      </CardContent>

      <AlertDialog open={confirmOpen} onOpenChange={setConfirmOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>تأكيد اعتماد {labels.one}</AlertDialogTitle>
            <AlertDialogDescription>
              {labels.one} بمبلغ {formatCents(cents ?? 0n)} — {labels.party} {party?.label} —{" "}
              {treasury ? `${treasury.code} - ${treasury.name}` : ""}. لا يمكن تعديل السند أو حذفه بعد
              الاعتماد، والتصحيح يكون بإلغائه ثم إدخاله من جديد.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <Button type="button" onClick={post}>
              اعتماد
            </Button>
            <AlertDialogCancel>رجوع</AlertDialogCancel>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </Card>
  );
}
