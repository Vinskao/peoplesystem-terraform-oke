"""Integration checks for the private OCI PROXY-protocol backend; no DATA."""
import os
import smtplib
import socket
import ssl
import unittest

HOSTNAME = 'mx.peoplesystem.tatdvsonorth.com'


class ProxySmtpTests(unittest.TestCase):
    def connect(self):
        smtp = smtplib.SMTP(timeout=10)
        smtp._host = HOSTNAME
        smtp.sock = socket.create_connection((os.environ.get('PROXY_TEST_HOST', '127.0.0.1'),
                                             int(os.environ.get('PROXY_TEST_PORT', '2525'))), 10)
        self.addCleanup(smtp.close)
        smtp.sock.sendall(b'PROXY TCP4 203.0.113.10 140.245.52.231 45000 25\r\n')
        self.assertEqual(smtp.getreply()[0], 220)
        smtp.ehlo('probe.example.org')
        return smtp

    def test_trusted_tls_uses_the_mail_hostname(self):
        smtp = self.connect()
        smtp.starttls(context=ssl.create_default_context())
        self.assertIn(('DNS', HOSTNAME), smtp.sock.getpeercert()['subjectAltName'])

    def test_owner_address_is_accepted(self):
        smtp = self.connect()
        self.assertEqual(smtp.mail('probe@example.org')[0], 250)
        self.assertEqual(smtp.rcpt('tianyikao@peoplesystem.tatdvsonorth.com')[0], 250)

    def test_external_relay_is_denied(self):
        smtp = self.connect()
        self.assertEqual(smtp.mail('probe@example.org')[0], 250)
        self.assertIn(smtp.rcpt('unrelated-recipient@gmail.com')[0], (550, 554))

    def test_unknown_local_recipient_is_denied(self):
        smtp = self.connect()
        self.assertEqual(smtp.mail('probe@example.org')[0], 250)
        self.assertEqual(smtp.rcpt('unknown@peoplesystem.tatdvsonorth.com')[0], 550)


if __name__ == '__main__':
    unittest.main(verbosity=2)
