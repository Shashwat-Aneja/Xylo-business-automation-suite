from datetime import datetime, timezone

import pytest
from pydantic import ValidationError

from backend.api.main import TransactionCreate


def test_transaction_currency_is_normalized_to_uppercase():
    transaction = TransactionCreate(
        date=datetime(2026, 10, 11, tzinfo=timezone.utc),
        amount=25.0,
        currency="usd",
    )

    assert transaction.currency == "USD"


@pytest.mark.parametrize("currency", ["US", "USDD", "12A", "", "IN R"])
def test_transaction_rejects_invalid_currency_codes(currency):
    with pytest.raises(ValidationError):
        TransactionCreate(
            date=datetime(2026, 10, 11, tzinfo=timezone.utc),
            amount=25.0,
            currency=currency,
        )
