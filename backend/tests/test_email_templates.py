"""Unit tests for branded Xylo email composition."""
import unittest

from backend.api.email_templates import invoice_reminder_email


class InvoiceReminderTemplateTests(unittest.TestCase):
    def test_composes_text_and_html_and_escapes_untrusted_fields(self):
        message = invoice_reminder_email(
            recipient_name='<script>alert("x")</script>',
            business_name="A&B Services",
            invoice_number="INV-2026-014",
            amount="₹12,500.00",
            due_date="22 October 2026",
            invoice_url="https://example.com/invoices/INV-2026-014",
        )
        self.assertIn("INV-2026-014", message["subject"])
        self.assertIn("&lt;script&gt;", message["html"])
        self.assertNotIn("<script>", message["html"])
        self.assertIn("₹12,500.00", message["text"])
        self.assertIn("https://example.com/invoices/INV-2026-014", message["text"])

    def test_rejects_non_https_invoice_link(self):
        with self.assertRaises(ValueError):
            invoice_reminder_email(
                recipient_name="Client",
                business_name="Example",
                invoice_number="INV-1",
                amount="100.00",
                due_date="22 October 2026",
                invoice_url="http://example.com/invoice",
            )

    def test_requires_invoice_fields(self):
        with self.assertRaises(ValueError):
            invoice_reminder_email(
                recipient_name="Client",
                business_name="",
                invoice_number="INV-1",
                amount="100.00",
                due_date="22 October 2026",
                invoice_url="https://example.com/invoice",
            )


if __name__ == "__main__":
    unittest.main()
