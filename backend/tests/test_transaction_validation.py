from datetime import datetime, timezone

import pytest
from fastapi import HTTPException

from backend.api.main import TransactionCreate, add_transaction


@pytest.mark.parametrize("amount", [float("nan"), float("inf"), float("-inf")])
def test_add_transaction_rejects_non_finite_amounts(amount):
    transaction = TransactionCreate(
        date=datetime(2026, 10, 10, tzinfo=timezone.utc),
        amount=amount,
        description="validation test",
    )

    with pytest.raises(HTTPException) as exc_info:
        add_transaction(transaction)

    assert exc_info.value.status_code == 422
    assert exc_info.value.detail == "Transaction amount must be a finite number."
