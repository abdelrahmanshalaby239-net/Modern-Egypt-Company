import Link from "next/link";

import { cn } from "@/lib/utils";

// أجزاء الأرصدة الافتتاحية: كل جزء قيد مستقل على حسابات لا تتداخل (SPEC §6.1)
const TABS = [
  { part: "accounts", href: "/opening-balances", label: "أرصدة الحسابات" },
  { part: "parties", href: "/opening-balances/parties", label: "أرصدة العملاء والموردين" },
  { part: "inventory", href: "/opening-balances/inventory", label: "مخزون أول المدة" },
] as const;

export function OpeningTabs({ active }: { active: (typeof TABS)[number]["part"] }) {
  return (
    <nav className="flex gap-1 border-b">
      {TABS.map((tab) => (
        <Link
          key={tab.part}
          href={tab.href}
          aria-current={active === tab.part ? "page" : undefined}
          className={cn(
            "-mb-px border-b-2 px-3 py-2 text-sm transition-colors",
            active === tab.part
              ? "border-primary font-semibold"
              : "border-transparent text-muted-foreground hover:text-foreground",
          )}
        >
          {tab.label}
        </Link>
      ))}
    </nav>
  );
}
