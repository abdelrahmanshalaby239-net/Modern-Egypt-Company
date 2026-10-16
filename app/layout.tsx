import type { Metadata, Viewport } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "نظام المحاسبة والتصنيع",
  description: "نظام محاسبة وتصنيع بسيط لمصنع منظفات",
};

// viewport-fit=cover لاستخدام مساحة الشاشة كاملة على iOS مع هوامش safe-area في التخطيط
export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
  themeColor: "#ffffff",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="ar" dir="rtl">
      <body className="min-h-dvh">{children}</body>
    </html>
  );
}
