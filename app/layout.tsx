import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "نظام المحاسبة والتصنيع",
  description: "نظام محاسبة وتصنيع بسيط لمصنع منظفات",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="ar" dir="rtl">
      <body className="min-h-dvh">{children}</body>
    </html>
  );
}
