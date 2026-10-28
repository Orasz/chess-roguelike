import contextlib
import io
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock

from . import check_aab

GOOD_ALIGN = [14, 14, 14, 14]
SO = check_aab.REQUIRED_LIB
EXPECTED = check_aab.Expected(application_id="io.example.play", version_code="3")

# The output of `bundletool dump config` on our own bundle (bundletool 1.16.0), the compression globs cut short.
REAL_CONFIG = """{
  "bundletool": {
    "version": "1.16.0"
  },
  "optimizations": {
    "splitsConfig": {
    },
    "uncompressNativeLibraries": {
      "enabled": true,
      "alignment": "PAGE_ALIGNMENT_16K"
    },
    "storeArchive": {
      "enabled": true
    }
  },
  "compression": {
    "uncompressedGlob": ["**.3[gG]2", "**.3[gG][pP]", "**.[aA][aA][cC]"]
  }
}
"""
CONFIG_16K = REAL_CONFIG
CONFIG_4K = REAL_CONFIG.replace("PAGE_ALIGNMENT_16K", "PAGE_ALIGNMENT_4K")
CONFIG_COMPRESSED = REAL_CONFIG.replace('"enabled": true,\n      "alignment"', '"enabled": false,\n      "alignment"')
LIBS_COMPRESSED_NAME = "bundle config uncompresses native libraries"
ALIGNMENT_NAME = "bundle config asks for 16 KB page alignment"


def manifest(package="io.example.play", code="3", target="36", extra="", minimum="24", application='android:allowBackup="false"'):
    return f"""<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    android:versionCode="{code}" android:versionName="0.1.0" package="{package}">
  <uses-sdk android:minSdkVersion="{minimum}" android:targetSdkVersion="{target}" />
  <uses-feature android:glEsVersion="0x00030000" android:required="true" />
  {extra}
  <application {application} />
</manifest>"""


def make_aab(directory, libs=(SO, "libc++_shared.so"), other_abis=()):
    """A zip shaped like a bundle: arm64-v8a libraries, plus the "abi/name" libraries of `other_abis`."""
    path = Path(directory) / "fake.aab"
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as bundle:
        bundle.writestr("BundleConfig.pb", b"")
        bundle.writestr("base/manifest/AndroidManifest.xml", b"")
        for lib in libs:
            bundle.writestr(f"base/lib/arm64-v8a/{lib}", b"not an elf")
        for abi_lib in other_abis:
            bundle.writestr(f"base/lib/{abi_lib}", b"not an elf")
    return path


class FakeTools:
    """Stands in for bundletool and llvm-objdump: it answers with canned text and canned alignments."""

    def __init__(self, config=CONFIG_16K, manifest_xml=None, alignments=None, raises=()):
        self.config = config
        self.raises = raises
        self.manifest_xml = manifest_xml if manifest_xml is not None else manifest()
        self.alignments = alignments or {}
        self.inspected = []

    def _maybe_raise(self, what):
        if what in self.raises:
            raise check_aab.ToolError(f"{what} blew up")

    def dump_config(self, aab):
        self._maybe_raise("dump_config")
        return self.config

    def dump_manifest(self, aab):
        self._maybe_raise("dump_manifest")
        return self.manifest_xml

    def load_alignments(self, so_path):
        self._maybe_raise("load_alignments")
        self.inspected.append(Path(so_path).name)
        return self.alignments.get(Path(so_path).name, GOOD_ALIGN)


def verdicts(results):
    return {result.name: result.passed for result in results}


class CheckBundleTest(unittest.TestCase):
    def run_checks(self, tools, libs=(SO, "libc++_shared.so"), other_abis=()):
        with tempfile.TemporaryDirectory() as directory:
            aab = make_aab(directory, libs, other_abis)
            return check_aab.check_bundle(aab, EXPECTED, tools)

    def test_a_good_bundle_passes_every_check(self):
        tools = FakeTools()
        results = self.run_checks(tools)
        self.assertTrue(all(result.passed for result in results), [r.line() for r in results])
        self.assertEqual(sorted(tools.inspected), sorted([SO, "libc++_shared.so"]))

    def test_a_4k_page_alignment_in_the_config_fails_only_the_alignment_line(self):
        verdict = verdicts(self.run_checks(FakeTools(config=CONFIG_4K)))
        self.assertFalse(verdict[ALIGNMENT_NAME])
        self.assertTrue(verdict[LIBS_COMPRESSED_NAME])

    def test_a_config_that_keeps_native_libraries_compressed_fails_only_that_line(self):
        verdict = verdicts(self.run_checks(FakeTools(config=CONFIG_COMPRESSED)))
        self.assertFalse(verdict[LIBS_COMPRESSED_NAME])
        self.assertTrue(verdict[ALIGNMENT_NAME])

    def test_the_alignment_must_be_in_the_uncompress_block_not_just_anywhere_in_the_text(self):
        misplaced = '{"optimizations": {"uncompressNativeLibraries": {"enabled": true}}, "note": "PAGE_ALIGNMENT_16K"}'
        verdict = verdicts(self.run_checks(FakeTools(config=misplaced)))
        self.assertFalse(verdict[ALIGNMENT_NAME])

    def test_noise_around_the_config_json_is_ignored(self):
        results = self.run_checks(FakeTools(config="INFO: starting\n" + REAL_CONFIG + "\nDone."))
        self.assertTrue(all(result.passed for result in results), [r.line() for r in results])

    def test_a_config_that_is_not_json_fails_both_config_lines(self):
        verdict = verdicts(self.run_checks(FakeTools(config="no json here")))
        self.assertFalse(verdict[ALIGNMENT_NAME])
        self.assertFalse(verdict[LIBS_COMPRESSED_NAME])

    def test_a_config_without_the_uncompress_block_fails_both_config_lines(self):
        verdict = verdicts(self.run_checks(FakeTools(config='{"optimizations": {}}')))
        self.assertFalse(verdict[ALIGNMENT_NAME])
        self.assertFalse(verdict[LIBS_COMPRESSED_NAME])

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

    def test_a_library_of_another_abi_fails_and_is_named(self):
        results = self.run_checks(FakeTools(), other_abis=("armeabi-v7a/libgodot_android.so",))
        failed = [result for result in results if not result.passed]
        self.assertEqual([result.name for result in failed], ["the bundle has no library of another ABI"])
        self.assertIn("armeabi-v7a", failed[0].detail)

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

    def test_the_manifest_must_have_min_sdk_24(self):
        results = self.run_checks(FakeTools(manifest_xml=manifest(minimum="21")))
        self.assertFalse(verdicts(results)["manifest minSdkVersion is 24"])

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

    def test_a_manifest_that_allows_the_backup_fails_and_so_does_one_that_says_nothing(self):
        for application in ('android:allowBackup="true"', ""):
            with self.subTest(application=application):
                results = self.run_checks(FakeTools(manifest_xml=manifest(application=application)))
                self.assertFalse(verdicts(results)['manifest sets android:allowBackup="false"'])

    def test_a_debuggable_manifest_fails_and_an_explicit_false_does_not(self):
        debuggable = manifest(application='android:allowBackup="false" android:debuggable="true"')
        results = self.run_checks(FakeTools(manifest_xml=debuggable))
        self.assertFalse(verdicts(results)["manifest is not debuggable"])
        explicit_false = manifest(application='android:allowBackup="false" android:debuggable="false"')
        self.assertTrue(verdicts(self.run_checks(FakeTools(manifest_xml=explicit_false)))["manifest is not debuggable"])

    def test_a_manifest_without_an_application_element_fails_the_backup_check(self):
        results = self.run_checks(FakeTools(manifest_xml=manifest().replace("<application", "<!--").replace("/>\n</manifest>", "-->\n</manifest>")))
        self.assertFalse(verdicts(results)['manifest sets android:allowBackup="false"'])

    def test_an_unreadable_manifest_fails_every_manifest_check(self):
        results = self.run_checks(FakeTools(manifest_xml="not xml at all"))
        manifest_checks = [result for result in results if result.name.startswith("manifest")]
        self.assertTrue(manifest_checks)
        self.assertTrue(all(not result.passed for result in manifest_checks))

    def test_bundletool_output_after_the_xml_is_ignored_too(self):
        results = self.run_checks(FakeTools(manifest_xml=manifest() + "\nINFO: done <not xml>\n"))
        self.assertTrue(all(result.passed for result in results), [r.line() for r in results])

    def test_a_failing_config_dump_is_one_fail_line_and_the_other_checks_still_run(self):
        results = self.run_checks(FakeTools(raises=("dump_config",)))
        failed = [result.name for result in results if not result.passed]
        self.assertEqual(failed, ["bundle config can be dumped"])

    def test_a_failing_manifest_dump_is_one_fail_line_and_the_other_checks_still_run(self):
        results = self.run_checks(FakeTools(raises=("dump_manifest",)))
        failed = [result.name for result in results if not result.passed]
        self.assertEqual(failed, ["manifest can be dumped"])

    def test_a_failing_objdump_fails_each_library_and_only_those(self):
        results = self.run_checks(FakeTools(raises=("load_alignments",)))
        failed = [result.name for result in results if not result.passed]
        self.assertEqual(sorted(failed), sorted(f"{lib} has 16 KB LOAD segments" for lib in (SO, "libc++_shared.so")))

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

# The manifest `bundletool dump manifest` printed for our own bundle, cut down to the elements that matter.
REAL_MANIFEST = """<manifest xmlns:android="http://schemas.android.com/apk/res/android" android:compileSdkVersion="36" android:versionCode="1" android:versionName="0.1.0" package="io.github.orasz.chessroguelike" platformBuildVersionCode="36">

  <uses-sdk android:minSdkVersion="24" android:targetSdkVersion="36"/>

  <uses-feature android:glEsVersion="0x00030000" android:required="true"/>

  <application android:allowBackup="false" android:extractNativeLibs="false">
    <activity android:name="com.godot.game.GodotApp" android:exported="false">
        </activity>
  </application>
</manifest>
"""


class RealOutputTest(unittest.TestCase):
    def test_the_manifest_bundletool_printed_for_our_bundle_passes(self):
        expected = check_aab.Expected("io.github.orasz.chessroguelike", "1")
        results = check_aab.check_manifest(REAL_MANIFEST, expected)
        self.assertEqual(len(results), 7)
        self.assertTrue(all(result.passed for result in results), [r.line() for r in results])

    def test_the_real_manifest_fails_when_mutated_to_allow_backup_or_to_be_debuggable(self):
        expected = check_aab.Expected("io.github.orasz.chessroguelike", "1")
        mutations = {
            'manifest sets android:allowBackup="false"': REAL_MANIFEST.replace('allowBackup="false"', 'allowBackup="true"'),
            "manifest is not debuggable": REAL_MANIFEST.replace(
                'android:allowBackup="false"', 'android:allowBackup="false" android:debuggable="true"'
            ),
        }
        for failing, text in mutations.items():
            with self.subTest(failing=failing):
                verdict = {r.name: r.passed for r in check_aab.check_manifest(text, expected)}
                self.assertFalse(verdict[failing])
                self.assertEqual([n for n, ok in verdict.items() if not ok], [failing])

    def test_the_config_bundletool_printed_for_our_bundle_passes(self):
        results = check_aab.check_config(REAL_CONFIG)
        self.assertEqual(len(results), 2)
        self.assertTrue(all(result.passed for result in results))


class ToolsRunTest(unittest.TestCase):
    """Tools._run turns a failing subprocess into a ToolError that carries the tool's own message."""

    def tools(self):
        return check_aab.Tools("bundletool.jar", "/jdk/bin/java", "/ndk/llvm-objdump")

    def test_a_nonzero_exit_becomes_a_tool_error_with_the_stderr(self):
        failure = subprocess.CalledProcessError(1, ["java"], output="", stderr="Invalid or corrupt jarfile")
        with mock.patch.object(check_aab.subprocess, "run", side_effect=failure):
            with self.assertRaisesRegex(check_aab.ToolError, "Invalid or corrupt jarfile"):
                self.tools().dump_config(Path("x.aab"))

    def test_a_program_that_cannot_start_becomes_a_tool_error(self):
        with mock.patch.object(check_aab.subprocess, "run", side_effect=FileNotFoundError("no such java")):
            with self.assertRaisesRegex(check_aab.ToolError, "java failed: no such java"):
                self.tools().dump_manifest(Path("x.aab"))

    def test_the_commands_are_the_ones_the_makefile_documents(self):
        done = subprocess.CompletedProcess([], 0, stdout="out")
        with mock.patch.object(check_aab.subprocess, "run", return_value=done) as run:
            self.tools().dump_config(Path("x.aab"))
            self.tools().load_alignments(Path("a.so"))
        self.assertEqual(run.call_args_list[0].args[0], ["/jdk/bin/java", "-jar", "bundletool.jar", "dump", "config", "--bundle=x.aab"])
        self.assertEqual(run.call_args_list[1].args[0], ["/ndk/llvm-objdump", "-p", "a.so"])


class MainFunctionTest(unittest.TestCase):
    PRESETS = (
        '[preset.0]\n\nname="Android Play"\n\n[preset.0.options]\n\n'
        'package/unique_name="io.example.play"\nversion/code=7\nversion/name="2.0.0"\n'
    )

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.aab = make_aab(self.root)
        self.jar = self.root / "bundletool.jar"
        self.jar.write_bytes(b"")
        self.presets = self.root / "export_presets.cfg"
        self.presets.write_text(self.PRESETS, encoding="utf-8")

    def arguments(self, **overrides):
        values = {"aab": str(self.aab), "--bundletool": str(self.jar), "--presets": str(self.presets)}
        values.update(overrides)
        return [values.pop("aab")] + [item for pair in values.items() for item in pair] + ["--objdump", "llvm-objdump"]

    def test_the_expected_id_and_version_come_from_the_play_preset(self):
        with mock.patch.object(check_aab, "run", return_value=0) as run:
            self.assertEqual(check_aab.main(self.arguments()), 0)
        aab, expected, tools = run.call_args.args
        self.assertEqual(aab, self.aab)
        self.assertEqual(expected, check_aab.Expected("io.example.play", "7"))
        self.assertEqual((tools.bundletool, tools.objdump), (str(self.jar), "llvm-objdump"))

    def test_the_exit_code_of_run_is_the_exit_code_of_main(self):
        with mock.patch.object(check_aab, "run", return_value=1):
            self.assertEqual(check_aab.main(self.arguments()), 1)

    def test_a_missing_bundle_stops_with_a_message(self):
        with self.assertRaisesRegex(SystemExit, "does not exist"):
            check_aab.main(self.arguments(aab=str(self.root / "nope.aab")))

    def test_a_missing_bundletool_stops_with_a_message(self):
        with self.assertRaisesRegex(SystemExit, "bundletool .*does not exist"):
            check_aab.main(self.arguments(**{"--bundletool": str(self.root / "nope.jar")}))

    def test_a_missing_bundle_argument_is_an_argparse_error(self):
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as caught:
            check_aab.main([])
        self.assertEqual(caught.exception.code, 2)


if __name__ == "__main__":
    unittest.main()
