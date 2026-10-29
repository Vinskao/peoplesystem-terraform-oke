"""Staging only: deliver one synthetic message to a loopback SMTP sink, never Gmail."""
import email.policy
import email.utils
from email.message import EmailMessage
from email.parser import BytesParser
import json
import re
import smtplib
import socketserver
import subprocess
import threading
import uuid


def run(*args):
    return subprocess.check_output(args, text=True).strip()


received = {}
done = threading.Event()


class Sink(socketserver.StreamRequestHandler):
    def handle(self):
        self.wfile.write(b'220 local verification sink\r\n')
        while True:
            line = self.rfile.readline()
            if not line:
                break
            command = line.split(b' ', 1)[0].upper().strip()
            if command in (b'EHLO', b'HELO'):
                self.wfile.write(b'250 local-sink\r\n')
            elif command == b'MAIL':
                received['envelope'] = line.decode().strip()
                self.wfile.write(b'250 OK\r\n')
            elif command == b'RCPT':
                received['recipient'] = line.decode().strip()
                self.wfile.write(b'250 OK\r\n')
            elif command == b'DATA':
                self.wfile.write(b'354 end with dot\r\n')
                body = []
                while True:
                    part = self.rfile.readline()
                    if part in (b'.\r\n', b''):
                        break
                    body.append(part[1:] if part.startswith(b'..') else part)
                received['message'] = BytesParser(policy=email.policy.default).parsebytes(b''.join(body))
                self.wfile.write(b'250 accepted by local sink\r\n')
                done.set()
            elif command == b'QUIT':
                self.wfile.write(b'221 bye\r\n')
                break
            else:
                self.wfile.write(b'250 OK\r\n')


if run('postqueue', '-j'):
    raise SystemExit('Run only on an empty staging queue; refusing to redirect existing messages')

original = {key: run('postconf', '-h', key) for key in ('relayhost', 'smtp_tls_security_level')}
message_id = email.utils.make_msgid(domain='peoplesystem.tatdvsonorth.com')
server = socketserver.ThreadingTCPServer(('127.0.0.1', 2525), Sink)
server.daemon_threads = True
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    run('postconf', '-e', 'relayhost=[127.0.0.1]:2525', 'smtp_tls_security_level=none')
    run('postfix', 'reload')
    message = EmailMessage()
    message['From'] = 'SMTP Verification <sender@example.org>'
    message['To'] = 'tianyikao@peoplesystem.tatdvsonorth.com'
    message['Subject'] = 'Synthetic local mail-forward verification'
    message['Date'] = email.utils.formatdate(localtime=False)
    message['Message-ID'] = message_id
    message.set_content('Synthetic content for local-only verification: ' + uuid.uuid4().hex)
    with smtplib.SMTP('127.0.0.1', 25, timeout=30) as smtp:
        smtp.ehlo('probe.example.org')
        smtp.send_message(message)
    if not done.wait(30):
        raise AssertionError('Forwarded message did not reach the loopback sink')
    actual = received['message']
    assert actual['From'] == message['From'], 'Original From was changed'
    assert actual['Message-ID'] == message_id
    assert 'tianyikao@gmail.com' in received['recipient'], 'Wrong forwarding destination'
    assert 'SRS0=' in received['envelope'] or 'SRS1=' in received['envelope'], 'Missing SRS envelope rewrite'
    assert actual['ARC-Seal'], 'Missing ARC seal'
    assert actual['ARC-Authentication-Results'], 'Missing ARC authentication results'
    srs_address = re.search(r'<([^>]+)>', received['envelope']).group(1)
    with smtplib.SMTP('127.0.0.1', 25, timeout=15) as smtp:
        smtp.ehlo('probe.example.org')
        assert smtp.mail('')[0] == 250
        assert smtp.rcpt(srs_address)[0] == 250, 'Valid SRS bounce recipient was rejected'
    # SMTP serializes line endings as CRLF; compare identical content after that canonicalization.
    actual_body = actual.get_body(preferencelist=('plain',)).get_content().replace('\r\n', '\n')
    assert actual_body == message.get_content().replace('\r\n', '\n'), 'Original body was changed'
    print('PASS: forwarding destination, original From/body, SRS envelope and bounce recipient, ARC seal and authentication results')
finally:
    run('postconf', '-e', *(f'{key}={value}' for key, value in original.items()))
    run('postfix', 'reload')
    server.shutdown()
    server.server_close()
    # Only remove the unique synthetic test message if delivery failed; never purge a real queue.
    for row in run('postqueue', '-j').splitlines():
        item = json.loads(row)
        content = run('postcat', '-q', item['queue_id'])
        if message_id in content:
            run('postsuper', '-d', item['queue_id'])
