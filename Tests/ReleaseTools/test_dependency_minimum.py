# SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
# Copyright (c) 2026 Xudong Xu

from pathlib import Path
import runpy
import unittest

TOOLS = runpy.run_path(str(Path(__file__).resolve().parents[2] / 'Scripts/check-dependency-minimum'))


class DependencyMinimumTests(unittest.TestCase):
    def test_selects_the_requested_dependency_lower_bound(self):
        manifest = {'dependencies': [{'sourceControl': [{
            'identity': name,
            'requirement': {'range': [{'lowerBound': low, 'upperBound': high}]},
        }]} for name, low, high in [('other', '1.0.0', '2.0.0'), ('syntax', '602.0.0', '605.0.0')]]}
        self.assertEqual(TOOLS['minimum_version'](manifest, 'syntax'), '602.0.0')

    def test_rejects_a_revision_requirement(self):
        manifest = {'dependencies': [{'sourceControl': [{
            'identity': 'syntax', 'requirement': {'revision': ['abc']},
        }]}]}
        with self.assertRaisesRegex(ValueError, 'version range'):
            TOOLS['minimum_version'](manifest, 'syntax')

    def test_rejects_a_resolver_that_keeps_the_upper_pin(self):
        lock = {'pins': [{'identity': 'syntax', 'state': {'version': '604.0.0', 'revision': 'abc'}}]}
        with self.assertRaisesRegex(ValueError, 'required minimum'):
            TOOLS['resolved_pin'](lock, 'syntax', '602.0.0')

    def test_records_the_actual_selected_revision(self):
        pin = {'identity': 'syntax', 'state': {'version': '602.0.0', 'revision': 'abc'}}
        self.assertEqual(TOOLS['resolved_pin']({'pins': [pin]}, 'syntax', '602.0.0'), pin)


if __name__ == '__main__':
    unittest.main()
