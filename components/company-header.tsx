// رأس المستندات المطبوعة (الفواتير والسندات وأوامر الإنتاج): اسم الشركة وعنوانها وهاتفها من الإعدادات
export function CompanyHeader({
  settings,
}: {
  settings: { company_name: string; company_address: string | null; company_phone: string | null } | null;
}) {
  return (
    <div className="border-b pb-4 text-center">
      <div className="text-lg font-bold">{settings?.company_name}</div>
      {(settings?.company_address || settings?.company_phone) && (
        <div className="text-sm text-muted-foreground">
          {[settings?.company_address, settings?.company_phone].filter(Boolean).join(" · ")}
        </div>
      )}
    </div>
  );
}
