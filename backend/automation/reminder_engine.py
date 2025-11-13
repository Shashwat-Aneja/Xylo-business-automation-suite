# backend/automation/reminder_engine.py
"""
XYLO — Reminder Engine

Handles:
- Overdue payment reminders
- Recurring alerts
- Email notifications
- Integration with scheduler + accounting engine

This engine is designed to work with:
- email_service.py
- accounting_engine.stubs (for reading unpaid invoices)
- scheduler.py for daily automation
"""

from datetime import datetime, timedelta
from typing import List, Dict, Any

import backend.accounting_engine.stubs as acct
import backend.automation.email_service as emailer


# ---------------------------------------------------------------------
# Placeholder: In full system, invoices would have a 'due_date' and 'paid' flag.
# For now, we infer overdue invoices from transactions with negative balances
# or invoice references marked unpaid.
# ---------------------------------------------------------------------

def _mock_find_overdue_invoices() -> List[Dict[str, Any]]:
    """
    Mock overdue invoice detection.
    In a full system, this will check invoice database table:
        - invoice.due_date < today
        - invoice.paid == false
    """
    # Use transactions as mock invoice records
    conn = acct._get_conn()
    cur = conn.cursor()
    rows = cur.execute("SELECT * FROM transactions WHERE amount > 0").fetchall()

    overdue = []
    today = datetime.utcnow().date()

    for r in rows:
        # Mock rule: everything older than 10 days is overdue
        tx_date = datetime.fromisoformat(r["date"]).date()
        if (today - tx_date).days > 10:
            overdue.append(
                {
                    "invoice_number": r["reference"],
                    "amount": r["amount"],
                    "description": r["description"],
                    "date": r["date"],
                    "days_overdue": (today - tx_date).days,
                }
            )

    conn.close()
    return overdue


# ---------------------------------------------------------------------
# Send Reminder Email
# ---------------------------------------------------------------------
def send_payment_reminder(invoice: Dict[str, Any], to_email: str) -> bool:
    subject = f"Payment Reminder — Invoice {invoice['invoice_number']}"
    body = (
        f"Dear Customer,\n\n"
        f"This is a reminder that your payment for invoice **{invoice['invoice_number']}** "
        f"is overdue by **{invoice['days_overdue']} days**.\n\n"
        f"Amount Due: ₹{invoice['amount']:.2f}\n"
        f"Description: {invoice['description']}\n"
        f"Invoice Date: {invoice['date']}\n\n"
        f"Please clear the payment at your earliest convenience.\n"
        f"\nRegards,\nXYLO Automated Reminder System"
    )

    return emailer.send_email(
        to=to_email,
        subject=subject,
        body=body,
        html=False,
    )


# ---------------------------------------------------------------------
# Main Overdue Reminder Runner
# ---------------------------------------------------------------------
def run_overdue_reminder_cycle(to_email: str = "client@example.com") -> Dict[str, Any]:
    overdue = _mock_find_overdue_invoices()

    results = []
    for invoice in overdue:
        success = send_payment_reminder(invoice, to_email)
        results.append({"invoice": invoice["invoice_number"], "sent": success})

    return {
        "timestamp": datetime.utcnow().isoformat(),
        "total_overdue": len(overdue),
        "results": results,
    }


# ---------------------------------------------------------------------
# Demo
# ---------------------------------------------------------------------
if __name__ == "__main__":
    print("Finding overdue invoices...")
    cycle = run_overdue_reminder_cycle("demo@example.com")
    print(cycle)
