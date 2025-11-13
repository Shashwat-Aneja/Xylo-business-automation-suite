# backend/accounting_engine/stubs.py
"""
XYLO — Accounting Engine Starter (SQLite-backed, dev-friendly)

This module provides a minimal, clear, and practical accounting backend
for development and demo purposes. It is intentionally small and readable:
- Uses sqlite3 (no external dependencies)
- Creates required tables if missing
- Implements basic double-entry journal posting
- Exposes functions to compute trial balance, P&L, and balance sheet

Replace with full accounting_engine implementation (ORM, rules engine, validations)
for production use.
"""

import sqlite3
from datetime import datetime
from decimal import Decimal, ROUND_HALF_UP
from typing import List, Dict, Any, Optional
import uuid
import os

DB_PATH = os.environ.get("XYLO_DB", "xylo_dev.db")


def _get_conn():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def _ensure_schema():
    conn = _get_conn()
    cur = conn.cursor()

    # users (simple reference)
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS users (
            id TEXT PRIMARY KEY,
            email TEXT UNIQUE,
            name TEXT,
            created_at TEXT
        )
        """
    )

    # transactions (source records)
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS transactions (
            id TEXT PRIMARY KEY,
            user_id TEXT,
            source TEXT,
            reference TEXT,
            date TEXT,
            amount REAL,
            currency TEXT,
            description TEXT,
            metadata TEXT,
            created_at TEXT,
            processed INTEGER DEFAULT 0
        )
        """
    )

    # journal_entries (header)
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS journal_entries (
            id TEXT PRIMARY KEY,
            transaction_id TEXT,
            entry_date TEXT,
            description TEXT,
            created_at TEXT
        )
        """
    )

    # journal_lines (debit/credit lines)
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS journal_lines (
            id TEXT PRIMARY KEY,
            journal_entry_id TEXT,
            account_code TEXT,
            debit REAL DEFAULT 0,
            credit REAL DEFAULT 0
        )
        """
    )

    # accounts (chart of accounts - minimal)
    cur.execute(
        """
        CREATE TABLE IF NOT EXISTS accounts (
            code TEXT PRIMARY KEY,
            name TEXT,
            type TEXT, -- asset, liability, equity, income, expense
            normal_balance TEXT
        )
        """
    )

    conn.commit()
    conn.close()


# --- Utilities ---


def _decimal(x) -> Decimal:
    return Decimal(str(x)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


# --- Public API ---


def seed_default_accounts():
    """
    Seed a minimal Chart of Accounts for demonstration.
    Only runs if account codes do not exist.
    """
    _ensure_schema()
    conn = _get_conn()
    cur = conn.cursor()

    default_accounts = [
        ("1000", "Cash", "asset", "debit"),
        ("1100", "Bank", "asset", "debit"),
        ("2000", "Accounts Payable", "liability", "credit"),
        ("3000", "Equity / Capital", "equity", "credit"),
        ("4000", "Sales / Revenue", "income", "credit"),
        ("5000", "Cost of Goods Sold", "expense", "debit"),
        ("5100", "Rent Expense", "expense", "debit"),
        ("5200", "Utilities Expense", "expense", "debit"),
    ]

    for code, name, typ, nb in default_accounts:
        cur.execute("SELECT 1 FROM accounts WHERE code = ?", (code,))
        if cur.fetchone() is None:
            cur.execute(
                "INSERT INTO accounts(code, name, type, normal_balance) VALUES (?, ?, ?, ?)",
                (code, name, typ, nb),
            )

    conn.commit()
    conn.close()


def create_transaction(user_id: Optional[str], amount: float, description: str, source: str = "manual", reference: Optional[str] = None) -> str:
    """
    Create a raw transaction record (source). Returns transaction_id.
    """
    _ensure_schema()
    tx_id = str(uuid.uuid4())
    created_at = datetime.utcnow().isoformat()
    conn = _get_conn()
    cur = conn.cursor()
    cur.execute(
        """INSERT INTO transactions(id, user_id, source, reference, date, amount, currency, description, created_at, processed)
           VALUES (?,?,?,?,?,?,?,?,?,0)""",
        (tx_id, user_id, source, reference, datetime.utcnow().date().isoformat(), float(amount), "INR", description, created_at),
    )
    conn.commit()
    conn.close()
    return tx_id


def create_journal_entry(transaction_id: Optional[str], entry_date: str, description: str, lines: List[Dict[str, Any]]) -> str:
    """
    Create a journal entry with lines.
    'lines' should be a list of dicts: {"account_code": "1000", "debit": 100.0, "credit": 0.0}
    Returns journal_entry_id.
    """
    _ensure_schema()
    # validate that debits == credits
    total_debit = sum([_decimal(l.get("debit", 0)) for l in lines])
    total_credit = sum([_decimal(l.get("credit", 0)) for l in lines])
    if total_debit != total_credit:
        raise ValueError(f"Debits ({total_debit}) do not equal Credits ({total_credit}). Journal entry rejected.")

    je_id = str(uuid.uuid4())
    created_at = datetime.utcnow().isoformat()
    conn = _get_conn()
    cur = conn.cursor()

    cur.execute(
        "INSERT INTO journal_entries(id, transaction_id, entry_date, description, created_at) VALUES (?,?,?,?,?)",
        (je_id, transaction_id, entry_date, description, created_at),
    )

    for line in lines:
        jl_id = str(uuid.uuid4())
        account_code = line["account_code"]
        debit = float(line.get("debit", 0))
        credit = float(line.get("credit", 0))
        cur.execute(
            "INSERT INTO journal_lines(id, journal_entry_id, account_code, debit, credit) VALUES (?,?,?,?,?)",
            (jl_id, je_id, account_code, debit, credit),
        )

    # mark transaction processed if supplied
    if transaction_id:
        cur.execute("UPDATE transactions SET processed = 1 WHERE id = ?", (transaction_id,))

    conn.commit()
    conn.close()
    return je_id


def compute_trial_balance(from_date: Optional[str] = None, to_date: Optional[str] = None) -> List[Dict[str, Any]]:
    """
    Returns a list of accounts with total debits and credits within optional date range.
    """
    _ensure_schema()
    conn = _get_conn()
    cur = conn.cursor()

    q = """
    SELECT jl.account_code,
           COALESCE(SUM(jl.debit),0) AS total_debit,
           COALESCE(SUM(jl.credit),0) AS total_credit,
           a.name, a.type
    FROM journal_lines jl
    LEFT JOIN journal_entries je ON je.id = jl.journal_entry_id
    LEFT JOIN accounts a ON a.code = jl.account_code
    """

    params = []
    if from_date or to_date:
        q += " WHERE 1=1 "
        if from_date:
            q += " AND je.entry_date >= ? "
            params.append(from_date)
        if to_date:
            q += " AND je.entry_date <= ? "
            params.append(to_date)

    q += " GROUP BY jl.account_code ORDER BY jl.account_code "

    cur.execute(q, params)
    rows = cur.fetchall()
    result = []
    for r in rows:
        result.append(
            {
                "account_code": r["account_code"],
                "account_name": r["name"],
                "type": r["type"],
                "total_debit": float(r["total_debit"]),
                "total_credit": float(r["total_credit"]),
            }
        )
    conn.close()
    return result


def compute_profit_and_loss(from_date: Optional[str] = None, to_date: Optional[str] = None) -> Dict[str, float]:
    """
    Simple P&L: sums income and expense accounts to produce profit.
    """
    tb = compute_trial_balance(from_date, to_date)
    income = 0.0
    expense = 0.0
    for row in tb:
        typ = row.get("type", "")
        debit = row.get("total_debit", 0.0)
        credit = row.get("total_credit", 0.0)
        if typ == "income":
            income += credit - debit
        elif typ == "expense":
            expense += debit - credit

    profit = income - expense
    return {"income": round(income, 2), "expense": round(expense, 2), "profit": round(profit, 2)}


def compute_balance_sheet(as_of: Optional[str] = None) -> Dict[str, Any]:
    """
    Returns top-level totals for Assets, Liabilities, Equity and a simple reconciliation.
    """
    tb = compute_trial_balance(None, as_of)
    assets = 0.0
    liabilities = 0.0
    equity = 0.0

    conn = _get_conn()
    cur = conn.cursor()

    for row in tb:
        typ = row.get("type", "")
        debit = row.get("total_debit", 0.0)
        credit = row.get("total_credit", 0.0)
        if typ == "asset":
            assets += debit - credit
        elif typ == "liability":
            liabilities += credit - debit
        elif typ == "equity":
            equity += credit - debit

    # add profit to equity
    pnl = compute_profit_and_loss(None, as_of)
    equity += pnl["profit"]

    conn.close()
    return {"assets": round(assets, 2), "liabilities": round(liabilities, 2), "equity": round(equity, 2), "reconciles": round(assets - (liabilities + equity), 2)}


# Simple demo runner
if __name__ == "__main__":
    # initialize schema + seed accounts
    _ensure_schema()
    seed_default_accounts()

    # demo: create a transaction and post journal entries (Sales ₹1000)
    tx_id = create_transaction(user_id=None, amount=1000.0, description="Demo sale", source="manual")
    # Journal: Debit Bank, Credit Sales
    je_id = create_journal_entry(
        transaction_id=tx_id,
        entry_date=datetime.utcnow().date().isoformat(),
        description="Sale received (demo)",
        lines=[
            {"account_code": "1100", "debit": 1000.0, "credit": 0.0},  # Bank
            {"account_code": "4000", "debit": 0.0, "credit": 1000.0},  # Sales
        ],
    )
    print("Journal Entry posted:", je_id)
    print("Trial Balance:")
    for r in compute_trial_balance():
        print(r)
    print("P&L:", compute_profit_and_loss())
    print("Balance Sheet:", compute_balance_sheet())
