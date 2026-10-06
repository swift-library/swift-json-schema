# SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
# Copyright (c) 2026 Xudong Xu

import json
from pathlib import Path
import re
import runpy
import shutil
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


class ConsumerTests(unittest.TestCase):
    def test_product_dependencies_resolve_in_a_renamed_checkout(self):
        fixtures = ROOT / ".build/test-fixtures"
        fixtures.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=fixtures) as temporary:
            root = Path(temporary) / "renamed-package"
            (root / "Scripts").mkdir(parents=True)
            (root / ".github").mkdir()
            shutil.copy2(ROOT / "Scripts/check-consumer", root / "Scripts/check-consumer")
            (root / ".github/release.json").write_text(json.dumps({
                "documentation_targets": ["JSONValue", "JSONSchema"],
            }))
            with patch("subprocess.run", side_effect=RuntimeError("stop before compilation")):
                with self.assertRaisesRegex(RuntimeError, "stop before compilation"):
                    runpy.run_path(str(root / "Scripts/check-consumer"))
            manifest = root / ".build/example-consumer/Package.swift"
            text = manifest.read_text()
            dependency = re.search(r'\.package\(name: ("[^"\n]+"), path: ("[^"\n]+")\)', text)
            self.assertIsNotNone(dependency)
            name, path = (json.loads(value) for value in dependency.groups())
            self.assertFalse(Path(path).is_absolute())
            self.assertEqual((manifest.parent / path).resolve(), root.resolve())
            self.assertEqual(set(re.findall(r'package: "([^"\n]+)"', text)), {name})
            self.assertNotIn(str(root), text)


if __name__ == "__main__":
    unittest.main()
