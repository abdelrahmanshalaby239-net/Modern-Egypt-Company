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

// معامل تحويل الوحدة (حتى 6 خانات): "12" → 12000000n. يرجع null لو غير صالح. الفارغ = صفر.
const FACTOR = /^(\d{1,9})(?:\.(\d{1,6}))?$/;
export function parseFactor(value: string): bigint | null {
  return parseScaled(value, FACTOR, 6);
}

export function plainFactor(units: bigint): string {
  return formatScaled(units, 6, 0).replace(/,/g, "");
}

// معامل من قاعدة البيانات ("12.000000" أو "12") → "12"
export function formatFactor(value: string | null | undefined): string {
  if (value == null || value === "") return "";
  const units = parseFactor(value.trim());
  return units === null ? value : formatScaled(units, 6, 0);
}

// الكمية بالوحدة الأساسية (بالألف) = الكمية × المعامل، ويجب أن تكون دقيقة بثلاث خانات (وإلا null)
export function toBaseUnits(qtyUnits: bigint, factorUnits: bigint): bigint | null {
  const product = qtyUnits * factorUnits; // 3 + 6 = 9 خانات
  if (product % 1000000n !== 0n) return null;
  return product / 1000000n;
}

// كمية بالألف → نص للعرض أو للإرسال
export function formatQtyUnits(units: bigint): string {
  return formatScaled(units, 3, 0);
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

// تكلفة وحدة بعشر الألف → نص للعرض ("10.0000" → "10.00")
export function formatUnitCostUnits(units: bigint): string {
  return formatScaled(units, 4, 2);
}

// حاصل ضرب كميتين بثلاث خانات (مثل الكمية لكل دفعة × عدد الدفعات) مقربًا لثلاث خانات — للاقتراح فقط
export function mulQtyUnits(a: bigint, b: bigint): bigint {
  return (a * b + 500n) / 1000n;
}

// كمية بوحدة بديلة (بالألف) × معاملها (بالمليون) بالوحدة الأساسية مقربة لثلاث خانات — للعرض فقط
export function toBaseUnitsRounded(qtyUnits: bigint, factorUnits: bigint): bigint {
  return (qtyUnits * factorUnits + 500000n) / 1000000n;
}

// تكلفة صرف كمية بالقروش بمتوسط التكلفة الحالي — نفس private.issue_cost: round(الكمية × القيمة ÷ الرصيد, 2)،
// وصرف الرصيد كله = القيمة كلها. null لو الكمية أكبر من الرصيد. معاينة فقط، والمعتمد ما تحسبه قاعدة البيانات.
export function issueCostCents(qtyUnits: bigint, stockUnits: bigint, valueCents: bigint): bigint | null {
  if (qtyUnits > stockUnits) return null;
  if (qtyUnits === stockUnits) return valueCents;
  return (2n * qtyUnits * valueCents + stockUnits) / (2n * stockUnits);
}

// تكلفة الوحدة بعشر الألف = الإجمالي بالقروش ÷ الكمية بالألف — نفس round(الإجمالي ÷ الكمية, 4)
export function unitCostUnits(totalCents: bigint, qtyUnits: bigint): bigint {
  return (2n * totalCents * 100000n + qtyUnits) / (2n * qtyUnits);
}

// كمية بأي عدد من الخانات (مثل الكمية المعيارية = الوصفة × المعامل × الدفعات) → بالألف مقربة لثلاث خانات
export function roundQtyUnits(value: string | null | undefined): bigint | null {
  const match = (value ?? "").trim().match(/^(\d+)(?:\.(\d+))?$/);
  if (!match) return null;
  const fraction = (match[2] ?? "").padEnd(4, "0");
  const units = BigInt(match[1]) * 1000n + BigInt(fraction.slice(0, 3));
  return fraction[3] >= "5" ? units + 1n : units;
}
