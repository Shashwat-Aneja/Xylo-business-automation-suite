# backend/api/invoice_adapter.py
"""
Adapter: API ↔ Invoice Parsing ↔ Accounting Engine

This module connects:
1. invoice_parser     → extract structured data
2. accounting_engine  → create transaction + journal entry
3. API                → returns clean JSON output

This keeps the API very slim and clean.
"""

import os
import uuid
from typing import Dict, Any
from datetime import datetime

import backend.automation.invoice_parser as parser
import backend.accounting_engine.stubs as acct


# Ensure DB + default accounts
acct._ensure_schema()
acct.seed_default_accounts()


# ------------------------------------------------------------
# Save Uploaded File to Temp Directory
# ------------------------------------------------------------
def save_temp_file(upload_file) -> str:
    """
    Saves UploadFile to a temporary location inside /tmp or backend/tmp/.
    Returns path.
    """
    filename = f"invoice_{uuid.uuid4()}_{upload_file.filename}"
    temp_dir = "backend/tmp"
    os.makedirs(temp_dir, exist_ok=True)
    path = os.path.join(temp_dir, filename)

    with open(path, "wb") as f:
        f.write(upload_file.file.read())

    return path


# ------------------------------------------------------------
# Core Handler
# ------------------------------------------------------------
def process_invoice(upload_file, user_id=None) -> Dict[str, Any]:
    """
    Full pipeline:
    - Save file
    - Parse invoice data
    - Create a transaction in DB
    - Auto-post a journal entry
    """
    # 1. Save file
    file_path = save_temp_file(upload_file)

    # 2. Parse data
    data = parser.parse_invoice(file_path)
    invoice_number = data["invoice_number"]
    amount = float(data["amount"])
    date_iso = data["date"]
    vendor = data["vendor"]

    # 3. Create a transaction
    tx_id = acct.create_transaction(
        user_id=user_id,
        amount=amount,
        description=f"Invoice {invoice_number} from {vendor}",
        source="invoice_upload",
        reference=invoice_number,
    )

    # 4. Auto-post a journal entry
    je_id = acct.create_journal_entry(
        transaction_id=tx_id,
        entry_date=date_iso,
        description=f"Auto-entry for invoice {invoice_number}",
        lines=[
            {"account_code": "1100", "debit": amount, "credit": 0.0},  # Debit Bank
            {"account_code": "4000", "debit": 0.0, "credit": amount},  # Credit Sales/Revenue
        ],
    )

    # 5. Return structured response
    return {
        "invoice": {
            "invoice_number": invoice_number,
            "amount": amount,
            "vendor": vendor,
            "date": date_iso,
            "raw_preview": data["raw_text_preview"],
        },
        "transaction_id": tx_id,
        "journal_entry_id": je_id,
        "file_saved_as": file_path,
    }


# ------------------------------------------------------------
# Demo
# ------------------------------------------------------------
if __name__ == "__main__":
    class FakeUpload:
        filename = "test_invoice.pdf"
        file = open("sample_invoice.pdf", "rb")

    print(process_invoice(FakeUpload()))
