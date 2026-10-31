import contextlib
import io
import ssl
import sys
import unittest
from email import policy
from email.parser import BytesParser
from pathlib import Path
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "relay"))
from forward import (  # noqa: E402
    MAX_ORIGINAL_BYTES, RECIPIENT, SENDER, RelayConfig,
    build_message, deliver, run,
)


ORIGINAL = (
    b"From: Example Sender <sender@example.org>\r\n"
    b"To: tianyikao@peoplesystem.tatdvsonorth.com\r\n"
    b"Subject: Verify your business address\r\n"
    b"Message-ID: <fixture@example.org>\r\n"
    b"Content-Type: text/plain; charset=utf-8\r\n\r\n"
    b"Follow https://example.org/verify?code=fixture to verify.\r\n"
)


class ForwardMessageTests(unittest.TestCase):
    def test_uses_only_approved_sender_and_allowlisted_recipient(self):
        msg = build_message(ORIGINAL)
        self.assertEqual(msg["From"].addresses[0].addr_spec, SENDER)
        self.assertEqual(msg["To"].addresses[0].addr_spec, RECIPIENT)
        self.assertEqual(msg["Reply-To"].addresses[0].addr_spec, "sender@example.org")
        self.assertEqual(str(msg["Subject"]), "Verify your business address")
        self.assertEqual(str(msg["Auto-Submitted"]), "auto-forwarded")

    def test_sends_as_the_primary_domain_approved_sender(self):
        # Must match an OCI Approved Sender in ty-mail; the old domain stays receive-only.
        self.assertEqual(SENDER, "tianyikao@tymultiverse.cc")
        self.assertTrue(str(build_message(ORIGINAL)["Message-ID"]).endswith("@tymultiverse.cc>"))

    def test_preserves_original_bytes_and_readable_verification_link(self):
        msg = build_message(ORIGINAL)
        serialized = msg.as_bytes(policy=policy.SMTP)
        reparsed = BytesParser(policy=policy.default).parsebytes(serialized)
        attachment = next(reparsed.iter_attachments())
        self.assertEqual(attachment.get_filename(), "original.eml")
        self.assertEqual(attachment.get_payload(decode=True), ORIGINAL)
        self.assertIn("https://example.org/verify?code=fixture", reparsed.get_body().get_content())
        self.assertIn("sender@example.org", reparsed.get_body().get_content())

    def test_honors_valid_original_reply_to(self):
        raw = ORIGINAL.replace(b"To:", b"Reply-To: support@example.org\r\nTo:", 1)
        self.assertEqual(build_message(raw)["Reply-To"].addresses[0].addr_spec, "support@example.org")

    def test_does_not_copy_bcc_or_untrusted_routing_headers(self):
        raw = ORIGINAL.replace(b"To:", b"Bcc: attacker@example.net\r\nReturn-Path: <bad@example.net>\r\nTo:", 1)
        msg = build_message(raw)
        self.assertIsNone(msg["Bcc"])
        self.assertIsNone(msg["Return-Path"])
        self.assertEqual(len(msg["To"].addresses), 1)

    def test_html_only_preview_keeps_safe_links_without_scripts(self):
        raw = (
            b"From: sender@example.org\r\nSubject: HTML\r\n"
            b"Content-Type: text/html; charset=utf-8\r\n\r\n"
            b'<p>Click <a href="https://example.org/verify?x=1&amp;y=2">Verify</a></p>'
            b'<script>secretScript()</script><a href="javascript:bad()">Ignore</a>'
        )
        body = build_message(raw).get_body().get_content()
        self.assertIn("https://example.org/verify?x=1&y=2", body)
        self.assertNotIn("secretScript", body)
        self.assertNotIn("javascript:", body)

    def test_invalid_reply_address_is_not_propagated(self):
        raw = ORIGINAL.replace(b"Example Sender <sender@example.org>", b"not-an-address")
        self.assertIsNone(build_message(raw)["Reply-To"])

    def test_retries_have_a_stable_message_id(self):
        self.assertEqual(build_message(ORIGINAL)["Message-ID"], build_message(ORIGINAL)["Message-ID"])

    def test_oversize_original_is_rejected_before_submission(self):
        with self.assertRaises(ValueError):
            build_message(b"x" * (MAX_ORIGINAL_BYTES + 1))


class RelayDeliveryTests(unittest.TestCase):
    def config(self):
        return RelayConfig("smtp.email.ap-singapore-2.oci.oraclecloud.com", "test-user", "test-secret")

    def test_authenticated_tls_submission_has_fixed_envelope(self):
        smtp = Mock()
        smtp.__enter__ = Mock(return_value=smtp)
        smtp.__exit__ = Mock(return_value=False)
        factory = Mock(return_value=smtp)
        deliver(ORIGINAL, RECIPIENT, self.config(), smtp_factory=factory)
        args, kwargs = factory.call_args
        self.assertEqual(args, (self.config().host, 465))
        self.assertEqual(kwargs["context"].verify_mode, ssl.CERT_REQUIRED)
        self.assertTrue(kwargs["context"].check_hostname)
        smtp.login.assert_called_once_with("test-user", "test-secret")
        self.assertEqual(smtp.send_message.call_args.kwargs, {"from_addr": SENDER, "to_addrs": [RECIPIENT]})

    def test_other_destination_never_opens_a_connection(self):
        factory = Mock()
        with self.assertRaises(ValueError):
            deliver(ORIGINAL, "attacker@example.net", self.config(), smtp_factory=factory)
        factory.assert_not_called()

    def test_failure_defers_postfix_delivery_without_logging_secrets(self):
        def fail(*args, **kwargs):
            raise RuntimeError("password=test-secret original message content")
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            code = run(ORIGINAL, RECIPIENT, self.config(), deliver_fn=fail)
        self.assertEqual(code, 75)
        self.assertNotIn("test-secret", stderr.getvalue())
        self.assertNotIn("original message content", stderr.getvalue())

    def test_non_oci_endpoint_is_rejected(self):
        with self.assertRaises(ValueError):
            RelayConfig("attacker.example.net", "user", "secret")


if __name__ == "__main__":
    unittest.main()
