import os
import sqlite3
import tempfile
from datetime import datetime
from pathlib import Path

import pytest

os.environ.setdefault(
    "XYLO_DB",
    str(Path(tempfile.gettempdir()) / "xylo-csv-import-tests.sqlite3"),
)

from backend.api import adapter_accounting as adapter


@pytest.fixture
def isolated_database(tmp_path, monkeypatch):
    db_path = tmp_path / "csv-import.sqlite3"
    monkeypatch.setattr(adapter.acct, "DB_PATH", str(db_path))
    adapter.acct._ensure_schema()
    adapter.acct.seed_default_accounts()
    return db_path


def test_csv_import_preserves_transaction_dates_and_reports_invalid_rows(isolated_database):
    payload = (
        b"\xef\xbb\xbfdate,description,amount,source,reference\n"
        b"2026-10-03,October sale,25.50,bank,INV-1\n"
        b",Missing date,10,bank,INV-2\n"
        b"2026-10-04,Non-finite amount,NaN,bank,INV-3\n"
    )

    result = adapter.import_transactions_from_csv_bytes(payload, user_id="user-1")

    assert result["count"] == 1
    assert len(result["created_transactions"]) == 1
    assert result["skipped_rows"] == [
        {"row": 3, "error": "date is required."},
        {"row": 4, "error": "amount must be a finite number."},
    ]

    with sqlite3.connect(isolated_database) as connection:
        row = connection.execute(
            "SELECT date, amount, description, source, reference FROM transactions WHERE id = ?",
            (result["created_transactions"][0],),
        ).fetchone()

    assert row == ("2026-10-03", 25.5, "October sale", "bank", "INV-1")


def test_csv_import_rejects_missing_required_headers(isolated_database):
    with pytest.raises(ValueError, match="missing required headers: amount"):
        adapter.import_transactions_from_csv_bytes(b"date,description\n2026-10-03,Sale\n")


def test_csv_import_rejects_duplicate_headers(isolated_database):
    with pytest.raises(ValueError, match="headers must be non-empty and unique"):
        adapter.import_transactions_from_csv_bytes(
            b"date,amount,amount\n2026-10-03,10,20\n"
        )



def test_manual_transaction_and_journal_share_the_requested_date(isolated_database):
    result = adapter.create_transaction_and_post(
        user_id="user-1",
        date=datetime(2026, 10, 5),
        amount=50.00,
        description="Dated sale",
    )

    with sqlite3.connect(isolated_database) as connection:
        transaction_date = connection.execute(
            "SELECT date FROM transactions WHERE id = ?",
            (result["transaction_id"],),
        ).fetchone()[0]
        journal_date = connection.execute(
            "SELECT entry_date FROM journal_entries WHERE id = ?",
            (result["journal_entry_id"],),
        ).fetchone()[0]

    assert transaction_date == "2026-10-05"
    assert journal_date == "2026-10-05"
