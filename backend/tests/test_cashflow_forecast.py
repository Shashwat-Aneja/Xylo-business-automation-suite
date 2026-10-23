from datetime import date
from decimal import Decimal

import pytest

from backend.accounting_engine.cashflow import CashMovement, build_forecast, money


AS_OF = date(2026, 10, 23)


def test_forecast_reconciles_opening_cash_and_source_movements():
    result = build_forecast(
        as_of=AS_OF,
        horizon_days=3,
        opening_cash_by_currency={"INR": "1000.00"},
        movements=[
            CashMovement(date(2026, 10, 24), "INR", Decimal("250.00"), "inflow", "INV-1"),
            CashMovement(date(2026, 10, 25), "INR", Decimal("75.50"), "outflow", "BILL-1"),
        ],
        business_timezone="Asia/Kolkata",
    )

    day_one, day_two, day_three = result.buckets
    assert day_one.opening_cash == Decimal("1000.00")
    assert day_one.closing_forecast == Decimal("1250.00")
    assert day_two.opening_cash == Decimal("1250.00")
    assert day_two.closing_forecast == Decimal("1174.50")
    assert day_three.closing_forecast == Decimal("1174.50")
    assert day_one.inflow_sources == ({"source_id": "INV-1", "amount": "250.00"},)


def test_forecast_never_nets_different_currencies():
    result = build_forecast(
        as_of=AS_OF,
        horizon_days=1,
        opening_cash_by_currency={"INR": "1000", "USD": "10"},
        movements=[
            CashMovement(date(2026, 10, 24), "USD", Decimal("5"), "outflow", "BILL-USD"),
        ],
        business_timezone="Asia/Kolkata",
    )

    balances = {bucket.currency: bucket.closing_forecast for bucket in result.buckets}
    assert balances == {"INR": Decimal("1000.00"), "USD": Decimal("5.00")}


def test_unposted_movements_are_ignored():
    result = build_forecast(
        as_of=AS_OF,
        horizon_days=1,
        opening_cash_by_currency={"INR": "100"},
        movements=[
            CashMovement(date(2026, 10, 24), "INR", Decimal("500"), "inflow", "DRAFT-1", status="draft"),
        ],
        business_timezone="Asia/Kolkata",
    )

    assert result.buckets[0].expected_inflows == Decimal("0.00")
    assert result.buckets[0].closing_forecast == Decimal("100.00")


def test_movements_outside_forecast_window_are_ignored():
    result = build_forecast(
        as_of=AS_OF,
        horizon_days=1,
        opening_cash_by_currency={"INR": "100"},
        movements=[
            CashMovement(AS_OF, "INR", Decimal("10"), "inflow", "TODAY"),
            CashMovement(date(2026, 10, 25), "INR", Decimal("20"), "inflow", "LATER"),
        ],
        business_timezone="Asia/Kolkata",
    )

    assert result.buckets[0].expected_inflows == Decimal("0.00")


@pytest.mark.parametrize("horizon", [0, -1, 367])
def test_horizon_is_bounded(horizon):
    with pytest.raises(ValueError):
        build_forecast(
            as_of=AS_OF,
            horizon_days=horizon,
            opening_cash_by_currency={},
            movements=[],
            business_timezone="Asia/Kolkata",
        )


@pytest.mark.parametrize("amount", ["NaN", "Infinity", "-Infinity", "not-money"])
def test_money_rejects_non_finite_or_invalid_amounts(amount):
    with pytest.raises(ValueError):
        money(amount)


def test_forecast_requires_timezone_and_valid_currency():
    with pytest.raises(ValueError):
        build_forecast(
            as_of=AS_OF, horizon_days=1, opening_cash_by_currency={"INR": "1"},
            movements=[], business_timezone="",
        )
    with pytest.raises(ValueError):
        build_forecast(
            as_of=AS_OF, horizon_days=1, opening_cash_by_currency={"IN": "1"},
            movements=[], business_timezone="Asia/Kolkata",
        )


def test_source_warnings_are_preserved_without_duplicates():
    result = build_forecast(
        as_of=AS_OF,
        horizon_days=1,
        opening_cash_by_currency={"INR": "0"},
        movements=[],
        business_timezone="Asia/Kolkata",
        source_warnings=["supplier payment workflow unavailable", "supplier payment workflow unavailable"],
    )

    assert result.warnings == ("supplier payment workflow unavailable",)
    assert result.buckets[0].warnings == result.warnings
