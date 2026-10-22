"""Xylo transactional email composition.

Templates are plain application code so messages remain version-controlled and do
not require a browser-side template editor. All user-controlled values are escaped.
"""
from __future__ import annotations

from html import escape
from urllib.parse import urlparse


def _safe_absolute_url(value: str) -> str:
    parsed = urlparse(value)
    if parsed.scheme != "https" or not parsed.netloc:
        raise ValueError("Action links must be absolute HTTPS URLs.")
    return value


def invoice_reminder_email(
    *,
    recipient_name: str,
    business_name: str,
    invoice_number: str,
    amount: str,
    due_date: str,
    invoice_url: str,
) -> dict[str, str]:
    """Compose a restrained, accessible invoice reminder.

    The caller must confirm the invoice is genuinely due and that the requesting
    user is authorized to send this reminder before invoking the email adapter.
    """
    action_url = _safe_absolute_url(invoice_url)
    name = escape(recipient_name.strip() or "there")
    business = escape(business_name.strip())
    invoice = escape(invoice_number.strip())
    total = escape(amount.strip())
    due = escape(due_date.strip())
    if not business or not invoice or not total or not due:
        raise ValueError("Business, invoice number, amount and due date are required.")

    subject = f"Payment reminder: invoice {invoice_number.strip()}"
    text = (
        f"Hello {recipient_name.strip() or 'there'},\n\n"
        f"This is a reminder from {business_name.strip()} that invoice "
        f"{invoice_number.strip()} for {amount.strip()} was due on {due_date.strip()}.\n\n"
        f"Review the invoice: {action_url}\n\n"
        "If you have already paid, please disregard this reminder."
    )
    html = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Payment reminder</title></head>
<body style="margin:0;padding:0;background:#f3efe6;color:#24231f;font-family:Arial,Helvetica,sans-serif">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f3efe6;padding:28px 12px"><tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:600px;background:#faf8f2;border:1px solid #d7d1c5">
<tr><td style="padding:28px 30px;border-bottom:1px solid #d7d1c5;font-family:Georgia,'Times New Roman',serif;font-size:34px;letter-spacing:-1px">Xylo<span style="color:#873f32">.</span></td></tr>
<tr><td style="padding:30px">
<p style="margin:0 0 12px;color:#74745d;font-size:11px;letter-spacing:2px;text-transform:uppercase">Payment reminder</p>
<h1 style="margin:0 0 20px;font-family:Georgia,'Times New Roman',serif;font-size:30px;font-weight:400;line-height:1.2">An invoice is ready for your attention.</h1>
<p style="font-size:15px;line-height:1.7">Hello {name},</p>
<p style="font-size:15px;line-height:1.7"><strong>{business}</strong> is reminding you about invoice <strong>{invoice}</strong>, due on {due}.</p>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:22px 0;border-top:1px solid #d7d1c5;border-bottom:1px solid #d7d1c5"><tr><td style="padding:18px 0;color:#77766e;font-size:12px">Amount due</td><td align="right" style="padding:18px 0;font-size:20px;font-weight:bold">{total}</td></tr></table>
<p style="margin:26px 0"><a href="{escape(action_url, quote=True)}" style="display:inline-block;padding:13px 18px;background:#873f32;color:#fff;text-decoration:none;font-size:13px">Review invoice ↗</a></p>
<p style="font-size:12px;line-height:1.7;color:#77766e">If you have already paid, please disregard this reminder. For questions, contact {business} directly.</p>
</td></tr><tr><td style="padding:18px 30px;border-top:1px solid #d7d1c5;color:#77766e;font-size:11px">Sent through Xylo · Business records, kept clear.</td></tr>
</table></td></tr></table></body></html>"""
    return {"subject": subject, "html": html, "text": text}
