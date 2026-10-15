import Link from "next/link";
import { ChevronLeft } from "lucide-react";

import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { requireUser } from "@/lib/auth";
import { formatDate } from "@/lib/format";
import { ROLE_LABELS } from "@/lib/labels";
import { formatAmount, formatCents, sumAmounts } from "@/lib/money";
import { cn } from "@/lib/utils";

// عرض نسبي للأشرطة فقط (ليس حسابًا ماليًا): القيمة المطلقة ÷ أكبر قيمة، بالقروش كـ BigInt
function barPercent(cents: bigint, maxCents: bigint): number {
  if (maxCents <= 0n || cents === 0n) return 0;
  const abs = cents < 0n ? -cents : cents;
  return Math.max(2, Number((abs * 100n) / maxCents));
}

// الشاشة الرئيسية (SPEC §8): كل الأرقام من الأستاذ، ومبيعات الشهر وصافي ربحه بنفس تعريف قائمة الدخل
export default async function HomePage() {
  const { supabase, profile } = await requireUser();
  const [{ data: settings }, { data: summary }] = await Promise.all([
    supabase.from("settings").select("company_name").eq("id", 1).single(),
    supabase.rpc("dashboard_summary").maybeSingle(),
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
      href: `/income-statement?${monthRange}`,
      className: "border-transparent bg-lavender",
    },
    {
      title: net < 0n ? "صافي خسارة الشهر" : "صافي ربح الشهر",
      caption: "بعد المصروفات",
      value: formatCents(net < 0n ? -net : net),
      href: `/income-statement?${monthRange}`,
      className: "border-transparent bg-muted",
    },
  ];

  const indicators = [
    { title: "رصيد الخزينة والبنك", value: summary?.treasury, href: "/treasury", bar: "bg-chart-1" },
    { title: "قيمة المخزون", value: summary?.inventory, href: "/inventory", bar: "bg-chart-2" },
    { title: "مستحقات العملاء", value: summary?.receivables, href: "/customers", bar: "bg-chart-3" },
    { title: "مستحقات الموردين", value: summary?.payables, href: "/suppliers", bar: "bg-chart-4" },
  ].map((i) => ({ ...i, cents: sumAmounts([i.value]) }));
  const maxCents = indicators.reduce((max, i) => {
    const abs = i.cents < 0n ? -i.cents : i.cents;
    return abs > max ? abs : max;
  }, 0n);
  const lowStock = summary?.low_stock_items ?? 0;

  return (
    <div className="grid gap-6">
      <div className="grid gap-1">
        <h1 className="text-2xl font-bold tracking-tight">{settings?.company_name}</h1>
        <p className="text-sm text-muted-foreground">
          مرحبًا {profile.full_name || profile.email} — {ROLE_LABELS[profile.role]}
          {summary && ` · الشهر من ${formatDate(summary.month_start)} إلى ${formatDate(summary.month_end)}`}
        </p>
      </div>

      <div className="grid gap-4 lg:grid-cols-5">
        <div className="grid content-start gap-4 sm:grid-cols-2 lg:col-span-3 lg:col-start-3">
          {highlights.map((card) => (
            <Link
              key={card.href + card.title}
              href={card.href}
              className="group rounded-2xl focus-visible:ring-[3px] focus-visible:ring-ring/50 focus-visible:outline-none"
            >
              <Card className={cn("h-full gap-6 px-6 py-6 shadow-none transition-shadow group-hover:shadow-sm", card.className)}>
                <div className="flex items-center justify-between gap-2">
                  <span className="text-sm font-semibold">{card.title}</span>
                  <ChevronLeft
                    aria-hidden
                    className="size-4 text-muted-foreground transition-transform group-hover:-translate-x-0.5"
                  />
                </div>
                <div className="grid gap-1">
                  <span dir="ltr" className="text-end text-3xl font-bold tracking-tight tabular-nums">
                    {card.value}
                  </span>
                  <span className="text-sm text-muted-foreground">{card.caption}</span>
                </div>
              </Card>
            </Link>
          ))}

          <Card className="shadow-none sm:col-span-2">
            <CardContent className="text-xs leading-relaxed text-muted-foreground">
              الأرصدة من القيود المعتمدة. مبيعات الشهر = حسابات الإيرادات 41 بدون قيود الإقفال، وصافي ربح الشهر من قائمة
              الدخل لنفس الشهر. مستحقات الموردين بالرصيد الدائن لحسابهم.
            </CardContent>
          </Card>
        </div>

        <Card className="lg:col-span-2 lg:col-start-1 lg:row-start-1">
          <CardHeader>
            <CardTitle className="text-lg">أهم المؤشرات</CardTitle>
          </CardHeader>
          <CardContent className="grid gap-1">
            {indicators.map((i) => (
              <Link
                key={i.title}
                href={i.href}
                className="grid grid-cols-[minmax(0,9rem)_minmax(0,1fr)_auto] items-center gap-3 rounded-lg px-2 py-3 transition-colors hover:bg-muted focus-visible:ring-[3px] focus-visible:ring-ring/50 focus-visible:outline-none"
              >
                <span className="truncate text-sm text-muted-foreground">{i.title}</span>
                <span className="h-2 rounded-full bg-muted" aria-hidden>
                  <span
                    className={cn("block h-full rounded-full", i.bar)}
                    style={{ width: `${barPercent(i.cents, maxCents)}%` }}
                  />
                </span>
                <span dir="ltr" className="text-end text-sm font-semibold tabular-nums">
                  {amount(i.value)}
                </span>
              </Link>
            ))}
            <Link
              href="/inventory?low=1"
              className="mt-1 flex items-center justify-between gap-3 rounded-lg border-t px-2 pt-4 pb-3 transition-colors hover:bg-muted focus-visible:ring-[3px] focus-visible:ring-ring/50 focus-visible:outline-none"
            >
              <span className="text-sm text-muted-foreground">أصناف تحت الحد الأدنى</span>
              <span
                dir="ltr"
                className={cn("text-end text-sm font-semibold tabular-nums", lowStock > 0 && "text-warning")}
              >
                {lowStock}
              </span>
            </Link>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
