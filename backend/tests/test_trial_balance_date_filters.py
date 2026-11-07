import sqlite3

import backend.accounting_engine.stubs as accounting


def _post_entry(date, amount, description):
    return accounting.create_journal_entry(
        transaction_id=None,
        entry_date=date,
        description=description,
        lines=[
            {"account_code": "1100", "debit": amount, "credit": 0},
            {"account_code": "4000", "debit": 0, "credit": amount},
        ],
    )


def test_trial_balance_date_range_includes_both_boundary_dates(tmp_path, monkeypatch):
    database = tmp_path / "date-range.sqlite3"
    monkeypatch.setattr(accounting, "DB_PATH", str(database))
    accounting.seed_default_accounts()

    _post_entry("2026-11-06", 10, "before range")
    _post_entry("2026-11-07", 20, "start boundary")
    _post_entry("2026-11-08", 30, "end boundary")
    _post_entry("2026-11-09", 40, "after range")

    rows = accounting.compute_trial_balance("2026-11-07", "2026-11-08")
    by_code = {row["account_code"]: row for row in rows}

    assert by_code["1100"]["total_debit"] == 50.0
    assert by_code["4000"]["total_credit"] == 50.0
    assert len(rows) == 2
