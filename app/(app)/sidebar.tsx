"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

import { cn } from "@/lib/utils";

type NavItem = { href: string; label: string };
type NavSection = { title?: string; items: NavItem[]; adminOnly?: boolean };

// القائمة تعرض ما نُفّذ فقط، وتُضاف العناصر مع كل مرحلة (SPEC §8)
const SECTIONS: NavSection[] = [
  { items: [{ href: "/", label: "الرئيسية" }] },
  {
    title: "المبيعات",
    items: [
      { href: "/sales", label: "فواتير المبيعات" },
      { href: "/customers", label: "العملاء" },
      { href: "/sales/item-profit", label: "أرباح الأصناف" },
    ],
  },
  {
    title: "المشتريات",
    items: [
      { href: "/purchases", label: "فواتير المشتريات" },
      { href: "/suppliers", label: "الموردين" },
    ],
  },
  {
    title: "المخزون",
    items: [
      { href: "/items", label: "الأصناف" },
      { href: "/inventory", label: "أرصدة المخزون" },
      { href: "/inventory/movements", label: "حركة صنف" },
      { href: "/stock-adjustments", label: "تسوية الجرد" },
    ],
  },
  {
    title: "التصنيع",
    items: [
      { href: "/formulas", label: "الوصفات" },
      { href: "/production", label: "تسجيل الإنتاج" },
      { href: "/production/report", label: "تقرير الإنتاج" },
    ],
  },
  {
    title: "الخزينة",
    items: [
      { href: "/vouchers/receipt", label: "سندات القبض" },
      { href: "/vouchers/payment", label: "سندات الصرف" },
      { href: "/treasury", label: "أرصدة الخزائن والبنوك" },
    ],
  },
  {
    title: "المحاسبة",
    items: [
      { href: "/accounts", label: "دليل الحسابات" },
      { href: "/journal", label: "قيود اليومية" },
      { href: "/ledger", label: "كشف حساب" },
      { href: "/trial-balance", label: "ميزان المراجعة" },
      { href: "/opening-balances", label: "الأرصدة الافتتاحية" },
    ],
  },
  {
    title: "الإعدادات",
    adminOnly: true,
    items: [
      { href: "/settings", label: "بيانات الشركة" },
      { href: "/settings/system-accounts", label: "حسابات النظام" },
      { href: "/settings/users", label: "المستخدمون" },
    ],
  },
];

// العنصر النشط: أطول رابط يطابق المسار أو يسبقه (مثل /vouchers/receipt/5 ← سندات القبض)
function activeHref(pathname: string): string | undefined {
  return SECTIONS.flatMap((s) => s.items.map((i) => i.href))
    .filter((href) => pathname === href || (href !== "/" && pathname.startsWith(`${href}/`)))
    .sort((a, b) => b.length - a.length)[0];
}

export function Sidebar({ isAdmin }: { isAdmin: boolean }) {
  const pathname = usePathname();
  const current = activeHref(pathname);

  return (
    <nav className="flex flex-col gap-5 p-4">
      {SECTIONS.filter((section) => isAdmin || !section.adminOnly).map((section, i) => (
        <div key={i} className="flex flex-col gap-1">
          {section.title && (
            <div className="px-3 pb-1 text-xs font-semibold text-muted-foreground">
              {section.title}
            </div>
          )}
          {section.items.map((item) => {
            const active = item.href === current;
            return (
              <Link
                key={item.href}
                href={item.href}
                aria-current={active ? "page" : undefined}
                className={cn(
                  "border-s-[3px] px-3 py-1.5 text-sm transition-colors hover:bg-accent",
                  active ? "border-primary font-semibold" : "border-transparent",
                )}
              >
                {item.label}
              </Link>
            );
          })}
        </div>
      ))}
    </nav>
  );
}
