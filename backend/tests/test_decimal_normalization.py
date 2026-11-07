from decimal import Decimal

import pytest

from backend.accounting_engine import stubs as accounting


@pytest.mark.parametrize(
    ("value", "expected"),
    [
        ("1.005", Decimal("1.01")),
        ("1.004", Decimal("1.00")),
        ("-1.005", Decimal("-1.01")),
        ("0.005", Decimal("0.01")),
        ("10", Decimal("10.00")),
    ],
)
def test_decimal_normalization_uses_currency_precision(value, expected):
    assert accounting._decimal(value) == expected
