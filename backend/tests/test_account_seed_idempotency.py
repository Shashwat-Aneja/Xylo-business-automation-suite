import sqlite3

import backend.accounting_engine.stubs as accounting


def test_seeding_default_accounts_twice_does_not_duplicate_rows(tmp_path, monkeypatch):
    database = tmp_path / "accounts.sqlite3"
    monkeypatch.setattr(accounting, "DB_PATH", str(database))

    accounting.seed_default_accounts()
    accounting.seed_default_accounts()

    with sqlite3.connect(database) as connection:
        count = connection.execute("SELECT COUNT(*) FROM accounts").fetchone()[0]
        codes = {
            row[0]
            for row in connection.execute("SELECT code FROM accounts").fetchall()
        }

    assert count == 8
    assert codes == {"1000", "1100", "2000", "3000", "4000", "5000", "5100", "5200"}
