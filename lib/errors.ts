// يحوّل أخطاء Postgres/Supabase إلى رسائل عربية واضحة.
export function arabicError(error: { code?: string; message: string }): string {
  switch (error.code) {
    case "P0001": // رسائل الـ triggers والدوال عربية أصلًا
      return error.message;
    case "23505":
      return "القيمة مكررة: يوجد سجل بنفس البيانات (مثل كود مكرر).";
    case "23503":
      return "لا يمكن تنفيذ العملية لوجود بيانات مرتبطة بهذا السجل.";
    case "23502":
    case "23514":
      return "بعض القيم غير صالحة أو ناقصة.";
    case "22003":
      return "المبلغ أكبر من الحد المسموح.";
    case "22P02":
      return "قيمة غير صالحة.";
    case "42501":
      return "ليست لديك صلاحية لتنفيذ هذه العملية.";
    default:
      return "حدث خطأ غير متوقع، حاول مرة أخرى.";
  }
}

export const NOT_ALLOWED = "ليست لديك صلاحية لتنفيذ هذه العملية.";

export type FormState = { error?: string; success?: string };
