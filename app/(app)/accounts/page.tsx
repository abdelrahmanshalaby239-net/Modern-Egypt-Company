import type { Metadata } from "next";

import { Badge } from "@/components/ui/badge";
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
import type { Tables } from "@/lib/database.types";
import { ACCOUNT_TYPE_LABELS, type AccountType } from "@/lib/labels";
import { AccountDialog } from "./account-dialog";
import { DeleteAccountButton } from "./delete-account-button";

export const metadata: Metadata = { title: "دليل الحسابات" };

type Account = Tables<"accounts">;

// ترتيب شجري: كل حساب يليه أبناؤه مرتبين بالكود
function toTree(accounts: Account[]) {
  const children = new Map<number | null, Account[]>();
  for (const a of accounts) {
    const list = children.get(a.parent_id) ?? [];
    list.push(a);
    children.set(a.parent_id, list);
  }
  const rows: { account: Account; depth: number }[] = [];
  const walk = (parentId: number | null, depth: number) => {
    for (const a of (children.get(parentId) ?? []).sort((x, y) => x.code.localeCompare(y.code))) {
      rows.push({ account: a, depth });
      walk(a.id, depth + 1);
    }
  };
  walk(null, 0);
  return rows;
}

export default async function AccountsPage({ searchParams }: PageProps<"/accounts">) {
  const { supabase } = await requireUser();
  const q = String((await searchParams).q ?? "").trim();

  const [{ data: accounts }, { data: systemAccounts }] = await Promise.all([
    supabase.from("accounts").select("*"),
    supabase.from("system_accounts").select("account_id"),
  ]);
  const systemIds = new Set((systemAccounts ?? []).map((s) => s.account_id));
  const groups = (accounts ?? []).filter((a) => !a.is_postable);
  const rows = toTree(accounts ?? []).filter(
    ({ account }) => !q || account.code.includes(q) || account.name.includes(q),
  );

  return (
    <div className="grid gap-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-xl font-bold">دليل الحسابات</h1>
        <AccountDialog groups={groups} />
      </div>

      <form className="flex max-w-md gap-2">
        <Input name="q" defaultValue={q} placeholder="بحث بالكود أو الاسم" />
        <Button type="submit" variant="outline">
          بحث
        </Button>
      </form>

      <div className="rounded-lg border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>الكود</TableHead>
              <TableHead>اسم الحساب</TableHead>
              <TableHead>النوع</TableHead>
              <TableHead>الحالة</TableHead>
              <TableHead />
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.map(({ account, depth }) => {
              const isSystem = systemIds.has(account.id);
              return (
                <TableRow key={account.id}>
                  <TableCell dir="ltr" className="text-end font-mono">
                    {account.code}
                  </TableCell>
                  <TableCell>
                    <div
                      className="flex items-center gap-2"
                      style={{ paddingInlineStart: `${depth * 1.5}rem` }}
                    >
                      <span className={account.is_postable ? "" : "font-bold"}>
                        {account.name}
                      </span>
                      {!account.is_postable && <Badge>تجميعي</Badge>}
                      {account.is_treasury && <Badge>خزينة/بنك</Badge>}
                      {isSystem && <Badge>حساب نظام</Badge>}
                    </div>
                  </TableCell>
                  <TableCell>{ACCOUNT_TYPE_LABELS[account.type as AccountType]}</TableCell>
                  <TableCell className={account.is_active ? "" : "text-muted-foreground"}>
                    {account.is_active ? "نشط" : "معطّل"}
                  </TableCell>
                  <TableCell>
                    <div className="flex justify-end gap-2">
                      <AccountDialog account={account} groups={groups} isSystem={isSystem} />
                      {!isSystem && (
                        <DeleteAccountButton
                          id={account.id}
                          label={`${account.code} - ${account.name}`}
                        />
                      )}
                    </div>
                  </TableCell>
                </TableRow>
              );
            })}
            {rows.length === 0 && (
              <TableRow>
                <TableCell colSpan={5} className="py-6 text-center text-muted-foreground">
                  لا توجد حسابات مطابقة.
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </div>
    </div>
  );
}
