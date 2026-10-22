"""Invoice reminder delivery orchestration.

Call this only after the application has authenticated the actor, authorized access
to the invoice, confirmed that a reminder is appropriate, and loaded recipient data
from trusted business records. This module intentionally exposes no public endpoint.
"""
from __future__ import annotations

from typing import Any

from backend.api.email_templates import invoice_reminder_email
from backend.api.resend_mail import send_transactional_email


def send_invoice_reminder(
    *,
    recipient_email: str,
    recipient_name: str,
    business_name: str,
    invoice_number: str,
    amount: str,
    due_date: str,
    invoice_url: str,
) -> dict[str, Any]:
    """Compose and send one authorized invoice reminder via Resend."""
    message = invoice_reminder_email(
        recipient_name=recipient_name,
        business_name=business_name,
        invoice_number=invoice_number,
        amount=amount,
        due_date=due_date,
        invoice_url=invoice_url,
    )
    result = send_transactional_email(
        to=recipient_email,
        subject=message["subject"],
        html=message["html"],
        text=message["text"],
    )
    return {"provider": "resend", "message_id": result["id"]}
