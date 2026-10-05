# SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
# Copyright (c) 2026 Xudong Xu

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class CommandTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.cli = os.environ['JSON_SCHEMA_CLI']

    def tearDown(self):
        self.directory.cleanup()

    def file(self, name, value):
        path = self.root / name
        path.write_text(json.dumps(value))
        return str(path)

    def run_cli(self, *args, stdin=None):
        return subprocess.run([self.cli, *args], input=stdin, text=True, capture_output=True)

    def test_version_and_help(self):
        version = Path('VERSION').read_text().strip()
        self.assertEqual(self.run_cli('--version').stdout.strip(), version)
        self.assertIn('validate SCHEMA INSTANCE', self.run_cli('--help').stdout)

    def test_validation_and_structured_outputs(self):
        schema = self.file('schema.json', {'type': 'integer', 'minimum': 0})
        good = self.file('good.json', 2)
        bad = self.file('bad.json', -1)
        for output in ['flag', 'basic', 'detailed', 'verbose']:
            result = self.run_cli('validate', schema, good, '--output', output)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(json.loads(result.stdout)['valid'])
            result = self.run_cli('validate', schema, bad, '--output', output)
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertFalse(json.loads(result.stdout)['valid'])
        result = self.run_cli('validate', schema, bad, '--output', 'human')
        self.assertIn('minimum', result.stdout)

    def test_stdin_errors_and_format_assertions(self):
        schema = self.file('schema.json', {'type': 'string', 'format': 'email'})
        self.assertEqual(self.run_cli('validate', schema, '-', stdin='"wrong"').returncode, 0)
        self.assertEqual(self.run_cli('validate', schema, '-', '--assert-formats', stdin='"wrong"').returncode, 1)
        self.assertEqual(self.run_cli('validate', schema, '-', stdin='{broken').returncode, 2)
        self.assertEqual(self.run_cli('validate', schema, '--output', 'unknown').returncode, 2)
        self.assertEqual(self.run_cli('unknown', schema).returncode, 2)

    def test_metaschema_check_and_offline_bundle(self):
        invalid = self.file('invalid.json', {'type': 'not-a-type'})
        self.assertEqual(self.run_cli('check', invalid).returncode, 1)
        schema = self.file('root.json', {'$id': 'https://example.test/root', '$ref': 'number'})
        remote = self.file('number.json', {'type': 'integer'})
        self.assertEqual(self.run_cli('bundle', schema).returncode, 2)
        result = self.run_cli('bundle', schema, '--registry', 'https://example.test/number=' + remote)
        self.assertEqual(result.returncode, 0, result.stderr)
        bundle = self.file('bundle.json', json.loads(result.stdout))
        good = self.file('good.json', 2)
        self.assertEqual(self.run_cli('validate', bundle, good).returncode, 0)
