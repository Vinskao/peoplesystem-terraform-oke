import os
import base64
import shlex
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "pg-dump.sh"


def bash_path(path):
    value = Path(path).resolve().as_posix()
    if len(value) > 2 and value[1] == ":":
        return f"/mnt/{value[0].lower()}{value[2:]}"
    return value


class PgDumpPipelineTests(unittest.TestCase):
    def setUp(self):
        bash = shutil.which("bash")
        if not bash:
            self.skipTest("Bash is required to run the production pg-dump script")
        self.bash = bash
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.bin_dir = self.root / "bin"
        self.dump_dir = self.root / "dump"
        self.bin_dir.mkdir()
        self.dump_dir.mkdir()
        pg_dump = self.bin_dir / "pg_dump"
        pg_dump.write_text(
            "#!/bin/sh\n"
            "printf 'CREATE TABLE sample (id integer);\\n'\n"
            "if [ \"${FAIL_PG_DUMP:-0}\" = 1 ]; then exit 17; fi\n",
            encoding="utf-8",
        )
        pg_dump.chmod(0o755)

    def tearDown(self):
        self.temp.cleanup()

    def run_dump(self, fail=False):
        fake_dump = base64.b64encode(
            (self.bin_dir / "pg_dump").read_bytes()
        ).decode("ascii")
        command = "\n".join(
            [
                "set -e",
                "test_bin=$(mktemp -d)",
                f"printf %s {shlex.quote(fake_dump)} | base64 -d > \"$test_bin/pg_dump\"",
                "chmod +x \"$test_bin/pg_dump\"",
                f"export PATH=\"$test_bin:/usr/bin:/bin\" DUMP_DIR={shlex.quote(bash_path(self.dump_dir))}",
                "export PGDATABASE=testdb PGHOST=localhost PGPORT=5432 PGUSER=testuser",
                f"export FAIL_PG_DUMP={1 if fail else 0}",
                f"{shlex.quote(bash_path(SCRIPT))}",
            ]
        )
        return subprocess.run(
            [self.bash, "-c", command], capture_output=True, text=True
        )

    def test_pg_dump_failure_fails_pipeline(self):
        result = self.run_dump(fail=True)

        self.assertNotEqual(result.returncode, 0)

    def test_success_creates_verified_nonempty_gzip(self):
        result = self.run_dump()

        self.assertEqual(result.returncode, 0, result.stderr)
        archives = list(self.dump_dir.glob("*.sql.gz"))
        self.assertEqual(len(archives), 1)
        self.assertGreater(archives[0].stat().st_size, 0)
        verify = subprocess.run(["gzip", "-t", str(archives[0])], capture_output=True)
        self.assertEqual(verify.returncode, 0)

    def test_failed_dump_leaves_no_valid_archive_for_upload(self):
        self.run_dump(fail=True)

        archives = list(self.dump_dir.glob("*.sql.gz"))
        self.assertEqual(archives, [])


if __name__ == "__main__":
    unittest.main()
