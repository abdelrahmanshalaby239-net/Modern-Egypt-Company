import type { Metadata } from "next";

import { PartiesPage } from "../_parties/parties-page";

export const metadata: Metadata = { title: "العملاء" };

export default async function CustomersPage({ searchParams }: PageProps<"/customers">) {
  const q = String((await searchParams).q ?? "").trim();
  return <PartiesPage kind="customer" q={q} />;
}
