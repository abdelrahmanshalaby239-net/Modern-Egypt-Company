import type { Metadata } from "next";

import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { requireAdmin } from "@/lib/auth";
import { RoleForm } from "./role-form";

export const metadata: Metadata = { title: "المستخدمون" };

export default async function UsersPage() {
  const { supabase, profile: me } = await requireAdmin();
  const { data: users } = await supabase
    .from("profiles")
    .select("id, email, full_name, role")
    .order("created_at");

  return (
    <div className="grid max-w-3xl gap-4">
      <h1 className="text-xl font-bold">المستخدمون</h1>
      <p className="text-sm text-muted-foreground">
        يُنشأ المستخدم الجديد من لوحة Supabase (Authentication)، ويظهر هنا بدور «محاسب».
      </p>
      <div className="rounded-lg border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>البريد الإلكتروني</TableHead>
              <TableHead>الاسم</TableHead>
              <TableHead>الدور</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {(users ?? []).map((user) => (
              <TableRow key={user.id}>
                <TableCell dir="ltr" className="text-end">
                  {user.email}
                </TableCell>
                <TableCell>{user.full_name}</TableCell>
                <TableCell>
                  <RoleForm id={user.id} role={user.role} isSelf={user.id === me.id} />
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
    </div>
  );
}
