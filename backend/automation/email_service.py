# backend/automation/email_service.py
"""
XYLO — Email Service (Lightweight)

This module provides:
- SMTP email sending
- Support for attachments
- Simple HTML or text emails
- Standardised email wrapper for automation tasks

For production:
- Configure environmental variables (SMTP server, credentials)
- Replace smtplib with transactional email (SendGrid, SES, Mailgun)
"""

import smtplib
import ssl
from email.message import EmailMessage
from typing import Optional, List


# ------------------------------------------------------------
# Configuration (use environment variables in production)
# ------------------------------------------------------------
SMTP_HOST = "smtp.gmail.com"
SMTP_PORT = 465  # SSL
SMTP_USERNAME = "your-email@gmail.com"  # placeholder
SMTP_PASSWORD = "your-app-password"     # placeholder

SENDER_NAME = "XYLO Automation"
SENDER_EMAIL = SMTP_USERNAME


# ------------------------------------------------------------
# Public Function: send_email
# ------------------------------------------------------------
def send_email(
    to: str,
    subject: str,
    body: str,
    attachments: Optional[List[str]] = None,
    html: bool = False,
) -> bool:
    """
    Sends an email via SMTP.

    :param to: recipient email
    :param subject: subject line
    :param body: email content
    :param attachments: list of file paths
    :param html: interpret body as HTML
    :return: success (True/False)
    """
    try:
        msg = EmailMessage()
        msg["From"] = f"{SENDER_NAME} <{SENDER_EMAIL}>"
        msg["To"] = to
        msg["Subject"] = subject

        if html:
            msg.add_alternative(body, subtype="html")
        else:
            msg.set_content(body)

        # Attach files
        if attachments:
            for path in attachments:
                try:
                    with open(path, "rb") as f:
                        data = f.read()
                        filename = path.split("/")[-1]
                        msg.add_attachment(
                            data,
                            maintype="application",
                            subtype="octet-stream",
                            filename=filename,
                        )
                except Exception as e:
                    print(f"[email_service] Could not attach '{path}': {e}")

        # SSL context
        context = ssl.create_default_context()

        # Connect and send
        with smtplib.SMTP_SSL(SMTP_HOST, SMTP_PORT, context=context) as server:
            server.login(SMTP_USERNAME, SMTP_PASSWORD)
            server.send_message(msg)

        print(f"[XYLO Email] Sent email to {to} — '{subject}'")
        return True

    except Exception as e:
        print(f"[XYLO Email] Error sending email: {e}")
        return False


# For quick smoke testing:
if __name__ == "__main__":
    print("Sending test email...")
    send_email(
        to="recipient@example.com",
        subject="XYLO Test Email",
        body="This is a test email from XYLO Automation.",
    )
