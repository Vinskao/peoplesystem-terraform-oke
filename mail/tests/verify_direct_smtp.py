"""Integration checks for the direct (no PROXY header) backend behind the dedicated OCI NLB; no DATA.

The NLB preserves the client source IP itself, so this listener must work WITHOUT a PROXY header,
while still enforcing the same recipient and relay rules as port 25/2525.
Run inside the pod:  kubectl -n mail-system exec -i ty-mail-0 -- python3 - < mail/tests/verify_direct_smtp.py
Run from outside:    DIRECT_TEST_HOST=<nlb ip> DIRECT_TEST_PORT=25 python3 mail/tests/verify_direct_smtp.py
"""
import os
import smtplib
import ssl
import unittest

HOST = os.environ.get('DIRECT_TEST_HOST', '127.0.0.1')
PORT = int(os.environ.get('DIRECT_TEST_PORT', '2526'))
NEW_MX = 'mx.tymultiverse.cc'
OLD_MX = 'mx.peoplesystem.tatdvsonorth.com'


class DirectSmtpTests(unittest.TestCase):
    def connect(self):
        smtp = smtplib.SMTP(HOST, PORT, timeout=10)
        self.addCleanup(smtp.close)
        smtp.ehlo('probe.example.org')
        return smtp

    def test_banner_needs_no_proxy_header(self):
        smtp = smtplib.SMTP(timeout=10)
        self.addCleanup(smtp.close)
        code, _ = smtp.connect(HOST, PORT)
        self.assertEqual(code, 220)

    def test_trusted_tls_covers_both_mail_hostnames(self):
        smtp = self.connect()
        smtp._host = NEW_MX
        smtp.starttls(context=ssl.create_default_context())
        names = {value for kind, value in smtp.sock.getpeercert()['subjectAltName'] if kind == 'DNS'}
        self.assertIn(NEW_MX, names)
        self.assertIn(OLD_MX, names)

    def test_owner_addresses_on_both_domains_are_accepted(self):
        for rcpt in ('tianyikao@tymultiverse.cc', 'tianyikao@peoplesystem.tatdvsonorth.com'):
            with self.subTest(rcpt=rcpt):
                smtp = self.connect()
                self.assertEqual(smtp.mail('probe@example.org')[0], 250)
                self.assertEqual(smtp.rcpt(rcpt)[0], 250)

    def test_unknown_local_recipient_is_denied(self):
        smtp = self.connect()
        self.assertEqual(smtp.mail('probe@example.org')[0], 250)
        self.assertEqual(smtp.rcpt('unknown-probe@tymultiverse.cc')[0], 550)

    def test_external_relay_is_denied(self):
        smtp = self.connect()
        self.assertEqual(smtp.mail('probe@example.org')[0], 250)
        self.assertIn(smtp.rcpt('unrelated-recipient@gmail.com')[0], (550, 554))


if __name__ == '__main__':
    unittest.main(verbosity=2)
