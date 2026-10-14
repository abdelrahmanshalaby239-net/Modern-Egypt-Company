// التواريخ يوم/شهر/سنة والأرقام 0-9 (SPEC §2)

// "2026-10-14" → "14/10/2026"
export function formatDate(iso: string | null | undefined): string {
  if (!iso) return "";
  const [y, m, d] = iso.slice(0, 10).split("-");
  return `${d}/${m}/${y}`;
}

// "14/10/2026" → "2026-10-14"، أو null لو التاريخ غير صحيح
export function parseDate(input: string): string | null {
  const match = input.trim().match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
  if (!match) return null;
  const [, d, m, y] = match.map(Number);
  const date = new Date(Date.UTC(y, m - 1, d));
  if (date.getUTCFullYear() !== y || date.getUTCMonth() !== m - 1 || date.getUTCDate() !== d) {
    return null;
  }
  return `${y}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
}

// تاريخ اليوم بتوقيت القاهرة بصيغة ISO
export function todayIso(): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Africa/Cairo" }).format(new Date());
}

// أول يوم في السنة الحالية بصيغة ISO
export function yearStartIso(): string {
  return `${todayIso().slice(0, 4)}-01-01`;
}
