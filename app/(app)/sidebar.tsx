"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

import { cn } from "@/lib/utils";

type NavItem = { href: string; label: string };
type NavSection = { title?: string; items: NavItem[]; adminOnly?: boolean };

// القائمة تعرض ما نُفّذ فقط، وتُضاف العناصر مع كل مرحلة (SPEC §8)
const SECTIONS: NavSection[] = [
  { items: [{ href: "/", label: "الرئيسية" }] },
  { title: "المحاسبة", items: [{ href: "/accounts", label: "دليل الحسابات" }] },
  {
    title: "الإعدادات",
    adminOnly: true,
    items: [
      { href: "/settings", label: "بيانات الشركة والعملة" },
      { href: "/settings/system-accounts", label: "حسابات النظام" },
      { href: "/settings/users", label: "المستخدمون" },
    ],
  },
];

export function Sidebar({ isAdmin }: { isAdmin: boolean }) {
  const pathname = usePathname();

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
            const active = pathname === item.href;
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
