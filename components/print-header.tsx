// رأس يظهر في الطباعة فقط: اسم الشركة وعنوان التقرير والفترة
export function PrintHeader({
  company,
  title,
  subtitle,
}: {
  company: string;
  title: string;
  subtitle?: string;
}) {
  return (
    <div className="mb-4 hidden border-b pb-3 text-center print:block">
      <div className="text-lg font-bold">{company}</div>
      <div className="font-semibold">{title}</div>
      {subtitle && <div className="text-sm text-muted-foreground">{subtitle}</div>}
    </div>
  );
}
