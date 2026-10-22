"""Unit tests for the Resend adapter; no live network calls are made."""
import json
import os
import unittest
from unittest.mock import patch, MagicMock

from backend.api.resend_mail import (
    ResendConfigurationError,
    ResendDeliveryError,
    send_transactional_email,
)


class ResendMailTests(unittest.TestCase):
    def setUp(self):
        self.env = patch.dict(
            os.environ,
            {
                "RESEND_API_KEY": "test-key-not-a-real-credential",
                "RESEND_FROM_EMAIL": "Xylo <mail@mail.shashwataneja.com>",
            },
            clear=False,
        )
        self.env.start()
        self.addCleanup(self.env.stop)

    @patch("backend.api.resend_mail.urlopen")
    def test_sends_with_server_key_and_returns_only_message_id(self, urlopen):
        response = MagicMock()
        response.read.return_value = json.dumps({"id": "email_test_123"}).encode()
        response.__enter__.return_value = response
        urlopen.return_value = response

        result = send_transactional_email(
            to="client@example.com",
            subject="Invoice reminder",
            html="<p>Invoice reminder</p>",
            text="Invoice reminder",
        )

        self.assertEqual(result, {"id": "email_test_123"})
        request = urlopen.call_args.args[0]
        self.assertEqual(request.full_url, "https://api.resend.com/emails")
        self.assertEqual(request.get_header("Authorization"), "Bearer test-key-not-a-real-credential")
        self.assertEqual(json.loads(request.data)["to"], ["client@example.com"])

    @patch.dict(os.environ, {"RESEND_API_KEY": "", "RESEND_FROM_EMAIL": ""})
    def test_requires_server_configuration(self):
        with self.assertRaises(ResendConfigurationError):
            send_transactional_email(
                to="client@example.com",
                subject="Hello",
                html="<p>Hello</p>",
                text="Hello",
            )

    def test_rejects_invalid_recipient_before_network_call(self):
        with patch("backend.api.resend_mail.urlopen") as urlopen:
            with self.assertRaises(ValueError):
                send_transactional_email(
                    to="not-an-email",
                    subject="Hello",
                    html="<p>Hello</p>",
                    text="Hello",
                )
            urlopen.assert_not_called()

    @patch("backend.api.resend_mail.urlopen")
    def test_provider_rejection_is_reported_without_secret(self, urlopen):
        from urllib.error import HTTPError
        urlopen.side_effect = HTTPError(
            "https://api.resend.com/emails", 403, "Forbidden", {}, None
        )
        with self.assertRaises(ResendDeliveryError) as raised:
            send_transactional_email(
                to="client@example.com",
                subject="Hello",
                html="<p>Hello</p>",
                text="Hello",
            )
        self.assertNotIn("test-key-not-a-real-credential", str(raised.exception))


if __name__ == "__main__":
    unittest.main()
