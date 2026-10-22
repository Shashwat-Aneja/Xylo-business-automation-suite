"""Server-side Resend client for Xylo transactional email.

The API key must only be supplied through the server environment. Never import
this module into browser code or return provider credentials in API responses.
"""
from __future__ import annotations

import json
import os
import re
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

RESEND_EMAILS_URL = "https://api.resend.com/emails"
_SENDER_RE = re.compile(r"^(?:[^<>]*<)?([^<>\\s@]+@[^<>\\s@]+\\.[^<>\\s@]+)>?$")
_EMAIL_RE = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")


class ResendConfigurationError(RuntimeError):
    """Raised when required server-side email configuration is missing."""


class ResendDeliveryError(RuntimeError):
    """Raised when Resend rejects a transactional email request."""


def send_transactional_email(
    *,
    to: str,
    subject: str,
    html: str,
    text: str,
    reply_to: str | None = None,
    timeout_seconds: float = 10.0,
) -> dict[str, Any]:
    """Send one transactional email and return Resend's non-secret response.

    Callers must authorize the action and validate the recipient/business
    context before calling this provider adapter.
    """
    api_key = os.environ.get("RESEND_API_KEY", "").strip()
    from_email = os.environ.get("RESEND_FROM_EMAIL", "").strip()

    if not api_key:
        raise ResendConfigurationError("RESEND_API_KEY is not configured.")
    sender_address = from_email.rsplit("<", 1)[-1].rstrip("> ").strip() if "<" in from_email else from_email
    if not sender_address or not _EMAIL_RE.fullmatch(sender_address):
        raise ResendConfigurationError(
            "RESEND_FROM_EMAIL must be a valid address on a verified sending domain."
        )
    if not _EMAIL_RE.fullmatch(to.strip()):
        raise ValueError("Recipient email address is invalid.")
    if not subject.strip():
        raise ValueError("Email subject cannot be empty.")
    if not html.strip() and not text.strip():
        raise ValueError("Provide HTML or plain-text email content.")

    payload: dict[str, Any] = {
        "from": from_email,
        "to": [to.strip()],
        "subject": subject.strip(),
        "html": html,
        "text": text,
    }
    if reply_to:
        if not _EMAIL_RE.fullmatch(reply_to.strip()):
            raise ValueError("Reply-to email address is invalid.")
        payload["reply_to"] = reply_to.strip()

    request = Request(
        RESEND_EMAILS_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "User-Agent": "Xylo-Transactional-Mail/1.0",
        },
        method="POST",
    )
    try:
        with urlopen(request, timeout=timeout_seconds) as response:
            result = json.loads(response.read().decode("utf-8"))
            if not isinstance(result, dict) or not result.get("id"):
                raise ResendDeliveryError("Resend returned an unexpected response.")
            return {"id": result["id"]}
    except HTTPError as exc:
        # Do not propagate request headers or API-key material into logs/errors.
        detail = exc.read().decode("utf-8", errors="replace")[:1000]
        raise ResendDeliveryError(
            f"Resend rejected the email request (HTTP {exc.code}): {detail}"
        ) from None
    except URLError as exc:
        raise ResendDeliveryError("Resend could not be reached.") from None
    except TimeoutError:
        raise ResendDeliveryError("Resend request timed out.") from None
