import Link from "next/link";
import {
  ChartColumn,
  ChevronLeft,
  Clock,
  CreditCard,
  Factory,
  FilePlus,
  Package,
  PackagePlus,
  ShoppingCart,
  TriangleAlert,
  Truck,
  Users,
  Wallet,
  Zap,
  type LucideIcon,
} from "lucide-react";

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { requireUser } from "@/lib/auth";
import { formatDate } from "@/lib/format";
import { formatAmount, formatCents, sumAmounts } from "@/lib/money";
import { cn } from "@/lib/utils";

const RECENT_LIMIT = 6;

// إجراءات سريعة لصفحات إنشاء قائمة (متاحة لكل الأدوار: admin و accountant)
const QUICK_ACTIONS: { href: string; label: string; icon: LucideIcon }[] = [
  { href: "/sales/new", label: "فاتورة بيع", icon: ShoppingCart },
  { href: "/purchases/new", label: "فاتورة شراء", icon: FilePlus },
  { href: "/production/new", label: "تسجيل إنتاج", icon: Factory },
  { href: "/vouchers/receipt/new", label: "سند قبض", icon: Wallet },
  { href: "/vouchers/payment/new", label: "سند صرف", icon: CreditCard },
  { href: "/items/new", label: "إضافة صنف", icon: PackagePlus },
];

type RecentRow = {
  key: string;
  type: string;
  href: string;
  docNo: number;
  date: string;
  party: string;
  amount: string;
  cancelled: boolean;
  status: { active: string; cancelled: string };
  entryId: number;
};

const FEMININE = { active: "معتمدة", cancelled: "ملغاة" };
const MASCULINE = { active: "معتمد", cancelled: "ملغى" };

// الشاشة الرئيسية (SPEC §8): كل الأرقام من الأستاذ، ومبيعات الشهر وصافي ربحه بنفس تعريف قائمة الدخل.
// آخر العمليات من دوال القوائم الموجودة (قراءة فقط وبصلاحيات المستخدم).
export default async function HomePage() {
  const { supabase } = await requireUser();
  const [{ data: summary }, sales, purchases, receipts, payments, production] = await Promise.all([
    supabase.rpc("dashboard_summary").maybeSingle(),
    supabase
      .rpc("sales_invoice_list", {})
      .order("doc_date", { ascending: false })
      .order("journal_entry_id", { ascending: false })
      .limit(RECENT_LIMIT),
    supabase
      .rpc("purchase_invoice_list", {})
      .order("doc_date", { ascending: false })
      .order("journal_entry_id", { ascending: false })
      .limit(RECENT_LIMIT),
    supabase
      .rpc("voucher_list", { p_kind: "receipt" })
      .order("doc_date", { ascending: false })
      .order("journal_entry_id", { ascending: false })
      .limit(RECENT_LIMIT),
    supabase
      .rpc("voucher_list", { p_kind: "payment" })
      .order("doc_date", { ascending: false })
      .order("journal_entry_id", { ascending: false })
      .limit(RECENT_LIMIT),
    supabase
      .rpc("production_list", {})
      .order("doc_date", { ascending: false })
      .order("journal_entry_id", { ascending: false })
      .limit(RECENT_LIMIT),
  ]);

  const monthRange = summary
    ? `from=${encodeURIComponent(formatDate(summary.month_start))}&to=${encodeURIComponent(formatDate(summary.month_end))}`
    : "";
  const net = sumAmounts([summary?.month_net_profit]);
  const amount = (value: string | undefined) => formatAmount(value ?? "0.00");

  const highlights = [
    {
      title: "مبيعات الشهر",
      caption: "إجمالي المبيعات",
      value: amount(summary?.month_sales),
      icon: ShoppingCart,
      className: "bg-lavender",
    },
    {
      title: net < 0n ? "صافي خسارة الشهر" : "صافي ربح الشهر",
      caption: "بعد المصروفات",
      value: formatCents(net < 0n ? -net : net),
      icon: ChartColumn,
      className: "bg-secondary",
    },
  ];

  const lowStock = summary?.low_stock_items ?? 0;
  const indicators = [
    { title: "رصيد الخزينة والبنك", value: amount(summary?.treasury), href: "/treasury", icon: Wallet },
    { title: "قيمة المخزون", value: amount(summary?.inventory), href: "/inventory", icon: Package },
    { title: "مستحقات العملاء", value: amount(summary?.receivables), href: "/customers", icon: Users },
    { title: "مستحقات الموردين", value: amount(summary?.payables), href: "/suppliers", icon: Truck },
    {
      title: "أصناف تحت الحد الأدنى",
      value: String(lowStock),
      href: "/inventory?low=1",
      icon: TriangleAlert,
      warn: lowStock > 0,
    },
  ];

  const rows: RecentRow[] = [
    ...(sales.data ?? []).map((d) => ({
      key: `s${d.id}`,
      type: "فاتورة بيع",
      href: `/sales/${d.id}`,
      docNo: d.doc_no,
      date: d.doc_date,
      party: d.customer_name,
      amount: d.total,
      cancelled: d.is_cancelled,
      status: FEMININE,
      entryId: d.journal_entry_id,
    })),
    ...(purchases.data ?? []).map((d) => ({
      key: `p${d.id}`,
      type: "فاتورة شراء",
      href: `/purchases/${d.id}`,
      docNo: d.doc_no,
      date: d.doc_date,
      party: d.supplier_name,
      amount: d.total,
      cancelled: d.is_cancelled,
      status: FEMININE,
      entryId: d.journal_entry_id,
    })),
    ...(receipts.data ?? []).map((d) => ({
      key: `r${d.id}`,
      type: "سند قبض",
      href: `/vouchers/receipt/${d.id}`,
      docNo: d.doc_no,
      date: d.doc_date,
      party: d.party_name,
      amount: d.amount,
      cancelled: d.is_cancelled,
      status: MASCULINE,
      entryId: d.journal_entry_id,
    })),
    ...(payments.data ?? []).map((d) => ({
      key: `v${d.id}`,
      type: "سند صرف",
      href: `/vouchers/payment/${d.id}`,
      docNo: d.doc_no,
      date: d.doc_date,
      party: d.party_name,
      amount: d.amount,
      cancelled: d.is_cancelled,
      status: MASCULINE,
      entryId: d.journal_entry_id,
    })),
    ...(production.data ?? []).map((d) => ({
      key: `m${d.id}`,
      type: "تسجيل إنتاج",
      href: `/production/${d.id}`,
      docNo: d.doc_no,
      date: d.doc_date,
      party: d.item_name,
      amount: d.total_cost,
      cancelled: d.is_cancelled,
      status: MASCULINE,
      entryId: d.journal_entry_id,
    })),
  ]
    .sort((a, b) => (a.date === b.date ? b.entryId - a.entryId : a.date < b.date ? 1 : -1))
    .slice(0, RECENT_LIMIT);

  return (
    <div className="grid gap-6">
      <div className="grid gap-1">
        <h1 className="text-2xl font-bold tracking-tight">لوحة التحكم</h1>
        {summary && (
          <p className="text-sm text-muted-foreground">
            الفترة من {formatDate(summary.month_start)} إلى {formatDate(summary.month_end)}
          </p>
        )}
      </div>

      <div className="grid gap-5 lg:grid-cols-3">
        {/* بطاقتا الشهر */}
        <div className="grid gap-5 sm:grid-cols-2 lg:col-span-2 lg:col-start-2 lg:row-start-1">
          {highlights.map((card) => {
            const Icon = card.icon;
            return (
              <Link
                key={card.title}
                href={`/income-statement?${monthRange}`}
                className={cn(
                  "group flex flex-col gap-4 rounded-2xl p-6 transition-shadow hover:shadow-sm focus-visible:ring-[3px] focus-visible:ring-ring/50 focus-visible:outline-none",
                  card.className,
                )}
              >
                <div className="flex items-start justify-between gap-3">
                  <span className="pt-1 text-base font-semibold">{card.title}</span>
                  <span className="flex size-12 shrink-0 items-center justify-center rounded-full bg-background">
                    <Icon className="size-5" strokeWidth={1.75} aria-hidden />
                  </span>
                </div>
                <span dir="ltr" className="text-end text-3xl font-bold tracking-tight tabular-nums">
                  {card.value}
                </span>
                <div className="flex items-center justify-between gap-3">
                  <span className="text-sm text-muted-foreground">{card.caption}</span>
                  <span className="flex size-8 items-center justify-center rounded-full bg-background">
                    <ChevronLeft
                      className="size-4 transition-transform group-hover:-translate-x-0.5"
                      aria-hidden
                    />
                  </span>
                </div>
              </Link>
            );
          })}
        </div>

        {/* أهم المؤشرات (يمين) */}
        <Card className="gap-0 py-0 lg:col-start-1 lg:row-span-2 lg:row-start-1">
          <CardHeader className="flex-row items-center gap-2 border-b py-5">
            <ChartColumn className="size-5" strokeWidth={1.75} aria-hidden />
            <CardTitle className="text-lg">أهم المؤشرات</CardTitle>
          </CardHeader>
          <CardContent className="grid px-2 py-2">
            {indicators.map((i, index) => {
              const Icon = i.icon;
              return (
                <Link
                  key={i.title}
                  href={i.href}
                  className={cn(
                    "flex items-center gap-3 rounded-lg px-3 py-4 transition-colors hover:bg-muted focus-visible:ring-[3px] focus-visible:ring-ring/50 focus-visible:outline-none",
                    index > 0 && "border-t",
                  )}
                >
                  <Icon
                    className={cn("size-5 shrink-0", i.warn ? "text-warning" : "text-muted-foreground")}
                    strokeWidth={1.75}
                    aria-hidden
                  />
                  <span className="flex-1 text-sm text-muted-foreground">{i.title}</span>
                  <span
                    dir="ltr"
                    className={cn("text-end text-base font-semibold tabular-nums", i.warn && "text-warning")}
                  >
                    {i.value}
                  </span>
                </Link>
              );
            })}
          </CardContent>
        </Card>

        {/* العمليات السريعة */}
        <Card className="lg:col-span-2 lg:col-start-2 lg:row-start-2">
          <CardHeader className="flex-row items-center gap-2">
            <Zap className="size-5" strokeWidth={1.75} aria-hidden />
            <CardTitle className="text-lg">العمليات السريعة</CardTitle>
          </CardHeader>
          <CardContent className="grid grid-cols-2 gap-3 sm:grid-cols-3">
            {QUICK_ACTIONS.map((action) => {
              const Icon = action.icon;
              return (
                <Link
                  key={action.href}
                  href={action.href}
                  className="flex flex-col items-center justify-center gap-2 rounded-xl border px-3 py-5 text-sm font-medium transition-colors hover:border-foreground/20 hover:bg-muted focus-visible:ring-[3px] focus-visible:ring-ring/50 focus-visible:outline-none"
                >
                  <Icon className="size-6" strokeWidth={1.5} aria-hidden />
                  {action.label}
                </Link>
              );
            })}
          </CardContent>
        </Card>

        {/* آخر العمليات */}
        <Card className="lg:col-span-3">
          <CardHeader className="flex-row items-center justify-between gap-2">
            <div className="flex items-center gap-2">
              <Clock className="size-5" strokeWidth={1.75} aria-hidden />
              <CardTitle className="text-lg">آخر العمليات</CardTitle>
            </div>
            <Link
              href="/journal"
              className="flex items-center gap-1 rounded-lg bg-muted px-3 py-1.5 text-xs font-medium transition-colors hover:bg-secondary"
            >
              عرض الكل
              <ChevronLeft className="size-3.5" aria-hidden />
            </Link>
          </CardHeader>
          <CardContent>
            <div className="overflow-hidden rounded-xl border">
              <Table>
                <TableHeader className="bg-muted">
                  <TableRow className="hover:bg-muted">
                    <TableHead>نوع العملية</TableHead>
                    <TableHead>رقم المستند</TableHead>
                    <TableHead>التاريخ</TableHead>
                    <TableHead>الجهة / الصنف</TableHead>
                    <TableHead className="text-end">القيمة</TableHead>
                    <TableHead>الحالة</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {rows.map((r) => (
                    <TableRow key={r.key}>
                      <TableCell>
                        <Link href={r.href} className="underline-offset-4 hover:underline">
                          {r.type}
                        </Link>
                      </TableCell>
                      <TableCell className="tabular-nums">{r.docNo}</TableCell>
                      <TableCell dir="ltr" className="text-end tabular-nums">
                        {formatDate(r.date)}
                      </TableCell>
                      <TableCell className="max-w-56 truncate">{r.party}</TableCell>
                      <TableCell dir="ltr" className="text-start tabular-nums">
                        {formatAmount(r.amount)}
                      </TableCell>
                      <TableCell>
                        <span
                          className={cn(
                            "inline-flex rounded-full px-2.5 py-0.5 text-xs font-medium",
                            r.cancelled ? "bg-destructive/10 text-destructive" : "bg-success/10 text-success",
                          )}
                        >
                          {r.cancelled ? r.status.cancelled : r.status.active}
                        </span>
                      </TableCell>
                    </TableRow>
                  ))}
                  {rows.length === 0 && (
                    <TableRow className="hover:bg-transparent">
                      <TableCell colSpan={6} className="py-8 text-center text-muted-foreground">
                        لا توجد عمليات مسجلة بعد.
                      </TableCell>
                    </TableRow>
                  )}
                </TableBody>
              </Table>
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
