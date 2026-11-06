# backend/api/adapter_accounting.py
"""
Adapter layer: API ↔ Accounting Engine

This module provides small wrapper functions that the FastAPI endpoints can import and call.
It isolates the accounting implementation (stubs or full engine) so the API stays clean.
"""

from typing import Dict, Any, List, Optional
from datetime import datetime
import math
import backend.accounting_engine.stubs as acct
import csv
import io

# Initialize / ensure schema and seed demo accounts
acct._ensure_schema()
acct.seed_default_accounts()


def create_transaction_and_post(
    user_id: Optional[str],
    date: datetime,
    amount: float,
    description: Optional[str] = None,
    source: str = "manual",
    reference: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Convenience function: creates a transaction record, then creates a basic journal entry.
    For demo purposes: posts a simple debit to Bank (1100) and credit to Sales (4000) when amount > 0.
    Replace this logic with the production rules engine later.
    """
    tx_id = acct.create_transaction(user_id=user_id, amount=amount, description=description or "", source=source, reference=reference)

    # Build a simple journal entry: Debit Bank (1100) / Credit Sales (4000)
    entry_date = date.date().isoformat()
    lines = [
        {"account_code": "1100", "debit": float(amount), "credit": 0.0},
        {"account_code": "4000", "debit": 0.0, "credit": float(amount)},
    ]

    je_id = acct.create_journal_entry(transaction_id=tx_id, entry_date=entry_date, description=description or "Auto-posted", lines=lines)

    return {"transaction_id": tx_id, "journal_entry_id": je_id}


def get_trial_balance(from_date: Optional[str] = None, to_date: Optional[str] = None) -> Dict[str, Any]:
    """
    Returns a packaged trial balance with totals.
    """
    tb = acct.compute_trial_balance(from_date, to_date)
    total_debit = sum(row["total_debit"] for row in tb)
    total_credit = sum(row["total_credit"] for row in tb)
    return {"trial_balance": tb, "total_debit": round(total_debit, 2), "total_credit": round(total_credit, 2)}


def get_profit_and_loss(from_date: Optional[str] = None, to_date: Optional[str] = None) -> Dict[str, Any]:
    """
    Returns profit/loss summary.
    """
    pnl = acct.compute_profit_and_loss(from_date, to_date)
    return pnl


def get_balance_sheet(as_of: Optional[str] = None) -> Dict[str, Any]:
    """
    Returns balance sheet top-level totals.
    """
    bs = acct.compute_balance_sheet(as_of)
    return bs


def import_transactions_from_csv_bytes(csv_bytes: bytes, user_id: Optional[str] = None) -> Dict[str, Any]:
    """
    Import dated transactions from UTF-8 CSV bytes.

    Required headers: date, amount
    Optional headers: description, currency, source, reference

    Invalid rows are reported with their CSV line number and do not stop later
    valid rows from being imported. Database errors still propagate to callers.
    """
    try:
        text = csv_bytes.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise ValueError("CSV content must be UTF-8 encoded.") from exc

    reader = csv.DictReader(io.StringIO(text, newline=""))
    if not reader.fieldnames:
        raise ValueError("CSV must include a header row.")

    headers = [header.strip().lower() if isinstance(header, str) else "" for header in reader.fieldnames]
    if any(not header for header in headers) or len(set(headers)) != len(headers):
        raise ValueError("CSV headers must be non-empty and unique.")
    reader.fieldnames = headers

    missing_headers = {"date", "amount"}.difference(headers)
    if missing_headers:
        raise ValueError(f"CSV is missing required headers: {', '.join(sorted(missing_headers))}.")

    created = []
    skipped_rows = []
    for line_number, row in enumerate(reader, start=2):
        try:
            if None in row:
                raise ValueError("row contains more values than the header.")
            date_text = (row.get("date") or "").strip()
            if not date_text:
                raise ValueError("date is required.")
            transaction_date = datetime.fromisoformat(date_text.replace("Z", "+00:00"))

            amount_text = (row.get("amount") or "").strip()
            if not amount_text:
                raise ValueError("amount is required.")
            amount = float(amount_text)
            if not math.isfinite(amount):
                raise ValueError("amount must be a finite number.")

            description = (row.get("description") or "").strip()
            source = (row.get("source") or "").strip() or "csv_import"
            reference = (row.get("reference") or "").strip() or None
        except (ValueError, TypeError, OverflowError) as exc:
            skipped_rows.append({"row": line_number, "error": str(exc)})
            continue

        tx_id = acct.create_transaction(
            user_id=user_id,
            amount=amount,
            description=description,
            source=source,
            reference=reference,
            transaction_date=transaction_date,
        )
        created.append(tx_id)

    return {
        "created_transactions": created,
        "count": len(created),
        "skipped_rows": skipped_rows,
    }

# Expose a small convenience to be used by API main
__all__ = [
    "create_transaction_and_post",
    "get_trial_balance",
    "get_profit_and_loss",
    "get_balance_sheet",
    "import_transactions_from_csv_bytes",
]
