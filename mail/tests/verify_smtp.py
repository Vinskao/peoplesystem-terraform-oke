"""Run inside the mailserver pod. Does not send DATA or deliver real email."""
import os
import smtplib
import socket
import ssl
import subprocess
import unittest

DOMAIN = 'peoplesystem.tatdvsonorth.com'


class SmtpPolicyTests(unittest.TestCase):
    def setUp(self):
        self.smtp = smtplib.SMTP(os.environ.get('SMTP_TEST_HOST', '127.0.0.1'), 25, timeout=15)
        self.smtp.ehlo('probe.example.org')
        self.addCleanup(self.smtp.close)

    def recipient(self, address):
        self.assertEqual(self.smtp.mail('sender@example.org')[0], 250)
        return self.smtp.rcpt(address)[0]

    def test_known_alias_is_accepted(self):
        self.assertEqual(self.recipient(f'hello@{DOMAIN}'), 250)

    def test_unknown_recipient_is_rejected_before_data(self):
        self.assertEqual(self.recipient(f'not-a-mailbox@{DOMAIN}'), 550)

    def test_forged_srs_recipient_is_rejected(self):
        self.assertEqual(self.recipient(f'SRS0=invalid=invalid=example.org=sender@{DOMAIN}'), 550)

    def test_external_relay_is_denied_even_from_localhost(self):
        self.assertIn(self.recipient('unrelated-recipient@gmail.com'), (550, 554))

    def test_starttls_with_the_known_staging_certificate(self):
        context = ssl.create_default_context(cafile='/var/mail-state/tls/cert.pem')
        # SMTP connects by loopback; check the expected hostname after verifying the certificate chain.
        context.check_hostname = False
        self.smtp.starttls(context=context)
        common_names = [value for entry in self.smtp.sock.getpeercert()['subject']
                        for key, value in entry if key == 'commonName']
        self.assertIn(f'mx.{DOMAIN}', common_names)

    def test_rspamd_configuration_is_valid(self):
        subprocess.run(['rspamadm', 'configtest'], check=True, capture_output=True)

    def test_rspamd_controller_is_not_reachable_on_pod_ip(self):
        pod_ip = socket.gethostbyname(socket.gethostname())
        with self.assertRaises(OSError):
            with socket.create_connection((pod_ip, 11334), timeout=2):
                pass

    def test_forwarding_map_has_no_catchall(self):
        def lookup(address):
            result = subprocess.run(['postmap', '-q', address, 'texthash:/tmp/docker-mailserver/postfix-virtual.cf'],
                                    text=True, capture_output=True)
            self.assertIn(result.returncode, (0, 1), result.stderr)
            return result.stdout.strip()
        self.assertEqual(lookup(f'hello@{DOMAIN}'), 'tianyikao@gmail.com')
        self.assertEqual(lookup(f'@{DOMAIN}'), '')


if __name__ == '__main__':
    unittest.main(verbosity=2)
