// الكميات (numeric(18,3)) وتكلفة الوحدة (numeric(18,4)) نصوص طوال الطريق مثل المبالغ.
// الحساب في الواجهة (معاينة إجمالي السطر فقط) يتم كـ BigInt بوحدات صحيحة، ولا يُستخدم Number أبدًا.
// القيمة المعتمدة دائمًا هي ما تحسبه قاعدة البيانات.

const QTY = /^(\d{1,15})(?:\.(\d{1,3}))?$/;
const UNIT_PRICE = /^(\d{1,14})(?:\.(\d{1,4}))?$/;

function parseScaled(value: string, pattern: RegExp, scale: number): bigint | null {
  const text = value.trim().replace(/,/g, "");
  if (text === "") return 0n;
  const match = text.match(pattern);
  if (!match) return null;
  return BigInt(match[1]) * 10n ** BigInt(scale) + BigInt((match[2] ?? "").padEnd(scale, "0"));
}

function formatScaled(units: bigint, scale: number, minDecimals: number): string {
  const negative = units < 0n;
  const abs = negative ? -units : units;
  const base = 10n ** BigInt(scale);
  const whole = (abs / base).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  let fraction = (abs % base).toString().padStart(scale, "0");
  while (fraction.length > minDecimals && fraction.endsWith("0")) fraction = fraction.slice(0, -1);
  return `${negative ? "-" : ""}${whole}${fraction ? `.${fraction}` : ""}`;
}

// "1,250.5" → 1250500n (بالألف). يرجع null لو النص غير صالح (سالب أو أكثر من 3 خانات). الفارغ = صفر.
export function parseQty(value: string): bigint | null {
  return parseScaled(value, QTY, 3);
}

// "40.125" → 401250n (بعشر الألف). يرجع null لو النص غير صالح (سالب أو أكثر من 4 خانات). الفارغ = صفر.
export function parseUnitPrice(value: string): bigint | null {
  return parseScaled(value, UNIT_PRICE, 4);
}

// 1250500n → "1250.5" (للإرسال إلى قاعدة البيانات)
export function plainQty(units: bigint): string {
  return formatScaled(units, 3, 0).replace(/,/g, "");
}

export function plainUnitPrice(units: bigint): string {
  return formatScaled(units, 4, 0).replace(/,/g, "");
}

// إجمالي السطر بالقروش = الكمية × السعر مقربًا لأقرب قرش (نصف لأعلى) — نفس round(qty * price, 2)
export function lineTotalCents(qtyUnits: bigint, priceUnits: bigint): bigint {
  // الكمية بـ 3 خانات والسعر بـ 4 = 7 خانات، والقروش خانتان: نقسم على 10^5
  return (qtyUnits * priceUnits + 50000n) / 100000n;
}

// كمية من قاعدة البيانات ("1250.500") → "1,250.5"
export function formatQty(value: string | null | undefined): string {
  if (value == null || value === "") return "";
  const text = value.trim();
  const negative = text.startsWith("-");
  const units = parseQty(negative ? text.slice(1) : text);
  if (units === null) return value;
  return formatScaled(negative ? -units : units, 3, 0);
}

// تكلفة وحدة من قاعدة البيانات ("45.0000") → "45.00"، و"5.0583" كما هي
export function formatUnitCost(value: string | null | undefined): string {
  if (value == null || value === "") return "";
  const units = parseUnitPrice(value);
  return units === null ? value : formatScaled(units, 4, 2);
}
