import Link from "next/link";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { requireUser } from "@/lib/auth";
import { PARTY_LABELS, type PartyKind } from "@/lib/labels";
import { formatBalance, plainCents, sumAmounts } from "@/lib/money";
import { DeletePartyButton } from "./delete-party-button";
import { PartyDialog } from "./party-dialog";

// شاشة العملاء أو الموردين: الرصيد من القيود فقط (party_balances)
export async function PartiesPage({ kind, q }: { kind: PartyKind; q: string }) {
  const { supabase } = await requireUser();
  const { many, table } = PARTY_LABELS[kind];

  const [{ data: parties }, { data: balances }] = await Promise.all([
    supabase.from(table).select("*").order("name"),
    supabase.rpc("party_balances", { p_party_kind: kind }),
  ]);
  const balanceOf = new Map((balances ?? []).map((b) => [b.party_id, b.balance]));
  const rows = (parties ?? []).filter(
    (p) => !q || p.name.includes(q) || (p.phone ?? "").includes(q),
  );
  const total = sumAmounts(rows.map((p) => balanceOf.get(p.id)));

  return (
    <div className="grid gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-xl font-bold">{many}</h1>
        <PartyDialog kind={kind} />
      </div>

      <form className="flex max-w-md gap-2">
        <Input name="q" defaultValue={q} placeholder="بحث بالاسم أو الهاتف" />
        <Button type="submit" variant="outline">
          بحث
        </Button>
      </form>

      <div className="rounded-lg border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>الاسم</TableHead>
              <TableHead>الهاتف</TableHead>
              <TableHead>العنوان</TableHead>
              <TableHead className="text-end">الرصيد</TableHead>
              <TableHead>الحالة</TableHead>
              <TableHead />
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.map((p) => (
              <TableRow key={p.id}>
                <TableCell className="font-semibold">{p.name}</TableCell>
                <TableCell dir="ltr" className="text-end">
                  {p.phone}
                </TableCell>
                <TableCell className="whitespace-normal">{p.address}</TableCell>
                <TableCell className="text-end tabular-nums whitespace-nowrap">
                  {formatBalance(balanceOf.get(p.id))}
                </TableCell>
                <TableCell className={p.is_active ? "" : "text-muted-foreground"}>
                  {p.is_active ? "نشط" : "معطّل"}
                </TableCell>
                <TableCell>
                  <div className="flex justify-end gap-2">
                    <Button asChild variant="outline" size="sm">
                      <Link href={`/ledger?${kind}=${p.id}`}>كشف حساب</Link>
                    </Button>
                    <PartyDialog kind={kind} party={p} />
                    <DeletePartyButton kind={kind} id={p.id} name={p.name} />
                  </div>
                </TableCell>
              </TableRow>
            ))}
            {rows.length === 0 ? (
              <TableRow>
                <TableCell colSpan={6} className="py-6 text-center text-muted-foreground">
                  {q ? "لا توجد نتائج مطابقة." : `لا يوجد ${many} بعد.`}
                </TableCell>
              </TableRow>
            ) : (
              <TableRow className="font-bold hover:bg-transparent">
                <TableCell colSpan={3}>الإجمالي</TableCell>
                <TableCell className="text-end tabular-nums whitespace-nowrap">
                  {formatBalance(plainCents(total))}
                </TableCell>
                <TableCell colSpan={2} />
              </TableRow>
            )}
          </TableBody>
        </Table>
      </div>
    </div>
  );
}
