import math
import sqlite3

import pytest

import backend.accounting_engine.stubs as accounting


@pytest.mark.parametrize("amount", [math.nan, math.inf, -math.inf])
def test_non_finite_transaction_amounts_are_rejected_before_schema_creation(
    tmp_path, monkeypatch, amount
):
    database = tmp_path / "invalid-transaction.sqlite3"
    monkeypatch.setattr(accounting, "DB_PATH", str(database))

    with pytest.raises(ValueError, match="finite number"):
        accounting.create_transaction(
            user_id="user-1",
            amount=amount,
            description="invalid amount",
        )

    assert not database.exists()


def test_non_datetime_transaction_date_is_rejected_before_persistence(
    tmp_path, monkeypatch
):
    database = tmp_path / "invalid-date.sqlite3"
    monkeypatch.setattr(accounting, "DB_PATH", str(database))

    with pytest.raises(ValueError, match="must be a datetime"):
        accounting.create_transaction(
            user_id="user-1",
            amount=10,
            description="invalid date",
            transaction_date="2026-11-07",
        )

    assert not database.exists()
