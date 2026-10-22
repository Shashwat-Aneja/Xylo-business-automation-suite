"""Tests invoice reminder delivery orchestration without sending real email."""
import unittest
from unittest.mock import patch

from backend.api.invoice_mail import send_invoice_reminder


class InvoiceMailDeliveryTests(unittest.TestCase):
    @patch("backend.api.invoice_mail.send_transactional_email")
    def test_composes_and_delivers_reminder(self, send_email):
        send_email.return_value = {"id": "resend_test_456"}
        result = send_invoice_reminder(
            recipient_email="client@example.com",
            recipient_name="Client",
            business_name="Example Services",
            invoice_number="INV-22",
            amount="₹1,250",
            due_date="22 October 2026",
            invoice_url="https://example.com/invoices/INV-22",
        )
        self.assertEqual(result, {"provider": "resend", "message_id": "resend_test_456"})
        kwargs = send_email.call_args.kwargs
        self.assertEqual(kwargs["to"], "client@example.com")
        self.assertIn("INV-22", kwargs["subject"])
        self.assertIn("Review invoice", kwargs["html"])

    @patch("backend.api.invoice_mail.send_transactional_email")
    def test_invalid_link_is_rejected_before_sending(self, send_email):
        with self.assertRaises(ValueError):
            send_invoice_reminder(
                recipient_email="client@example.com",
                recipient_name="Client",
                business_name="Example Services",
                invoice_number="INV-22",
                amount="₹1,250",
                due_date="22 October 2026",
                invoice_url="javascript:alert(1)",
            )
        send_email.assert_not_called()


if __name__ == "__main__":
    unittest.main()
