"""Validate relay transport using the real Postfix parser and a private copy.

Run inside the mail pod with RELAY_CONFIG_DIR pointing to the candidate overlay.
Does not reload Postfix, change the live configuration, or submit any mail.
"""
import os
import shlex
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


class RelayConfigTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = Path(os.environ.get("RELAY_CONFIG_DIR", "/tmp/docker-mailserver"))
        cls.temp = tempfile.TemporaryDirectory(prefix="ty-mail-postfix-check-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.config = Path(cls.temp.name)
        for name in ("main.cf", "master.cf"):
            shutil.copy2(Path("/etc/postfix") / name, cls.config / name)
        for line in (cls.source / "user-patches.sh").read_text().splitlines():
            if line.startswith("postconf "):
                subprocess.run(
                    ["postconf", "-c", str(cls.config), *shlex.split(line)[1:]],
                    check=True, capture_output=True, text=True,
                )

    def value(self, name):
        return subprocess.run(
            ["postconf", "-c", str(self.config), "-h", name],
            check=True, capture_output=True, text=True,
        ).stdout.strip()

    def lookup(self, address):
        result = subprocess.run(
            ["postmap", "-q", address, f"texthash:{self.source / 'oci-transport.cf'}"],
            capture_output=True, text=True,
        )
        self.assertIn(result.returncode, (0, 1), result.stderr)
        return result.stdout.strip()

    def test_transport_is_parsed_as_an_unprivileged_pipe(self):
        master = subprocess.run(
            ["postconf", "-c", str(self.config), "-M", "ociforward/unix"],
            check=True, capture_output=True, text=True,
        ).stdout
        self.assertIn("pipe", master)
        self.assertIn("user=nobody", master)
        self.assertIn("--recipient=${recipient}", master)
        self.assertEqual(self.value("ociforward_destination_recipient_limit"), "1")

    def test_only_owner_gmail_has_a_transport(self):
        self.assertEqual(self.lookup("tianyikao@gmail.com"), "ociforward:")
        self.assertEqual(self.lookup("attacker@gmail.com"), "")
        self.assertEqual(self.lookup("gmail.com"), "")

    def test_unmapped_destinations_cannot_fall_back_to_tcp25(self):
        for setting in ("default_transport", "relay_transport"):
            self.assertTrue(self.value(setting).startswith("error:"))

    def test_inbound_limit_keeps_wrapped_messages_below_oci_default(self):
        self.assertEqual(self.value("message_size_limit"), "1000000")

    def test_public_backend_requires_proxy_protocol_on_a_separate_port(self):
        result = subprocess.run(
            ['postconf', '-c', str(self.config), '-P', '2525/inet/smtpd_upstream_proxy_protocol'],
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('=haproxy', result.stdout.replace(' ', ''))
        self.assertEqual(self.value('smtpd_relay_restrictions'), 'reject_unauth_destination')


if __name__ == "__main__":
    unittest.main(verbosity=2)
