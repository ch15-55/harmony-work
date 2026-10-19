"""Review SQL extracted from ark_disasm output, using synthetic SQLite data.

This does not execute the HarmonyOS application or its service methods.
"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import sqlite3


def functions(text):
    return re.findall(r"^\.function .*?^\}", text, re.MULTILINE | re.DOTALL)


def select_function(items, module, method):
    matches = [item for item in items if f".{module}&." in item.splitlines()[0]
               and re.search(r"[.#]" + re.escape(method) + r"\(", item.splitlines()[0])]
    if len(matches) != 1:
        raise ValueError(f"Expected one {module}.{method}, found {len(matches)}")
    return matches[0]


def strings(body):
    return re.findall(r'\tlda\.str "(.*?)"\r*\n', body, re.DOTALL)


def audit(disassembly):
    raw = disassembly.read_bytes()
    items = functions(raw.decode("utf-8", errors="replace"))
    schema = select_function(items, "SchemaConstants", "func_main_0")
    ddl = [value for value in strings(schema) if value.startswith("CREATE ")]
    if len(ddl) != 14:
        raise ValueError(f"Expected 14 original DDL statements, found {len(ddl)}")
    db = sqlite3.connect(":memory:")
    db.row_factory = sqlite3.Row
    results = []

    def check(name, action):
        try:
            action()
            results.append({"name": name, "status": "passed"})
        except (AssertionError, sqlite3.Error) as error:
            results.append({"name": name, "status": "failed", "detail": str(error)})

    def require(condition, message):
        if not condition:
            raise AssertionError(message)

    def apply_schema():
        for statement in ddl:
            db.execute(statement)
        count = db.execute("SELECT COUNT(*) FROM sqlite_master WHERE type='table' "
                           "AND name LIKE 'll_%'").fetchone()[0]
        require(count == 7, f"Expected 7 tables, found {count}")

    check("original_schema_creates_seven_tables", apply_schema)
    check("original_schema_is_idempotent", apply_schema)
    check("seven_declared_indexes_exist", lambda: require(db.execute(
        "SELECT COUNT(*) FROM sqlite_master WHERE type='index' "
        "AND (name LIKE 'idx_%' OR name LIKE 'uk_%')").fetchone()[0] == 7,
        "Declared indexes missing"))

    start, end = 1000, 2000  # Synthetic timestamps; no device clock dependency.
    rows = [
        (1, 1, 0, 1234, 1, 0, 1, 0, start),
        (2, 1, 1, 10000, 1, 0, 2, 0, start + 1),
        (3, 1, 2, 3000, 1, 2, 0, 4, start + 2),
        (4, 1, 2, 3000, 2, 1, 0, 3, start + 2),
        (5, 2, 1, 99999, 3, 0, 3, 0, start + 3),
        (6, 1, 0, 50, 1, 0, 1, 0, start - 1),
        (7, 1, 0, 70, 1, 0, 1, 0, end),
    ]
    db.executemany("INSERT INTO ll_transaction "
                   "(id,ledger_id,type,amount,account_id,to_account_id,category_id,"
                   "related_tx_id,tx_date,created_at,updated_at) "
                   "VALUES (?,?,?,?,?,?,?,?,?,0,0)", rows)

    def summary_query(method):
        values = strings(select_function(items, "StatsService", method))
        first = next(i for i, value in enumerate(values) if value.startswith("SELECT "))
        return values[first] + "ll_transaction" + values[first + 1]

    monthly = summary_query("getMonthSummary")
    grand = summary_query("getGrandTotal")

    def totals(query, params):
        return {row["type"]: row["total"] for row in db.execute(query, params)}

    check("monthly_query_excludes_transfers_other_ledgers_and_end_boundary",
          lambda: require(totals(monthly, (1, 0, 1, start, end)) == {0: 1234, 1: 10000},
                          "Monthly totals differ"))
    check("monthly_query_includes_start_boundary", lambda: require(
        totals(monthly, (1, 0, 1, start, start + 1)) == {0: 1234}, "Start excluded"))
    check("monthly_query_empty_range", lambda: require(
        totals(monthly, (1, 0, 1, end + 1, end + 2)) == {}, "Expected empty totals"))
    check("monthly_query_isolates_second_ledger", lambda: require(
        totals(monthly, (2, 0, 1, start, end)) == {1: 99999}, "Ledger isolation failed"))
    check("all_time_query_excludes_transfers", lambda: require(
        totals(grand, (1, 0, 1)) == {0: 1354, 1: 10000}, "All-time totals differ"))

    values = strings(select_function(items, "AccountService", "getBalance"))
    balance_sql = "".join(value + ("ll_transaction" if value.endswith("FROM ") else "")
                          for value in values[:9])

    def balance(account, initial):
        row = db.execute(balance_sql, (account, 1, account, 0, 2, account, 2, account)).fetchone()
        return initial + row["income"] - row["expense"] + row["transfer_in"] - row["transfer_out"]

    check("source_account_query_counts_transfer_once", lambda: require(
        balance(1, 100000) == 105646, "Source balance differs"))
    check("destination_account_query_counts_transfer_once", lambda: require(
        balance(2, 50000) == 53000, "Destination balance differs"))
    check("balance_query_conserves_combined_transfer_value", lambda: require(
        balance(1, 100000) + balance(2, 50000) == 158646, "Combined balance differs"))

    def unique_budget():
        db.execute("INSERT INTO ll_budget (ledger_id,month,created_at,updated_at) "
                   "VALUES (1,'2026-10',0,0)")
        try:
            db.execute("INSERT INTO ll_budget (ledger_id,month,created_at,updated_at) "
                       "VALUES (1,'2026-10',0,0)")
        except sqlite3.IntegrityError:
            return
        raise AssertionError("Duplicate budget accepted")

    check("budget_unique_index_rejects_duplicate_month_in_same_ledger", unique_budget)
    check("budget_unique_index_allows_same_month_in_other_ledger", lambda: db.execute(
        "INSERT INTO ll_budget (ledger_id,month,created_at,updated_at) VALUES (2,'2026-10',0,0)"))

    evidence = {}
    for module, method in (
        ("MoneyUtil", "parseYuanToIntFen"), ("MoneyUtil", "isRecordableAmount"),
        ("CryptoUtil", "hashPin"), ("CryptoUtil", "sha256Hex"),
        ("AppLockService", "verifyPin"), ("DatabaseManager", "runInTransaction"),
        ("BackupService", "restoreFromJson"), ("BackupService", "validateBackupJson"),
        ("BackupService", "validateRelations"), ("ExportService", "guardCsvText"),
        ("ExportService", "joinRow"), ("PlaceholderPage", "initialRender"),
        ("BudgetProgressCard", "usedPercent"),
    ):
        body = select_function(items, module, method)
        evidence[f"{module}.{method}"] = {
            "function": body.splitlines()[0],
            "strings": strings(body),
            "member_names": re.findall(r'ldobjbyname[^\r\n"]*"([^"\r\n]+)"', body),
        }
        if (module, method) in (("CryptoUtil", "hashPin"),
                                ("BudgetProgressCard", "usedPercent")):
            evidence[f"{module}.{method}"]["instructions"] = body.splitlines()[1:-1]
    db.close()
    return {
        "scope": "original SQL on synthetic desktop SQLite data; not application execution",
        "disassembly_sha256": hashlib.sha256(raw).hexdigest(),
        "sqlite_version": sqlite3.sqlite_version,
        "passed": sum(result["status"] == "passed" for result in results),
        "failed": sum(result["status"] == "failed" for result in results),
        "tests": results,
        "schema_sql": ddl,
        "monthly_summary_sql": monthly,
        "grand_summary_sql": grand,
        "account_balance_sql": balance_sql,
        "static_evidence": evidence,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--disassembly", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = audit(args.disassembly)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"SQL review: {result['passed']} passed, {result['failed']} failed")
    raise SystemExit(bool(result["failed"]))


if __name__ == "__main__":
    main()
