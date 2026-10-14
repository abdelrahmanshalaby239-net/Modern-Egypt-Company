import type { Metadata } from "next";
import Link from "next/link";

import { requireUser } from "@/lib/auth";
import { formatDate, yearStartIso } from "@/lib/format";
import { ITEM_TYPES, ITEM_TYPE_LABELS } from "@/lib/labels";
import { parseUnitPrice, plainUnitPrice } from "@/lib/quantity";
import { OpeningTabs } from "../opening-tabs";
import { PostedOpening } from "../posted-opening";
import { StockOpeningForm } from "./stock-opening-form";

export const metadata: Metadata = { title: "مخزون أول المدة" };

export default async function StockOpeningPage() {
  const { supabase } = await requireUser();

  // جزء المخزون النشط (غير الملغى). جزءا الحسابات والأطراف مستقلان لا يمنعانه.
  const { data: openings } = await supabase.rpc("active_openings");
  const active = (openings ?? []).find((o) => o.part === "inventory");

  const [{ data: items }, { data: capital }] = active
    ? [{ data: [] }, { data: null }]
    : await Promise.all([
        supabase
          .from("items")
          .select("id, code, name, type, unit, default_cost::text")
          .eq("is_active", true)
          .order("code"),
        supabase
          .from("system_accounts")
          .select("account:accounts(code, name)")
          .eq("key", "capital")
          .single(),
      ]);

  const groups = ITEM_TYPES.map((type) => ({
    title: ITEM_TYPE_LABELS[type],
    items: (items ?? [])
      .filter((i) => i.type === type)
      .map(({ id, code, name, unit, default_cost }) => ({
        id,
        code,
        name,
        unit,
        // التكلفة الافتراضية من بطاقة الصنف تُقترح فقط، والمعتمد هو ما يؤكده المستخدم
        suggested_cost: default_cost && default_cost !== "0.0000" ? plainUnitPrice(parseUnitPrice(default_cost) ?? 0n) : "",
      })),
  }));

  return (
    <div className="grid max-w-4xl gap-4">
      <h1 className="text-xl font-bold">الأرصدة الافتتاحية</h1>
      <OpeningTabs active="inventory" />
      {active ? (
        <PostedOpening title="مخزون أول المدة" entry={active} />
      ) : (items ?? []).length === 0 ? (
        <p className="text-sm text-muted-foreground">
          أضف{" "}
          <Link href="/items" className="font-semibold text-foreground underline">
            الأصناف
          </Link>{" "}
          أولًا، ثم سجّل كمياتها وتكلفتها هنا.
        </p>
      ) : (
        <>
          <p className="text-sm text-muted-foreground">
            كمية كل صنف في أول المدة وتكلفة الوحدة. القيمة تُسجَّل على حساب المخزون حسب نوع الصنف، وتصبح
            تكلفة الوحدة أول متوسط تكلفة للصنف. تكلفة الوحدة مقترحة من التكلفة الافتراضية في بطاقة الصنف ويمكن
            تعديلها، ولا يُحتسب إلا الصنف الذي تُدخل له كمية.
          </p>
          <StockOpeningForm
            groups={groups}
            defaultDate={formatDate(yearStartIso())}
            capitalLabel={capital?.account ? `${capital.account.code} - ${capital.account.name}` : "رأس المال"}
          />
        </>
      )}
    </div>
  );
}
