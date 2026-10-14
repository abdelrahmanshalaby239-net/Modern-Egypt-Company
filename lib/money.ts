// المبالغ نصوص طوال الطريق (قاعدة البيانات numeric(18,2)).
// أي حساب في الواجهة يتم بالقروش كـ BigInt، ولا يُستخدم Number للمال أبدًا.

const AMOUNT = /^(-)?(\d{1,16})(?:\.(\d{1,2}))?$/;

// "1,234.5" → 123450n. يرجع null لو النص غير صالح. الفارغ = صفر.
export function parseCents(value: string, { signed = false } = {}): bigint | null {
  const text = value.trim().replace(/,/g, "");
  if (text === "") return 0n;
  const match = text.match(AMOUNT);
  if (!match || (match[1] && !signed)) return null;
  const cents = BigInt(match[2]) * 100n + BigInt((match[3] ?? "").padEnd(2, "0"));
  return match[1] ? -cents : cents;
}

// 123450n → "1,234.50"
export function formatCents(cents: bigint): string {
  const negative = cents < 0n;
  const abs = negative ? -cents : cents;
  const whole = (abs / 100n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  const fraction = (abs % 100n).toString().padStart(2, "0");
  return `${negative ? "-" : ""}${whole}.${fraction}`;
}

// 123450n → "1234.50" (للإرسال إلى قاعدة البيانات)
export function plainCents(cents: bigint): string {
  return formatCents(cents).replace(/,/g, "");
}

// مبلغ من قاعدة البيانات ("-99800.00") → "-99,800.00"
export function formatAmount(value: string | null | undefined): string {
  if (value == null || value === "") return "";
  const cents = parseCents(value, { signed: true });
  return cents === null ? value : formatCents(cents);
}

// مجموع مبالغ نصية من قاعدة البيانات
export function sumAmounts(values: (string | null | undefined)[]): bigint {
  return values.reduce<bigint>((total, v) => total + (parseCents(v ?? "", { signed: true }) ?? 0n), 0n);
}

// رصيد جارٍ (مدين موجب، دائن سالب) → "99,800.00 مدين"
export function formatBalance(value: string | null | undefined): string {
  const cents = parseCents(value ?? "", { signed: true }) ?? 0n;
  if (cents === 0n) return formatCents(0n);
  return `${formatCents(cents < 0n ? -cents : cents)} ${cents > 0n ? "مدين" : "دائن"}`;
}

// نسبة مئوية بخانتين (مثل هامش الربح = الربح ÷ المبيعات × 100) مقربة نصف لأعلى بعيدًا عن الصفر
export function formatPercent(numeratorCents: bigint, denominatorCents: bigint): string {
  if (denominatorCents <= 0n) return "";
  const negative = numeratorCents < 0n;
  const abs = negative ? -numeratorCents : numeratorCents;
  const hundredths = (2n * abs * 10000n + denominatorCents) / (2n * denominatorCents);
  return `${negative && hundredths > 0n ? "-" : ""}${hundredths / 100n}.${(hundredths % 100n).toString().padStart(2, "0")}%`;
}
