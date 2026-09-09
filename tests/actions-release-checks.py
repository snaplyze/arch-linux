#!/usr/bin/env python3
"""Check release allocation and API metadata without external writes."""

from __future__ import annotations

import importlib.util
from contextlib import redirect_stderr, redirect_stdout
import io
from pathlib import Path
import tarfile
import tempfile
import sys
import subprocess
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parent.parent
HELPER = ROOT / "repository/actions-release.py"


class ActionsReleaseChecks(unittest.TestCase):
    def setUp(self) -> None:
        self.assertTrue(HELPER.is_file(), "release publication helper is missing")
        spec = importlib.util.spec_from_file_location("actions_release", HELPER)
        assert spec is not None and spec.loader is not None
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)

    def test_version_allocation_never_reuses_retired_or_reserved_tags(self) -> None:
        for names, expected in (([], "1.0.2"), (["1.0.0", "1.0.1"], "1.0.2"),
                                (["1.0.2", "1.0.4", "packages-20260909.1"], "1.0.5")):
            self.assertEqual(self.module.next_version("1.0.2", names), expected)
        with self.assertRaises(ValueError):
            self.module.next_version("1.0.2", ["2.0.0"])

    def release(self) -> dict:
        names = ["BUILD-METADATA.json", "RELEASE-SHA256SUMS", "RELEASE-SHA256SUMS.sig", "UNSIGNED-SHA256SUMS",
                 "install.sh", "arch-linux-installer.sh", "arch-linux-installer.sh.sha256", "arch-linux-installer.sh.sig",
                 "arch-linux.gpg", "primary-fingerprint", "signing-subkey-fingerprint",
                 "arch-linux-repository-1.0.2.tar.zst", "arch-linux-repository-1.0.2.tar.zst.sha256",
                 "arch-linux-repository-1.0.2.tar.zst.sig", "arch-linux-acceptance-1.0.2.json",
                 "arch-linux-acceptance-1.0.2.json.sig", "arch-linux-acceptance-evidence-1.0.2.tar.zst",
                 "arch-linux-acceptance-evidence-1.0.2.tar.zst.sig"]
        return {"id": 7, "tag_name": "1.0.2", "name": "1.0.2", "draft": True, "prerelease": False,
                "assets": [{"id": n + 1, "name": name, "size": 1, "state": "uploaded", "digest": "sha256:" + "a" * 64}
                           for n, name in enumerate(names)]}

    def test_exact_asset_metadata_rejects_missing_extra_duplicate_and_unfinished(self) -> None:
        self.module.validate_metadata(self.release(), 7, "1.0.2", True)
        for change in (lambda x: x["assets"].pop(),
                       lambda x: x["assets"].append(dict(x["assets"][0])),
                       lambda x: x["assets"][0].update(name="unexpected"),
                       lambda x: x["assets"][0].update(digest=None),
                       lambda x: x["assets"][0].update(state="new"),
                       lambda x: x["assets"][0].update(size=0),
                       lambda x: x.update(draft=False),
                       lambda x: x.update(tag_name="1.0.1")):
            value = self.release()
            change(value)
            with self.assertRaises(ValueError):
                self.module.validate_metadata(value, 7, "1.0.2", True)

    def test_public_metadata_requires_actual_github_immutability(self) -> None:
        value = self.release()
        value.update(draft=False, immutable=False)
        with self.assertRaises(ValueError):
            self.module.validate_metadata(value, 7, "1.0.2", False)
        value["immutable"] = True
        self.module.validate_metadata(value, 7, "1.0.2", False)

    def test_evidence_extraction_rejects_traversal_and_links_before_writing(self) -> None:
        for name, kind in (("../outside", tarfile.REGTYPE), ("run/link", tarfile.SYMTYPE)):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                archive = root / "evidence.tar.gz"
                with tarfile.open(archive, "w:gz") as stream:
                    member = tarfile.TarInfo(name)
                    member.type = kind
                    member.linkname = "/etc/passwd" if kind == tarfile.SYMTYPE else ""
                    member.size = 0
                    stream.addfile(member, io.BytesIO())
                with self.assertRaises(ValueError):
                    self.module.unpack_evidence(archive, root / "output")
                self.assertFalse((root / "outside").exists())

    def test_same_main_selection_resumes_draft_or_reads_published_release(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            def git(*args: str) -> str:
                return subprocess.check_output(["git", "-C", str(root), *args], stderr=subprocess.DEVNULL).decode().strip()
            git("init", "-b", "main")
            git("config", "user.name", "Fixture")
            git("config", "user.email", "fixture@example.invalid")
            (root / "arch-linux-installer.sh").write_text("readonly VERSION='1.0.2'\n")
            git("add", ".")
            git("commit", "-m", "reviewed main")
            main_commit = git("rev-parse", "HEAD")
            (root / "repository").mkdir()
            (root / "repository/release-origin.json").write_text('{"mainCommit":"' + main_commit + '"}\n')
            git("add", ".")
            git("commit", "-m", "release source")
            git("tag", "-a", "1.0.2", "-m", "Actions-run-id: 123")
            git("reset", "--hard", main_commit)
            self.module.ROOT = root
            release = self.release()
            release["body"] = "Actions-run-id: 123"
            with patch.object(self.module, "releases", return_value=[release]):
                selection = self.module.select_release()
                self.assertEqual(selection, {"release_version": "1.0.2", "resume": "true", "already_published": "false",
                                             "resume_release_id": "7", "resume_run_id": "123"})
                release.update(draft=False, immutable=True)
                self.assertEqual(self.module.select_release()["already_published"], "true")

    def test_superseded_main_and_missing_immutability_policy_stop_publication(self) -> None:
        with patch.object(self.module, "command", return_value=b"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\trefs/heads/main\n"):
            with self.assertRaisesRegex(ValueError, "main has advanced"):
                self.module.require_latest_main({"main_commit": "a" * 40})
        with patch.dict(self.module.os.environ, {}, clear=True):
            with self.assertRaises(ValueError):
                self.module.require_immutability_policy()

    def test_manual_dispatch_can_only_resume_an_existing_release(self) -> None:
        for event, resume, accepted in (("workflow_run", "false", True),
                                        ("workflow_run", "true", True),
                                        ("workflow_dispatch", "true", True),
                                        ("workflow_dispatch", "false", False),
                                        ("push", "true", False), ("", "true", False)):
            with self.subTest(event=event, resume=resume), patch.dict(self.module.os.environ, {"GITHUB_EVENT_NAME": event}):
                if accepted:
                    self.module.require_release_trigger({"resume": resume})
                else:
                    with self.assertRaises(ValueError):
                        self.module.require_release_trigger({"resume": resume})

    def test_select_cli_applies_manual_recovery_gate_before_returning_candidate(self) -> None:
        for resume, expected_status in (("false", 1), ("true", 0)):
            with self.subTest(resume=resume), \
                    patch.dict(self.module.os.environ, {"GITHUB_EVENT_NAME": "workflow_dispatch", "GITHUB_REPOSITORY": "snaplyze/arch-linux"}), \
                    patch.object(self.module.sys, "argv", ["actions-release.py", "select"]), \
                    patch.object(self.module, "select_release", return_value={"resume": resume}), \
                    redirect_stdout(io.StringIO()) as output, redirect_stderr(io.StringIO()):
                self.assertEqual(self.module.main(), expected_status)
            self.assertEqual(bool(output.getvalue()), expected_status == 0)

    def test_release_notes_offer_the_exact_immutable_install_version(self) -> None:
        identity = {"release_version": "1.0.5", "main_commit": "a" * 40, "source_commit": "b" * 40}
        body = self.module.release_body(identity, "123")
        self.assertIn("curl -fsSL https://raw.githubusercontent.com/snaplyze/arch-linux/1.0.5/install.sh | bash", body)
        self.assertIn("https://github.com/snaplyze/arch-linux/blob/1.0.5/README.md", body)
        self.assertIn("Actions-run-id: 123", body)
        self.assertNotIn("/latest/", body)
        identity["release_version"] = "main"
        with self.assertRaises(ValueError):
            self.module.release_body(identity, "123")

    def test_draft_rechecks_main_after_asset_verification_before_tag_mutation(self) -> None:
        calls = []
        identity = {"release_version": "1.0.2", "main_commit": "a" * 40, "source_commit": "b" * 40}
        def check_main(identity):
            calls.append("main")
            if "assets" in calls:
                raise ValueError("main advanced during verification")
        with patch.object(self.module, "require_immutability_policy"), \
                patch.object(self.module, "require_latest_main", side_effect=check_main), \
                patch.object(self.module, "verify_assets", side_effect=lambda *args: calls.append("assets")), \
                patch.object(self.module, "command") as command, patch.object(self.module, "api") as api:
            with self.assertRaisesRegex(ValueError, "main advanced during verification"):
                self.module.draft(Path("/unused-test-assets"), identity)
        self.assertEqual(calls, ["main", "assets", "main"])
        command.assert_not_called()
        api.assert_not_called()

    def test_publish_rechecks_main_after_pages_readback_before_api_mutation(self) -> None:
        calls = []
        identity = {"release_version": "1.0.2", "main_commit": "a" * 40}
        current = self.release()
        def api(path, method="GET", payload=None, public=False):
            calls.append(method)
            if method == "PATCH":
                return dict(current, draft=False, immutable=True)
            return current
        def pages(*args):
            calls.append("pages-verified")
        def check_main():
            if "pages-verified" in calls:
                raise ValueError("main advanced during verification")
        with patch.object(self.module, "require_immutability_policy"), \
                patch.object(self.module, "require_latest_main", side_effect=lambda identity: check_main()), \
                patch.object(self.module, "api", side_effect=api), \
                patch.object(self.module, "readback"), patch.object(self.module, "pages_readback", side_effect=pages):
            with self.assertRaisesRegex(ValueError, "main advanced during verification"):
                self.module.publish(7, identity, Path("/unused-test-output"))
        self.assertEqual(calls, ["GET", "pages-verified"])

    def test_publish_verifies_before_mutation_and_published_retry_is_read_only(self) -> None:
        for published in (False, True):
            with self.subTest(published=published):
                calls = []
                identity = {"release_version": "1.0.2", "main_commit": "a" * 40}
                current = self.release()
                if published:
                    current.update(draft=False, immutable=True)
                def api(path, method="GET", payload=None, public=False):
                    calls.append(method)
                    return dict(current, draft=False, immutable=True) if method == "PATCH" else current
                with patch.object(self.module, "require_immutability_policy"), \
                        patch.object(self.module, "require_latest_main", side_effect=lambda identity: calls.append("main")), \
                        patch.object(self.module, "api", side_effect=api), \
                        patch.object(self.module, "readback", side_effect=lambda *args, **kwargs: calls.append("assets")) as readback, \
                        patch.object(self.module, "pages_readback", side_effect=lambda *args: calls.append("pages")):
                    self.module.publish(7, identity, Path("/unused-test-output"))
                self.assertEqual(calls, ["main", "GET", "assets", "pages", "main"] + ([] if published else ["PATCH"]))
                self.assertEqual(readback.call_args.kwargs, {"public": published})


if __name__ == "__main__":
    unittest.main()
