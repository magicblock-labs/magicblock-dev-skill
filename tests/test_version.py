import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "check_version", Path(__file__).resolve().parents[1] / "scripts/check-version.py"
)
version = importlib.util.module_from_spec(spec)
spec.loader.exec_module(version)


class VersionCheckTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git("init", "-q")
        (self.root / "skill").mkdir()
        self.write("skill/SKILL.md", "Original skill\n")
        self.write("skill/references/guide.md", "Original reference\n")
        self.write("build.sh", "original build\n")
        self.write("install.sh", "original installer\n")
        self.write("README.md", "original readme\n")
        self.release("0.1.0")
        self.git("add", ".")
        self.git("-c", "user.name=dhruvja", "-c", "user.email=dhruvja@users.noreply.github.com",
                 "commit", "-qm", "test: initial version fixture")

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, text=True,
                                       stderr=subprocess.DEVNULL)

    def write(self, path, content):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)

    def release(self, number):
        self.write("skill/VERSION", number + "\n")
        self.write("CHANGELOG.md", f"# Changelog\n\n## {number}\n\n- Test change.\n")

    def test_unchanged_and_readme_only_pass(self):
        version.check(self.root, "HEAD")
        self.write("README.md", "updated readme\n")
        version.check(self.root, "HEAD")

    def test_content_and_packaging_require_bump(self):
        for path in ("skill/SKILL.md", "skill/references/guide.md", "build.sh", "install.sh"):
            with self.subTest(path=path):
                original = (self.root / path).read_text()
                self.write(path, "changed\n")
                with self.assertRaisesRegex(ValueError, "increase skill/VERSION"):
                    version.check(self.root, "HEAD")
                self.write(path, original)

    def test_deleted_reference_requires_bump(self):
        (self.root / "skill/references/guide.md").unlink()
        with self.assertRaisesRegex(ValueError, "increase skill/VERSION"):
            version.check(self.root, "HEAD")

    def test_valid_bumps_pass(self):
        self.write("skill/SKILL.md", "updated skill\n")
        for number in ("0.1.1", "0.2.0", "1.0.0", "0.10.0"):
            with self.subTest(number=number):
                self.release(number)
                version.check(self.root, "HEAD")

    def test_bump_requires_current_changelog_entry(self):
        self.write("skill/VERSION", "0.1.1\n")
        with self.assertRaisesRegex(ValueError, "CHANGELOG.md"):
            version.check(self.root, "HEAD")

    def test_downgrade_fails(self):
        self.release("0.0.9")
        with self.assertRaisesRegex(ValueError, "cannot decrease"):
            version.check(self.root, "HEAD")

    def test_invalid_versions_fail(self):
        for number in ("v0.1.0", "01.1.0", "1.0", "1.0.0-beta", "1.0.0\n2.0.0"):
            with self.subTest(number=number):
                self.release(number)
                with self.assertRaisesRegex(ValueError, "MAJOR.MINOR.PATCH"):
                    version.check(self.root, "HEAD")

    def test_missing_base_fails(self):
        with self.assertRaises(subprocess.CalledProcessError):
            version.check(self.root, "missing-ref")

    def test_initial_version(self):
        self.git("rm", "-q", "skill/VERSION")
        self.git("-c", "user.name=dhruvja", "-c", "user.email=dhruvja@users.noreply.github.com",
                 "commit", "-qm", "test: unversioned fixture")
        self.release("0.1.0")
        version.check(self.root, "HEAD")
        self.release("0.2.0")
        with self.assertRaisesRegex(ValueError, "initial tracked version"):
            version.check(self.root, "HEAD")


if __name__ == "__main__":
    unittest.main()
