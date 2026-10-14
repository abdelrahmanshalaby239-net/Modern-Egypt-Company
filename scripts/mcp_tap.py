"""Turn a pgTAP test file into one SQL batch whose last result set lists every assertion.

The Supabase MCP execute_sql call returns only the last result set, so each
top-level assertion `select is(...);` becomes `insert into pg_temp._tap ...`.
The file on disk stays plain pgTAP (pg_prove / `supabase test db`).
"""
import re
import sys

ASSERT = re.compile(r"^select (is|isnt|ok|results_eq|throws_ok|throws_like|lives_ok|is_empty|bag_eq)\(", re.M)
src = open(sys.argv[1], encoding="utf-8").read()
src = re.sub(r"^--.*\n", "", src, flags=re.M)          # drop comment lines
src = re.sub(r"\n{2,}", "\n", src)
src = ASSERT.sub(lambda m: "insert into pg_temp._tap (line) select " + m.group(1) + "(", src)
setup = (
    "create temp table _tap (n serial, line text);\n"
    "grant all on pg_temp._tap to public; grant all on sequence pg_temp._tap_n_seq to public;\n"
)
src = src.replace("select plan(", setup + "select plan(", 1)
src = src.replace(
    "select * from finish();",
    "select count(*) filter (where line like 'ok%') as passed,"
    " count(*) filter (where line like 'not ok%') as failed,"
    " string_agg(line, E'\\n' order by n) as tap from pg_temp._tap;",
)
sys.stdout.write(src)
