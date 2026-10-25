import sqlite3

import pytest

import backend.accounting_engine.stubs as accounting


@pytest.fixture
def isolated_database(tmp_path, monkeypatch):
    db_path = tmp_path / "journal-validation.sqlite3"
    monkeypatch.setattr(accounting, "DB_PATH", str(db_path))
    accounting._ensure_schema()
    return db_path


def balanced_lines():
    return [
        {"account_code": "1100", "debit": 25.00, "credit": 0},
        {"account_code": "4000", "debit": 0, "credit": 25.00},
    ]


@pytest.mark.parametrize(
    ("mutate", "message"),
    [
        (lambda lines: lines[0].update(debit=-1), "cannot be negative"),
        (lambda lines: lines[0].update(debit=float("nan")), "must be finite"),
        (lambda lines: lines[0].update(debit=float("inf")), "must be finite"),
        (lambda lines: lines[0].update(debit=0, credit=0), "positive debit or credit"),
        (lambda lines: lines[0].update(credit=1), "both debit and credit"),
        (lambda lines: lines[0].update(account_code="  "), "requires an account_code"),
    ],
)
def test_invalid_journal_lines_are_rejected_before_persistence(
    isolated_database, mutate, message
):
    lines = balanced_lines()
    mutate(lines)

    with pytest.raises(ValueError, match=message):
        accounting.create_journal_entry(
            transaction_id=None,
            entry_date="2026-10-25",
            description="validation test",
            lines=lines,
        )

    with sqlite3.connect(isolated_database) as connection:
        count = connection.execute("SELECT COUNT(*) FROM journal_entries").fetchone()[0]
    assert count == 0


def test_unbalanced_entry_is_rejected_before_persistence(isolated_database):
    lines = balanced_lines()
    lines[0]["debit"] = 26.00

    with pytest.raises(ValueError, match="do not equal Credits"):
        accounting.create_journal_entry(None, "2026-10-25", "unbalanced", lines)

    with sqlite3.connect(isolated_database) as connection:
        count = connection.execute("SELECT COUNT(*) FROM journal_entries").fetchone()[0]
    assert count == 0


def test_valid_balanced_entry_is_persisted(isolated_database):
    entry_id = accounting.create_journal_entry(
        None, "2026-10-25", "balanced", balanced_lines()
    )

    with sqlite3.connect(isolated_database) as connection:
        row = connection.execute(
            "SELECT id, description FROM journal_entries WHERE id = ?", (entry_id,)
        ).fetchone()
        line_count = connection.execute(
            "SELECT COUNT(*) FROM journal_lines WHERE journal_entry_id = ?", (entry_id,)
        ).fetchone()[0]

    assert row == (entry_id, "balanced")
    assert line_count == 2
