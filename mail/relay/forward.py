#!/usr/bin/env python3
"""Postfix pipe delivery: re-envelope one allowed inbox through OCI over TLS.

The original message is attached byte-for-byte. Failures return EX_TEMPFAIL so
Postfix retains the original in its durable queue and retries delivery.
"""
import argparse
import hashlib
import json
import re
import smtplib
import ssl
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone
from email import policy
from email.message import EmailMessage
from email.parser import BytesParser
from email.utils import format_datetime, getaddresses
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit

SENDER = "tianyikao@tymultiverse.cc"
RECIPIENT = "tianyikao@gmail.com"
MAX_ORIGINAL_BYTES = 1_000_000
MAX_SUBMISSION_BYTES = 2_000_000
EX_TEMPFAIL = 75


@dataclass(frozen=True)
class RelayConfig:
    host: str
    username: str
    password: str = field(repr=False)

    def __post_init__(self):
        if not re.fullmatch(r"smtp\.email\.[a-z0-9-]+\.oci\.oraclecloud\.com", self.host):
            raise ValueError("An OCI Email Delivery endpoint is required")
        if not self.username or not self.password:
            raise ValueError("SMTP credentials are required")


class _HTMLPreview(HTMLParser):
    """Produce inert plain text while keeping verification-link destinations."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []
        self.hidden = 0
        self.links = []

    def handle_starttag(self, tag, attrs):
        if tag in {"script", "style"}:
            self.hidden += 1
        if self.hidden:
            return
        if tag in {"br", "p", "div", "li", "tr"}:
            self.parts.append("\n")
        if tag == "a":
            href = dict(attrs).get("href", "") or ""
            self.links.append(href if urlsplit(href).scheme.lower() in {"https", "http", "mailto"} else "")

    def handle_endtag(self, tag):
        if tag in {"script", "style"} and self.hidden:
            self.hidden -= 1
            return
        if self.hidden:
            return
        if tag == "a" and self.links:
            href = self.links.pop()
            if href:
                self.parts.append(f" ({href})")
        if tag in {"p", "div", "li", "tr"}:
            self.parts.append("\n")

    def handle_data(self, data):
        if not self.hidden:
            self.parts.append(data)


def _line(value):
    return " ".join(str(value or "").splitlines())[:500]


def _reply_address(source):
    for header in ("Reply-To", "From"):
        for _, address in getaddresses([str(v) for v in source.get_all(header, [])]):
            if address.isascii() and re.fullmatch(r"[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", address):
                return address
    return None


def _preview(source):
    body = source.get_body(preferencelist=("plain", "html"))
    if body is None:
        return "Open original.eml to read the original message and its attachments."
    try:
        text = body.get_content()
    except (LookupError, UnicodeError):
        text = (body.get_payload(decode=True) or b"").decode("utf-8", errors="replace")
    if not isinstance(text, str):
        return "Open original.eml to read the original message and its attachments."
    if body.get_content_type() == "text/html":
        parser = _HTMLPreview()
        parser.feed(text)
        text = "".join(parser.parts)
    return text[:50_000]


def build_message(raw):
    if len(raw) > MAX_ORIGINAL_BYTES:
        raise ValueError("Original message exceeds the configured inbound size limit")
    source = BytesParser(policy=policy.default).parsebytes(raw)
    msg = EmailMessage(policy=policy.SMTP)
    msg["From"] = f"TY Multiverse Mail <{SENDER}>"
    msg["To"] = RECIPIENT
    msg["Subject"] = _line(source["Subject"]) or "(no subject)"
    reply_to = _reply_address(source)
    if reply_to:
        msg["Reply-To"] = reply_to
    msg["Date"] = format_datetime(datetime.now(timezone.utc))
    digest = hashlib.sha256(raw).hexdigest()[:40]
    msg["Message-ID"] = f"<forward-{digest}@tymultiverse.cc>"
    msg["Auto-Submitted"] = "auto-forwarded"
    msg["X-Auto-Response-Suppress"] = "All"
    msg.set_content(
        f"Forwarded for {SENDER}\n"
        f"Original From: {_line(source['From'])}\n"
        f"Original To: {_line(source['To'])}\n"
        f"Original Date: {_line(source['Date'])}\n"
        f"Original Subject: {_line(source['Subject'])}\n\n"
        f"{_preview(source)}\n\n"
        "The complete original message, including original headers and attachments, is attached as original.eml.\n"
    )
    msg.add_attachment(raw, maintype="application", subtype="octet-stream", filename="original.eml")
    if len(msg.as_bytes()) > MAX_SUBMISSION_BYTES:
        raise ValueError("Wrapped message exceeds the configured OCI submission limit")
    return msg


def deliver(raw, recipient, config, *, smtp_factory=smtplib.SMTP_SSL):
    if recipient != RECIPIENT:
        raise ValueError("Delivery destination is not allowlisted")
    message = build_message(raw)
    with smtp_factory(config.host, 465, timeout=30, context=ssl.create_default_context()) as smtp:
        smtp.login(config.username, config.password)
        smtp.send_message(message, from_addr=SENDER, to_addrs=[RECIPIENT])


def run(raw, recipient, config, *, deliver_fn=deliver):
    try:
        deliver_fn(raw, recipient, config)
        return 0
    except Exception as exc:
        # SMTP exception text can contain credentials, addresses or message data.
        print(f"OCI relay deferred ({type(exc).__name__})", file=sys.stderr)
        return EX_TEMPFAIL


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--recipient", required=True)
    args = parser.parse_args()
    try:
        config = RelayConfig(**json.loads(Path(args.config).read_text(encoding="utf-8")))
        raw = sys.stdin.buffer.read(MAX_ORIGINAL_BYTES + 1)
        return run(raw, args.recipient, config)
    except Exception as exc:
        print(f"OCI relay deferred ({type(exc).__name__})", file=sys.stderr)
        return EX_TEMPFAIL


if __name__ == "__main__":
    raise SystemExit(main())
