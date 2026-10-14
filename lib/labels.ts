export const ROLE_LABELS = {
  admin: "مدير النظام",
  accountant: "محاسب",
} as const;

export const ACCOUNT_TYPES = ["asset", "liability", "equity", "revenue", "expense"] as const;
export type AccountType = (typeof ACCOUNT_TYPES)[number];

export const ACCOUNT_TYPE_LABELS: Record<AccountType, string> = {
  asset: "أصول",
  liability: "خصوم",
  equity: "حقوق ملكية",
  revenue: "إيرادات",
  expense: "مصروفات",
};

// مفاتيح حسابات النظام والنوع المطلوب لكل منها (يطابق trigger قاعدة البيانات)
export const SYSTEM_ACCOUNT_KEYS: { key: string; label: string; type: AccountType }[] = [
  { key: "receivables", label: "العملاء", type: "asset" },
  { key: "payables", label: "الموردين", type: "liability" },
  { key: "inventory_raw", label: "مخزون المواد الخام", type: "asset" },
  { key: "inventory_packaging", label: "مخزون مواد التعبئة والتغليف", type: "asset" },
  { key: "inventory_finished", label: "مخزون المنتج التام", type: "asset" },
  { key: "sales_revenue", label: "إيرادات المبيعات", type: "revenue" },
  { key: "cogs", label: "تكلفة البضاعة المباعة", type: "expense" },
  { key: "capital", label: "رأس المال", type: "equity" },
  { key: "retained_earnings", label: "الأرباح المرحّلة", type: "equity" },
  { key: "inventory_adjustment", label: "فروقات جرد المخزون", type: "expense" },
];
