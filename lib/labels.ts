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

// أنواع القيود (SPEC §9: source_type)
export const SOURCE_TYPE_LABELS: Record<string, string> = {
  manual: "يومية",
  adjustment: "تسوية",
  opening: "افتتاحي",
  reversal: "عكسي",
  purchase: "مشتريات",
  sale: "مبيعات",
  voucher: "سند",
  production: "إنتاج",
  stock_adjustment: "تسوية جرد",
  closing: "إقفال",
};

// العملاء والموردون: نفس الشاشات والإجراءات بجدولين منفصلين
export const PARTY_KINDS = ["customer", "supplier"] as const;
export type PartyKind = (typeof PARTY_KINDS)[number];

export const PARTY_LABELS: Record<PartyKind, { one: string; many: string; table: "customers" | "suppliers" }> = {
  customer: { one: "عميل", many: "العملاء", table: "customers" },
  supplier: { one: "مورد", many: "الموردين", table: "suppliers" },
};

// سندات القبض والصرف (SPEC §6.1)
export const VOUCHER_KINDS = ["receipt", "payment"] as const;
export type VoucherKind = (typeof VOUCHER_KINDS)[number];

export const VOUCHER_LABELS: Record<VoucherKind, { one: string; many: string; party: string }> = {
  receipt: { one: "سند قبض", many: "سندات القبض", party: "استلمنا من" },
  payment: { one: "سند صرف", many: "سندات الصرف", party: "صرفنا إلى" },
};

// طرف السند: عميل أو مورد أو حساب آخر
export const COUNTERPART_LABELS: Record<string, string> = {
  customer: "عميل",
  supplier: "مورد",
  account: "حساب",
};

export function isVoucherKind(value: string): value is VoucherKind {
  return VOUCHER_KINDS.includes(value as VoucherKind);
}
