"use client";

import { Fragment, useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  Calculator,
  ChartColumn,
  ChevronDown,
  Factory,
  House,
  Package,
  Settings,
  ShoppingCart,
  Wallet,
  type LucideIcon,
} from "lucide-react";

import { cn } from "@/lib/utils";

type NavItem = { href: string; label: string; adminOnly?: boolean };
type NavSection = { title?: string; icon: LucideIcon; items: NavItem[]; adminOnly?: boolean };

// القائمة تعرض ما نُفّذ فقط، وتُضاف العناصر مع كل مرحلة (SPEC §8)
const SECTIONS: NavSection[] = [
  { icon: House, items: [{ href: "/", label: "الرئيسية" }] },
  {
    title: "المبيعات",
    icon: ChartColumn,
    items: [
      { href: "/sales", label: "فواتير المبيعات" },
      { href: "/customers", label: "العملاء" },
      { href: "/sales/item-profit", label: "أرباح الأصناف" },
    ],
  },
  {
    title: "المشتريات",
    icon: ShoppingCart,
    items: [
      { href: "/purchases", label: "فواتير المشتريات" },
      { href: "/suppliers", label: "الموردين" },
    ],
  },
  {
    title: "المخزون",
    icon: Package,
    items: [
      { href: "/items", label: "الأصناف" },
      { href: "/inventory", label: "أرصدة المخزون" },
      { href: "/inventory/movements", label: "حركة صنف" },
      { href: "/stock-adjustments", label: "تسوية الجرد" },
    ],
  },
  {
    title: "التصنيع",
    icon: Factory,
    items: [
      { href: "/formulas", label: "الوصفات" },
      { href: "/production", label: "تسجيل الإنتاج" },
      { href: "/production/report", label: "تقرير الإنتاج" },
    ],
  },
  {
    title: "الخزينة",
    icon: Wallet,
    items: [
      { href: "/vouchers/receipt", label: "سندات القبض" },
      { href: "/vouchers/payment", label: "سندات الصرف" },
      { href: "/treasury", label: "أرصدة الخزائن والبنوك" },
    ],
  },
  {
    title: "المحاسبة",
    icon: Calculator,
    items: [
      { href: "/accounts", label: "دليل الحسابات" },
      { href: "/journal", label: "قيود اليومية" },
      { href: "/ledger", label: "كشف حساب" },
      { href: "/trial-balance", label: "ميزان المراجعة" },
      { href: "/income-statement", label: "قائمة الدخل" },
      { href: "/balance-sheet", label: "الميزانية العمومية" },
      { href: "/opening-balances", label: "الأرصدة الافتتاحية" },
      { href: "/closing", label: "إقفال السنة", adminOnly: true },
    ],
  },
  {
    title: "الإعدادات",
    icon: Settings,
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

// القسم الذي يحتوي الصفحة النشطة (يُفتح تلقائيًا)
function sectionOf(href: string | undefined): string | undefined {
  return SECTIONS.find((s) => s.title && s.items.some((i) => i.href === href))?.title;
}

export function Sidebar({ isAdmin }: { isAdmin: boolean }) {
  const pathname = usePathname();
  const current = activeHref(pathname);
  const activeSection = sectionOf(current);

  // الأقسام مطوية افتراضيًا: عند الانتقال لقسم آخر يُفتح قسم الصفحة النشطة وحده، والباقي بالضغط
  const [open, setOpen] = useState<ReadonlySet<string>>(() => new Set(activeSection ? [activeSection] : []));
  const [lastActive, setLastActive] = useState(activeSection);
  if (activeSection !== lastActive) {
    setLastActive(activeSection);
    setOpen(new Set(activeSection ? [activeSection] : []));
  }

  const toggle = (title: string) =>
    setOpen((prev) => {
      const next = new Set(prev);
      if (next.has(title)) next.delete(title);
      else next.add(title);
      return next;
    });

  return (
    <nav className="flex flex-col gap-1 p-3">
      {SECTIONS.filter((section) => isAdmin || !section.adminOnly).map((section, i) => {
        const items = section.items.filter((item) => isAdmin || !item.adminOnly);
        const Icon = section.icon;

        // عنصر بلا قسم (الرئيسية): رابط مباشر في المستوى الأول
        if (!section.title) {
          return (
            <Fragment key={i}>
              {items.map((item) => {
                const active = item.href === current;
                return (
                  <Link
                    key={item.href}
                    href={item.href}
                    aria-current={active ? "page" : undefined}
                    className={cn(
                      "flex items-center gap-3 rounded-lg px-3 py-2 text-sm transition-colors",
                      active ? "bg-lavender font-semibold text-foreground" : "text-foreground hover:bg-muted",
                    )}
                  >
                    <Icon className="size-[18px] shrink-0" strokeWidth={1.75} />
                    {item.label}
                  </Link>
                );
              })}
            </Fragment>
          );
        }

        const title = section.title;
        const expanded = open.has(title);
        const containsActive = title === activeSection;
        const panelId = `nav-section-${i}`;

        return (
          <div key={title}>
            <button
              type="button"
              onClick={() => toggle(title)}
              aria-expanded={expanded}
              aria-controls={panelId}
              className={cn(
                "flex w-full items-center gap-3 rounded-lg px-3 py-2 text-start text-sm transition-colors hover:bg-muted",
                containsActive ? "font-semibold text-foreground" : "text-foreground",
              )}
            >
              <Icon className="size-[18px] shrink-0" strokeWidth={1.75} />
              <span className="flex-1">{title}</span>
              <ChevronDown
                aria-hidden
                className={cn(
                  "size-4 shrink-0 text-muted-foreground transition-transform duration-200",
                  expanded ? "rotate-0" : "rotate-90",
                )}
              />
            </button>
            <div
              id={panelId}
              inert={!expanded}
              className={cn(
                "grid transition-[grid-template-rows,opacity] duration-200 ease-out",
                expanded ? "grid-rows-[1fr] opacity-100" : "grid-rows-[0fr] opacity-0",
              )}
            >
              <div className="overflow-hidden">
                <div className="ms-[1.3rem] mt-0.5 mb-1 flex flex-col gap-0.5 border-s ps-3">
                  {items.map((item) => {
                    const active = item.href === current;
                    return (
                      <Link
                        key={item.href}
                        href={item.href}
                        aria-current={active ? "page" : undefined}
                        className={cn(
                          "rounded-md px-3 py-1.5 text-sm transition-colors",
                          active
                            ? "bg-lavender font-semibold text-foreground"
                            : "text-muted-foreground hover:bg-muted hover:text-foreground",
                        )}
                      >
                        {item.label}
                      </Link>
                    );
                  })}
                </div>
              </div>
            </div>
          </div>
        );
      })}
    </nav>
  );
}
