import type { Metadata } from "next";

import { PartiesPage } from "../_parties/parties-page";

export const metadata: Metadata = { title: "الموردين" };

export default async function SuppliersPage({ searchParams }: PageProps<"/suppliers">) {
  const q = String((await searchParams).q ?? "").trim();
  return <PartiesPage kind="supplier" q={q} />;
}
