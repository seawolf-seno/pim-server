"""Tests for bin/pim-seed. Run: python3 -I -m unittest discover -s tests -p 'test_*.py'"""

import importlib.machinery
import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "fixtures" / "school"

loader = importlib.machinery.SourceFileLoader("pim_seed", str(ROOT / "bin" / "pim-seed"))
spec = importlib.util.spec_from_loader("pim_seed", loader)
seed = importlib.util.module_from_spec(spec)
loader.exec_module(seed)


def fixture_school():
    return seed.load_toml(FIXTURES / "school.toml")


class CheckSchool(unittest.TestCase):
    def test_fixture_is_valid(self):
        school = seed.check_school(fixture_school(), real=False)
        self.assertEqual(school["people"]["rteague29"]["role"], "student")
        self.assertEqual(school["people"]["okafor"]["role"], "staff")
        self.assertEqual(len(school["classes"]), 3)

    def test_refuses_unmarked_file_without_real(self):
        s = fixture_school()
        del s["fictional"]
        with self.assertRaisesRegex(seed.SeedError, "fictional"):
            seed.check_school(s, real=False)
        seed.check_school(s, real=True)

    def test_student_cannot_teach(self):
        s = fixture_school()
        s["class"][0]["teacher"] = "rteague29"
        with self.assertRaisesRegex(seed.SeedError, "not a staff"):
            seed.check_school(s, real=False)

    def test_staff_cannot_be_enrolled(self):
        s = fixture_school()
        s["class"][0]["students"].append("haddad")
        with self.assertRaisesRegex(seed.SeedError, "not a student"):
            seed.check_school(s, real=False)

    def test_unknown_login(self):
        s = fixture_school()
        s["activity"][0]["members"].append("ghost29")
        with self.assertRaisesRegex(seed.SeedError, "unknown login"):
            seed.check_school(s, real=False)

    def test_bad_login_and_name(self):
        s = fixture_school()
        s["person"][0]["login"] = "Bad Login"
        with self.assertRaisesRegex(seed.SeedError, "not a valid login"):
            seed.check_school(s, real=False)
        s = fixture_school()
        s["person"][0]["name"] = "a=b"
        with self.assertRaisesRegex(seed.SeedError, "one-line name"):
            seed.check_school(s, real=False)

    def test_duplicate_id(self):
        s = fixture_school()
        s["activity"][0]["id"] = "biology"
        with self.assertRaisesRegex(seed.SeedError, "id used twice"):
            seed.check_school(s, real=False)


class CheckSchedule(unittest.TestCase):
    def test_fixture_is_valid(self):
        sched = seed.check_schedule(seed.load_toml(FIXTURES / "schedule.toml"))
        self.assertEqual([b["number"] for b in sched["blocks"]], [1, 2, 3, 4])
        self.assertEqual(sched["fridays"]["2026-11-20"], "B")

    def test_bad_block(self):
        sched = seed.load_toml(FIXTURES / "schedule.toml")
        sched["blocks"][0]["end"] = "07:00"
        with self.assertRaisesRegex(seed.SeedError, "starts after it ends"):
            seed.check_schedule(sched)

    def test_day_both_a_and_b(self):
        sched = seed.load_toml(FIXTURES / "schedule.toml")
        sched["b_days"].append("Mon")
        with self.assertRaisesRegex(seed.SeedError, "both"):
            seed.check_schedule(sched)


class Groups(unittest.TestCase):
    def test_class_groups_and_teachers(self):
        text = seed.groups_file(seed.check_school(fixture_school(), real=False))
        biology = text.split("[Biology]\n", 1)[1].split("\n\n", 1)[0].splitlines()
        self.assertIn("okafor@pim.test=Mr. Okafor", biology)
        self.assertIn("rteague29@pim.test=Rowan Teague", biology)
        self.assertNotIn("amensah28@pim.test=Ama Mensah", biology)
        teachers = text.split("[Teachers]\n", 1)[1].splitlines()
        self.assertTrue(teachers)
        self.assertTrue(all(not seed.STUDENT_RE.match(line.split("@")[0]) for line in teachers))


class Build(unittest.TestCase):
    def run_seed(self, *extra, out):
        return subprocess.run(
            ["python3", "-I", str(ROOT / "bin" / "pim-seed"), "build",
             "--school", str(FIXTURES / "school.toml"),
             "--schedule", str(FIXTURES / "schedule.toml"), "--out", str(out), *extra],
            capture_output=True, text=True)

    def test_writes_files_and_prints_no_names(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "out"
            r = self.run_seed(out=out)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertNotIn("Rowan", r.stdout + r.stderr)
            data = json.loads((out / "school.json").read_text())
            self.assertEqual(data["schedule"]["blocks"][1]["start"], "09:35")
            self.assertIn("rteague29\n", (out / "accounts.txt").read_text())
            self.assertEqual((out / "groups.txt").stat().st_mode & 0o777, 0o600)

    def test_real_refuses_git_repo(self):
        # This repository is a git repository.
        r = self.run_seed("--real", out=ROOT / "build" / "real-test")
        self.assertEqual(r.returncode, 1)
        self.assertIn("git repository", r.stderr)


if __name__ == "__main__":
    unittest.main()
