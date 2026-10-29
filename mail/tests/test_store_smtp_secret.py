import base64
import json
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'relay'))
from store_smtp_secret import store


class StoreSecretTests(unittest.TestCase):
    def config(self):
        return {'host':'smtp.email.ap-singapore-2.oci.oraclecloud.com', 'username':'fixture-user', 'password':'fixture-secret'}

    def test_creates_only_the_fixed_secret_without_plaintext_annotations(self):
        runner=Mock(side_effect=[SimpleNamespace(returncode=1,stdout='',stderr='NotFound'), SimpleNamespace(returncode=0,stdout='created',stderr='')])
        store(self.config(), runner=runner)
        call=runner.call_args
        secret=json.loads(call.kwargs['input'])
        self.assertEqual(secret['metadata']['namespace'],'mail-system')
        self.assertEqual(secret['metadata']['name'],'oci-smtp')
        self.assertNotIn('annotations',secret['metadata'])
        self.assertNotIn('stringData',secret)
        self.assertEqual(json.loads(base64.b64decode(secret['data']['relay.json'])),self.config())
        self.assertEqual(call.args[0],['kubectl','create','-f','-'])

    def test_repeated_identical_import_does_not_rotate_or_overwrite(self):
        existing={'data':{'relay.json':base64.b64encode(json.dumps(self.config()).encode()).decode()}}
        runner=Mock(return_value=SimpleNamespace(returncode=0,stdout=json.dumps(existing),stderr=''))
        store(self.config(),runner=runner)
        runner.assert_called_once()

    def test_existing_different_secret_is_preserved(self):
        runner=Mock(return_value=SimpleNamespace(returncode=0,stdout='{"data":{}}',stderr=''))
        with self.assertRaises(ValueError): store(self.config(),runner=runner)
        runner.assert_called_once()

    def test_invalid_endpoint_never_calls_kubernetes(self):
        config=self.config(); config['host']='attacker.example.org'
        runner=Mock()
        with self.assertRaises(ValueError): store(config,runner=runner)
        runner.assert_not_called()

    def test_server_error_does_not_expose_payload(self):
        runner=Mock(side_effect=[SimpleNamespace(returncode=1,stdout='',stderr='NotFound'),SimpleNamespace(returncode=1,stdout='',stderr='fixture-secret')])
        with self.assertRaises(RuntimeError) as caught: store(self.config(),runner=runner)
        self.assertNotIn('fixture-secret',str(caught.exception))

    def test_forbidden_read_is_not_treated_as_missing_secret(self):
        runner=Mock(return_value=SimpleNamespace(returncode=1,stdout='',stderr='Forbidden'))
        with self.assertRaises(RuntimeError): store(self.config(),runner=runner)
        runner.assert_called_once()


if __name__ == '__main__': unittest.main()
