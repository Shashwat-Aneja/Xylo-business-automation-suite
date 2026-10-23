"""Deterministic, database-agnostic cashflow calculations.

This module accepts only explicitly supplied, already-authorized source rows.
Database adapters must enforce business scope and pass only posted accounting records.
All monetary arithmetic uses Decimal; values are never aggregated across currencies.
"""
from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass
from datetime import date, timedelta
from decimal import Decimal, InvalidOperation
from typing import Iterable, Mapping, Sequence

ZERO = Decimal("0.00")


def money(value: object) -> Decimal:
    """Parse a finite decimal currency amount without binary floating-point math."""
    try:
        amount = Decimal(str(value))
    except (InvalidOperation, ValueError, TypeError) as exc:
        raise ValueError("amount must be a valid decimal value") from exc
    if not amount.is_finite():
        raise ValueError("amount must be finite")
    rounded = amount.quantize(Decimal("0.01"))
    if amount != rounded:
        raise ValueError("amount cannot contain fractional minor currency units")
    return rounded


@dataclass(frozen=True)
class CashMovement:
    date: date
    currency: str
    amount: Decimal
    direction: str
    source_id: str
    status: str = "posted"


@dataclass(frozen=True)
class ForecastBucket:
    date: date
    currency: str
    opening_cash: Decimal
    expected_inflows: Decimal
    expected_outflows: Decimal
    closing_forecast: Decimal
    inflow_sources: tuple[Mapping[str, str], ...] = ()
    outflow_sources: tuple[Mapping[str, str], ...] = ()
    warnings: tuple[str, ...] = ()


@dataclass(frozen=True)
class ForecastResult:
    as_of: date
    horizon_days: int
    buckets: tuple[ForecastBucket, ...]
    warnings: tuple[str, ...] = ()


def build_forecast(
    *,
    as_of: date,
    horizon_days: int,
    opening_cash_by_currency: Mapping[str, object],
    movements: Iterable[CashMovement],
    business_timezone: str,
    source_warnings: Sequence[str] = (),
) -> ForecastResult:
    """Build daily forecast buckets for each currency, without cross-currency netting.

    Opening balances must come from the authorized database layer using posted
    cash/bank journal lines. Movements must come from authorized posted documents.
    The caller must pass the business-local as-of date and timezone label explicitly.
    """
    if horizon_days < 1 or horizon_days > 366:
        raise ValueError("horizon_days must be between 1 and 366")
    if not business_timezone or not business_timezone.strip():
        raise ValueError("business_timezone is required")

    opening: dict[str, Decimal] = {}
    for currency, value in opening_cash_by_currency.items():
        normalized = currency.strip().upper()
        if len(normalized) != 3 or not normalized.isalpha() or not normalized.isascii():
            raise ValueError(f"invalid ISO-style currency code: {currency!r}")
        if normalized in opening:
            raise ValueError(f"duplicate currency after normalization: {normalized}")
        opening[normalized] = money(value)

    inflows: dict[tuple[date, str], list[tuple[str, Decimal]]] = defaultdict(list)
    outflows: dict[tuple[date, str], list[tuple[str, Decimal]]] = defaultdict(list)
    warnings = list(dict.fromkeys(source_warnings))

    for movement in movements:
        currency = movement.currency.strip().upper()
        if len(currency) != 3 or not currency.isascii() or not currency.isalpha():
            raise ValueError(f"invalid ISO-style currency code: {movement.currency!r}")
        if movement.status != "posted":
            continue
        if movement.date <= as_of or movement.date > as_of + timedelta(days=horizon_days):
            continue
        amount = money(movement.amount)
        if amount < ZERO:
            raise ValueError("movement amount must be non-negative; use direction to indicate flow")
        if movement.direction == "inflow":
            inflows[(movement.date, currency)].append((movement.source_id, amount))
        elif movement.direction == "outflow":
            outflows[(movement.date, currency)].append((movement.source_id, amount))
        else:
            raise ValueError("direction must be 'inflow' or 'outflow'")

    currencies = sorted(set(opening) | {currency for _, currency in inflows} | {currency for _, currency in outflows})
    buckets: list[ForecastBucket] = []
    for currency in currencies:
        balance = opening.get(currency, ZERO)
        for offset in range(1, horizon_days + 1):
            bucket_date = as_of + timedelta(days=offset)
            incoming = inflows.get((bucket_date, currency), [])
            outgoing = outflows.get((bucket_date, currency), [])
            inflow_total = sum((amount for _, amount in incoming), ZERO)
            outflow_total = sum((amount for _, amount in outgoing), ZERO)
            opening_balance = balance
            balance = (balance + inflow_total - outflow_total).quantize(Decimal("0.01"))
            buckets.append(ForecastBucket(
                date=bucket_date,
                currency=currency,
                opening_cash=opening_balance,
                expected_inflows=inflow_total,
                expected_outflows=outflow_total,
                closing_forecast=balance,
                inflow_sources=tuple({"source_id": source_id, "amount": str(amount)} for source_id, amount in incoming),
                outflow_sources=tuple({"source_id": source_id, "amount": str(amount)} for source_id, amount in outgoing),
                warnings=tuple(warnings),
            ))
    return ForecastResult(as_of=as_of, horizon_days=horizon_days, buckets=tuple(buckets), warnings=tuple(warnings))
