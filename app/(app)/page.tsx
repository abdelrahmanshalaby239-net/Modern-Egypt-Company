import Link from "next/link";

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { requireUser } from "@/lib/auth";
import { formatDate } from "@/lib/format";
import { ROLE_LABELS } from "@/lib/labels";
import { formatAmount, formatCents, sumAmounts } from "@/lib/money";

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
  const cards = [
    { title: "رصيد الخزينة والبنك", value: amount(summary?.treasury), href: "/treasury" },
    { title: "مستحقات العملاء", value: amount(summary?.receivables), href: "/customers" },
    { title: "مستحقات الموردين", value: amount(summary?.payables), href: "/suppliers" },
    { title: "قيمة المخزون", value: amount(summary?.inventory), href: "/inventory" },
    { title: "مبيعات الشهر", value: amount(summary?.month_sales), href: `/income-statement?${monthRange}` },
    {
      title: net < 0n ? "صافي خسارة الشهر" : "صافي ربح الشهر",
      value: formatCents(net < 0n ? -net : net),
      href: `/income-statement?${monthRange}`,
    },
  ];

  return (
    <div className="grid gap-4">
      <div>
        <h1 className="text-xl font-bold">{settings?.company_name}</h1>
        <p className="text-sm text-muted-foreground">
          مرحبًا {profile.full_name || profile.email} — {ROLE_LABELS[profile.role]}
          {summary && ` · الشهر من ${formatDate(summary.month_start)} إلى ${formatDate(summary.month_end)}`}
        </p>
      </div>

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {cards.map((card) => (
          <Link key={card.title} href={card.href} className="rounded-lg focus-visible:ring-[3px] focus-visible:ring-ring/50">
            <Card className="h-full transition-colors hover:border-primary">
              <CardHeader>
                <CardDescription>{card.title}</CardDescription>
                <CardTitle dir="ltr" className="text-end text-2xl tabular-nums">
                  {card.value}
                </CardTitle>
              </CardHeader>
            </Card>
          </Link>
        ))}
        <Link href="/inventory?low=1" className="rounded-lg focus-visible:ring-[3px] focus-visible:ring-ring/50">
          <Card className="h-full transition-colors hover:border-primary">
            <CardHeader>
              <CardDescription>أصناف تحت الحد الأدنى</CardDescription>
              <CardTitle
                dir="ltr"
                className={`text-end text-2xl tabular-nums ${(summary?.low_stock_items ?? 0) > 0 ? "text-warning" : ""}`}
              >
                {summary?.low_stock_items ?? 0}
              </CardTitle>
            </CardHeader>
          </Card>
        </Link>
      </div>

      <Card>
        <CardContent className="text-xs text-muted-foreground">
          الأرصدة من القيود المعتمدة. مبيعات الشهر = حسابات الإيرادات 41 بدون قيود الإقفال، وصافي ربح الشهر من قائمة
          الدخل لنفس الشهر. مستحقات الموردين بالرصيد الدائن لحسابهم.
        </CardContent>
      </Card>
    </div>
  );
}
