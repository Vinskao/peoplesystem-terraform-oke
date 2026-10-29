"""Import SMTP credentials from stdin without persisting plaintext locally."""
import base64
import json
import subprocess
import sys


def store(config, runner=subprocess.run):
    if not isinstance(config, dict) or set(config) != {'host', 'username', 'password'}:
        raise ValueError('Invalid credential fields')
    if config['host'] != 'smtp.email.ap-singapore-2.oci.oraclecloud.com':
        raise ValueError('Invalid endpoint')
    if any(not isinstance(v, str) or not v or '\r' in v or '\n' in v for v in config.values()):
        raise ValueError('Invalid credential value')
    options = dict(stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
    existing = runner(['kubectl', '-n', 'mail-system', 'get', 'secret', 'oci-smtp', '-o', 'json'], **options)
    if existing.returncode == 0:
        try:
            saved = json.loads(base64.b64decode(json.loads(existing.stdout)['data']['relay.json']))
        except (ValueError, KeyError, TypeError):
            raise ValueError('Existing secret differs') from None
        if saved != config:
            raise ValueError('Existing secret differs')
        return
    if 'NotFound' not in existing.stderr:
        raise RuntimeError('Cannot inspect SMTP secret')
    encoded = base64.b64encode(json.dumps(config).encode('utf-8')).decode('ascii')
    manifest = {'apiVersion': 'v1', 'kind': 'Secret', 'type': 'Opaque',
                'metadata': {'name': 'oci-smtp', 'namespace': 'mail-system'},
                'data': {'relay.json': encoded}}
    created = runner(['kubectl', 'create', '-f', '-'], input=json.dumps(manifest), **options)
    if created.returncode:
        raise RuntimeError('Cannot create SMTP secret')


if __name__ == '__main__':
    try:
        payload = sys.stdin.read(16385)
        if len(payload) > 16384:
            raise ValueError('Input too large')
        store(json.loads(payload))
    except Exception as error:
        print('SMTP secret import failed: ' + type(error).__name__, file=sys.stderr)
        sys.exit(1)
    print('SMTP secret stored')
