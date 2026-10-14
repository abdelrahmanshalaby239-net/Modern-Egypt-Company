"use client";

import { Button } from "@/components/ui/button";

// طباعة (A4) وتصدير CSV لأي تقرير. صفوف الـ CSV نصوص جاهزة (المبالغ بدون فواصل).
export function ReportTools({
  filename,
  headers,
  rows,
}: {
  filename: string;
  headers: string[];
  rows: string[][];
}) {
  const exportCsv = () => {
    const cell = (v: string) => (/[",\r\n]/.test(v) ? `"${v.replace(/"/g, '""')}"` : v);
    const csv = [headers, ...rows].map((r) => r.map(cell).join(",")).join("\r\n");
    // BOM حتى يعرض Excel النص العربي صحيحًا
    const blob = new Blob(["﻿" + csv], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = filename;
    link.click();
    URL.revokeObjectURL(url);
  };

  return (
    <div className="flex gap-2 print:hidden">
      <Button type="button" variant="outline" onClick={() => window.print()}>
        طباعة
      </Button>
      <Button type="button" variant="outline" onClick={exportCsv} disabled={rows.length === 0}>
        تصدير CSV
      </Button>
    </div>
  );
}
