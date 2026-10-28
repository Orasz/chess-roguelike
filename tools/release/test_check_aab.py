import contextlib
import io
import tempfile
import unittest
import zipfile
from pathlib import Path

from . import check_aab

GOOD_ALIGN = [14, 14, 14, 14]
SO = check_aab.REQUIRED_LIB
EXPECTED = check_aab.Expected(application_id="io.example.play", version_code="3")

CONFIG_16K = '{"optimizations": {"uncompressNativeLibraries": {"enabled": true, "pageAlignment": "PAGE_ALIGNMENT_16K"}}}'
CONFIG_4K = '{"optimizations": {"uncompressNativeLibraries": {"enabled": true, "pageAlignment": "PAGE_ALIGNMENT_4K"}}}'


def manifest(package="io.example.play", code="3", target="36", extra=""):
    return f"""<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    android:versionCode="{code}" android:versionName="0.1.0" package="{package}">
  <uses-sdk android:minSdkVersion="24" android:targetSdkVersion="{target}" />
  <uses-feature android:glEsVersion="0x00030000" android:required="true" />
  {extra}
  <application android:allowBackup="false" />
</manifest>"""


def make_aab(directory, libs=(SO, "libc++_shared.so"), deflated=()):
    """A zip shaped like a bundle. Its libraries are stored, except the ones named in `deflated`."""
    path = Path(directory) / "fake.aab"
    with zipfile.ZipFile(path, "w") as bundle:
        bundle.writestr("BundleConfig.pb", b"", compress_type=zipfile.ZIP_DEFLATED)
        bundle.writestr("base/manifest/AndroidManifest.xml", b"", compress_type=zipfile.ZIP_DEFLATED)
        for lib in libs:
            method = zipfile.ZIP_DEFLATED if lib in deflated else zipfile.ZIP_STORED
            bundle.writestr(f"base/lib/arm64-v8a/{lib}", b"not an elf" * 100, compress_type=method)
    return path


class FakeTools:
    """Stands in for bundletool and llvm-objdump: it answers with canned text and canned alignments."""

    def __init__(self, config=CONFIG_16K, manifest_xml=None, alignments=None):
        self.config = config
        self.manifest_xml = manifest_xml if manifest_xml is not None else manifest()
        self.alignments = alignments or {}
        self.inspected = []

    def dump_config(self, aab):
        return self.config

    def dump_manifest(self, aab):
        return self.manifest_xml

    def load_alignments(self, so_path):
        self.inspected.append(Path(so_path).name)
        return self.alignments.get(Path(so_path).name, GOOD_ALIGN)


def verdicts(results):
    return {result.name: result.passed for result in results}


class CheckBundleTest(unittest.TestCase):
    def run_checks(self, tools, libs=(SO, "libc++_shared.so"), deflated=()):
        with tempfile.TemporaryDirectory() as directory:
            aab = make_aab(directory, libs, deflated)
            return check_aab.check_bundle(aab, EXPECTED, tools)

    def test_a_good_bundle_passes_every_check(self):
        tools = FakeTools()
        results = self.run_checks(tools)
        self.assertTrue(all(result.passed for result in results), [r.line() for r in results])
        self.assertEqual(sorted(tools.inspected), sorted([SO, "libc++_shared.so"]))

    def test_a_4k_page_alignment_in_the_config_fails(self):
        results = self.run_checks(FakeTools(config=CONFIG_4K))
        self.assertFalse(verdicts(results)["bundle config asks for 16 KB page alignment"])

    def test_a_library_with_a_4k_load_segment_fails_and_names_the_library(self):
        tools = FakeTools(alignments={"libc++_shared.so": [14, 12]})
        results = self.run_checks(tools)
        failed = [result for result in results if not result.passed]
        self.assertEqual(len(failed), 1)
        self.assertIn("libc++_shared.so", failed[0].name)

    def test_a_library_without_load_segments_fails(self):
        tools = FakeTools(alignments={SO: []})
        results = self.run_checks(tools)
        self.assertTrue(any(not result.passed and SO in result.name for result in results))

    def test_a_compressed_library_fails_the_stored_check_and_only_that_one(self):
        results = self.run_checks(FakeTools(), deflated=("libc++_shared.so",))
        failed = [result for result in results if not result.passed]
        self.assertEqual([result.name for result in failed], ["every arm64-v8a library is stored uncompressed"])
        self.assertIn("libc++_shared.so", failed[0].detail)

    def test_stored_libraries_pass_the_stored_check(self):
        self.assertTrue(verdicts(self.run_checks(FakeTools()))["every arm64-v8a library is stored uncompressed"])

    def test_a_missing_stockfish_library_fails(self):
        results = self.run_checks(FakeTools(), libs=("libc++_shared.so",))
        self.assertFalse(verdicts(results)[f"{SO} is in the bundle"])

    def test_a_bundle_with_no_native_libraries_fails_the_alignment_check(self):
        results = self.run_checks(FakeTools(), libs=())
        self.assertFalse(verdicts(results)["the bundle has arm64-v8a libraries"])

    def test_the_manifest_must_name_the_play_id(self):
        results = self.run_checks(FakeTools(manifest_xml=manifest(package="io.example.play.dev")))
        self.assertFalse(verdicts(results)["manifest application id is io.example.play"])

    def test_the_manifest_version_code_must_equal_the_preset(self):
        results = self.run_checks(FakeTools(manifest_xml=manifest(code="2")))
        self.assertFalse(verdicts(results)["manifest versionCode is 3"])

    def test_the_manifest_must_target_sdk_36(self):
        results = self.run_checks(FakeTools(manifest_xml=manifest(target="35")))
        self.assertFalse(verdicts(results)["manifest targetSdkVersion is 36"])

    def test_any_uses_permission_fails_and_a_uses_feature_does_not(self):
        extra = '<uses-permission android:name="android.permission.INTERNET" />'
        results = self.run_checks(FakeTools(manifest_xml=manifest(extra=extra)))
        self.assertFalse(verdicts(results)["manifest declares no permission"])
        self.assertTrue(verdicts(self.run_checks(FakeTools()))["manifest declares no permission"])

    def test_a_sdk_23_permission_variant_counts_too(self):
        extra = '<uses-permission-sdk-23 android:name="android.permission.CAMERA" />'
        results = self.run_checks(FakeTools(manifest_xml=manifest(extra=extra)))
        self.assertFalse(verdicts(results)["manifest declares no permission"])

    def test_an_unreadable_manifest_fails_every_manifest_check(self):
        results = self.run_checks(FakeTools(manifest_xml="not xml at all"))
        manifest_checks = [result for result in results if result.name.startswith("manifest")]
        self.assertTrue(manifest_checks)
        self.assertTrue(all(not result.passed for result in manifest_checks))

    def test_bundletool_output_before_the_xml_is_ignored(self):
        results = self.run_checks(FakeTools(manifest_xml="INFO: noise\n" + manifest()))
        self.assertTrue(all(result.passed for result in results), [r.line() for r in results])


class ParseLoadAlignmentsTest(unittest.TestCase):
    def test_only_the_load_segments_are_read(self):
        output = """
Program Header:
    PHDR off    0x0000000000000040 vaddr 0x0000000000000040 paddr 0x0000000000000040 align 2**3
    LOAD off    0x0000000000000000 vaddr 0x0000000000000000 paddr 0x0000000000000000 align 2**14
    LOAD off    0x0000000000004000 vaddr 0x0000000000004000 paddr 0x0000000000004000 align 2**14
 RELRO off    0x00000000003f0000 vaddr 0x00000000003f0000 paddr 0x00000000003f0000 align 2**0
"""
        self.assertEqual(check_aab.parse_load_alignments(output), [14, 14])

    def test_a_4k_segment_shows_as_12(self):
        output = "    LOAD off    0x0 vaddr 0x0 paddr 0x0 align 2**12\n"
        self.assertEqual(check_aab.parse_load_alignments(output), [12])


class MainTest(unittest.TestCase):
    def run_main(self, tools):
        out = io.StringIO()
        with tempfile.TemporaryDirectory() as directory:
            aab = make_aab(directory)
            with contextlib.redirect_stdout(out):
                code = check_aab.run(aab, EXPECTED, tools)
        return code, out.getvalue().splitlines()

    def test_exit_code_is_zero_and_every_line_says_pass(self):
        code, lines = self.run_main(FakeTools())
        self.assertEqual(code, 0)
        self.assertTrue(lines)
        self.assertTrue(all(line.startswith("PASS ") for line in lines), lines)

    def test_one_failure_makes_the_exit_code_non_zero_and_prints_a_fail_line(self):
        code, lines = self.run_main(FakeTools(config=CONFIG_4K))
        self.assertNotEqual(code, 0)
        self.assertEqual(sum(line.startswith("FAIL ") for line in lines), 1)

    def test_a_file_that_is_not_a_zip_is_one_failure_not_a_traceback(self):
        out = io.StringIO()
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "bad.aab"
            path.write_bytes(b"plain text")
            with contextlib.redirect_stdout(out):
                code = check_aab.run(path, EXPECTED, FakeTools())
        self.assertNotEqual(code, 0)
        self.assertTrue(out.getvalue().startswith("FAIL "))


if __name__ == "__main__":
    unittest.main()
