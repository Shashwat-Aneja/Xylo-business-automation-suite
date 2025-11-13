# backend/utils/report_generator.py
"""
XYLO — Report Generator Utility

This module generates:
- Daily summary reports
- Profit & Loss reports
- Balance sheet snapshots
- Transaction digests
- CSV/JSON exports

It integrates with:
- accounting_engine (data source)
- email_service (optional attachments)
- automation scheduler (daily/weekly tasks)

Supports exporting:
- JSON (dict)
- CSV (comma-separated)
- Plain text (for emails / logs)
"""

import csv
import json
from datetime import datetime
from typing import Dict, Any, List, Optional

import backend.accounting_engine.stubs as acct


# ------------------------------------------------------------
# Helper: timestamp
# ------------------------------------------------------------
def ts() -> str:
    return datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")


# ------------------------------------------------------------
# 1. Daily Summary Report
# ------------------------------------------------------------
def generate_daily_summary() -> Dict[str, Any]:
    """
    Generates a summary of all financial activity for the current day.
    """
    today = datetime.utcnow().date().isoformat()

    pnl = acct.compute_profit_and_loss(today, today)
    tb = acct.compute_trial_balance(today, today)

    return {
        "type": "daily_summary",
        "generated_at": ts(),
        "date": today,
        "profit_loss": pnl,
        "trial_balance": tb,
    }


# ------------------------------------------------------------
# 2. Monthly Summary Report
# ------------------------------------------------------------
def generate_monthly_summary(year: int, month: int) -> Dict[str, Any]:
    start = f"{year}-{month:02d}-01"
    # End-of-month handling
    if month == 12:
        end = f"{year}-12-31"
    else:
        end = f"{year}-{month+1:02d}-01"

    pnl = acct.compute_profit_and_loss(start, end)
    tb = acct.compute_trial_balance(start, end)

    return {
        "type": "monthly_summary",
        "generated_at": ts(),
        "range": {"from": start, "to": end},
        "profit_loss": pnl,
        "trial_balance": tb,
    }


# ------------------------------------------------------------
# 3. Balance Sheet Snapshot
# ------------------------------------------------------------
def generate_balance_snapshot(date: Optional[str] = None) -> Dict[str, Any]:
    bs = acct.compute_balance_sheet(date)
    return {
        "type": "balance_sheet_snapshot",
        "generated_at": ts(),
        "as_of": date or datetime.utcnow().date().isoformat(),
        "balance_sheet": bs,
    }


# ------------------------------------------------------------
# 4. CSV Export
# ------------------------------------------------------------
def export_trial_balance_to_csv(path: str, tb: List[Dict[str, Any]]) -> str:
    """
    Saves trial balance to a CSV file.
    Returns path.
    """
    fieldnames = ["account_code", "account_name", "type", "total_debit", "total_credit"]
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(tb)
    return path


def export_pnl_to_csv(path: str, pnl: Dict[str, float]) -> str:
    """
    Saves P&L summary to CSV.
    """
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["Category", "Amount"])
        writer.writerow(["Income", pnl["income"]])
        writer.writerow(["Expenses", pnl["expense"]])
        writer.writerow(["Net Profit", pnl["profit"]])
    return path


# ------------------------------------------------------------
# 5. JSON Export
# ------------------------------------------------------------
def save_json(path: str, data: Dict[str, Any]) -> str:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=4)
    return path


# ------------------------------------------------------------
# 6. Text Report (for email bodies)
# ------------------------------------------------------------
def format_daily_summary_text(summary: Dict[str, Any]) -> str:
    pnl = summary["profit_loss"]
    tb = summary["trial_balance"]

    lines = [
        f"XYLO Daily Summary — {summary['date']}",
        f"Generated at: {summary['generated_at']}",
        "",
        "Profit & Loss:",
        f"  Income:       ₹{pnl['income']:.2f}",
        f"  Expenses:     ₹{pnl['expense']:.2f}",
        f"  Net Profit:   ₹{pnl['profit']:.2f}",
        "",
        f"Trial Balance Accounts: {len(tb)}",
    ]
    return "\n".join(lines)


# ------------------------------------------------------------
# 7. High-Level Report API
# ------------------------------------------------------------
def generate_and_save_daily_report(output_dir: str = "samples/generated_reports") -> Dict[str, str]:
    """
    Creates and saves:
    - daily_summary.json
    - trial_balance.csv
    - pnl.csv

    Returns file paths.
    """
    import os
    os.makedirs(output_dir, exist_ok=True)

    summary = generate_daily_summary()
    pnl = summary["profit_loss"]
    tb = summary["trial_balance"]

    json_path = f"{output_dir}/daily_summary.json"
    tb_csv = f"{output_dir}/trial_balance.csv"
    pnl_csv = f"{output_dir}/pnl.csv"

    save_json(json_path, summary)
    export_trial_balance_to_csv(tb_csv, tb)
    export_pnl_to_csv(pnl_csv, pnl)

    return {
        "json": json_path,
        "trial_balance_csv": tb_csv,
        "pnl_csv": pnl_csv,
    }


# Demo
if __name__ == "__main__":
    result = generate_and_save_daily_report()
    print("Generated report files:", result)
