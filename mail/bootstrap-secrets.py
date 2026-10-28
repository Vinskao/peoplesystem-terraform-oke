"""Run on the SSH operator. Generate an installation-specific SRS secret without printing it."""
import base64
import json
import secrets
import subprocess

check = subprocess.run(['kubectl', '-n', 'mail-system', 'get', 'secret', 'mail-signing', '-o', 'name'],
                       universal_newlines=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
if check.returncode == 0:
    print('mail-signing already exists; retained')
elif 'NotFound' in check.stderr:
    value = base64.b64encode(secrets.token_hex(32).encode('ascii')).decode('ascii')
    secret = {'apiVersion': 'v1', 'kind': 'Secret', 'type': 'Opaque',
              'metadata': {'name': 'mail-signing', 'namespace': 'mail-system'}, 'data': {'srs': value}}
    subprocess.run(['kubectl', 'create', '-f', '-'], input=json.dumps(secret), universal_newlines=True, check=True)
else:
    raise SystemExit(check.stderr)
