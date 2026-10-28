"""Check a release bundle against what Google Play and this project require of it.

    python3 -m tools.release.check_aab build/chess-roguelike-0.1.0-1.aab --bundletool build/tools/bundletool.jar

It prints one PASS or FAIL line per condition and exits with 1 when any of them fails. The conditions:

* bundletool's `dump config` asks for 16 KB page alignment (PAGE_ALIGNMENT_16K);
* the Stockfish library for the release template is in the bundle;
* every arm64-v8a library has only LOAD segments aligned to 2**14, read with the NDK's llvm-objdump;
* the manifest carries the Play application id and the preset's versionCode, targets SDK 36 and declares
  no permission.

The application id and the versionCode come from the "Android Play" preset, so a version bump in
game/export_presets.cfg is all the check needs. bundletool and llvm-objdump run through the small Tools
class, which the tests replace.
"""

import argparse
import glob
import os
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile
from dataclasses import dataclass
from pathlib import Path

from . import preset

REQUIRED_LIB = "libstockfish_gd.android.template_release.arm64.so"
LIB_DIR = "base/lib/arm64-v8a/"
TARGET_SDK = "36"
MIN_ALIGN_EXPONENT = 14  # 2**14 bytes is 16 KB
ANDROID_NS = "{http://schemas.android.com/apk/res/android}"
PRESET_FILE = Path(__file__).resolve().parents[2] / "game" / "export_presets.cfg"
PRESET_NAME = "Android Play"


@dataclass(frozen=True)
class Expected:
    application_id: str
    version_code: str


@dataclass(frozen=True)
class Result:
    name: str
    passed: bool
    detail: str = ""

    def line(self) -> str:
        if self.passed:
            return f"PASS {self.name}"
        return f"FAIL {self.name}" + (f": {self.detail}" if self.detail else "")


class ToolError(Exception):
    """A tool the check calls failed to run, or printed something it cannot read."""


class Tools:
    """The real bundletool and llvm-objdump."""

    def __init__(self, bundletool: str, java: str, objdump: str):
        self.bundletool = bundletool
        self.java = java
        self.objdump = objdump

    def _run(self, command: list[str]) -> str:
        try:
            completed = subprocess.run(command, capture_output=True, text=True, check=True)
        except (OSError, subprocess.CalledProcessError) as error:
            detail = getattr(error, "stderr", "") or str(error)
            raise ToolError(f"{Path(command[0]).name} failed: {detail.strip()[:300]}") from error
        return completed.stdout

    def _bundletool(self, *args: str) -> str:
        return self._run([self.java, "-jar", self.bundletool, *args])

    def dump_config(self, aab: Path) -> str:
        return self._bundletool("dump", "config", f"--bundle={aab}")

    def dump_manifest(self, aab: Path) -> str:
        return self._bundletool("dump", "manifest", f"--bundle={aab}")

    def load_alignments(self, so_path: Path) -> list[int]:
        return parse_load_alignments(self._run([self.objdump, "-p", str(so_path)]))


def parse_load_alignments(objdump_output: str) -> list[int]:
    """The exponents of the LOAD segments' alignment in `llvm-objdump -p` output ("align 2**14" gives 14)."""
    return [int(match.group(1)) for match in re.finditer(r"^\s*LOAD\b.*\balign 2\*\*(\d+)", objdump_output, re.M)]


def check_config(config: str) -> Result:
    name = "bundle config asks for 16 KB page alignment"
    return Result(name, "PAGE_ALIGNMENT_16K" in config, "PAGE_ALIGNMENT_16K is not in `bundletool dump config`")


def check_manifest(manifest_text: str, expected: Expected) -> list[Result]:
    names = [
        f"manifest application id is {expected.application_id}",
        f"manifest versionCode is {expected.version_code}",
        f"manifest targetSdkVersion is {TARGET_SDK}",
        "manifest declares no permission",
    ]
    start = manifest_text.find("<manifest")
    try:
        if start < 0:
            raise ET.ParseError("no <manifest> element")
        root = ET.fromstring(manifest_text[start:])
    except ET.ParseError as error:
        return [Result(name, False, f"the manifest cannot be read ({error})") for name in names]
    uses_sdk = root.find("uses-sdk")
    target = uses_sdk.get(f"{ANDROID_NS}targetSdkVersion") if uses_sdk is not None else None
    permissions = [child.get(f"{ANDROID_NS}name", "?") for child in root if child.tag.startswith("uses-permission")]
    package = root.get("package")
    code = root.get(f"{ANDROID_NS}versionCode")
    return [
        Result(names[0], package == expected.application_id, f"found {package}"),
        Result(names[1], code == expected.version_code, f"found {code}"),
        Result(names[2], target == TARGET_SDK, f"found {target}"),
        Result(names[3], not permissions, "found " + ", ".join(permissions)),
    ]


def check_libraries(aab: Path, tools) -> list[Result]:
    """The required library is there, and every arm64-v8a library has 16 KB aligned LOAD segments."""
    with zipfile.ZipFile(aab) as bundle:
        members = [
            info for info in bundle.infolist() if info.filename.startswith(LIB_DIR) and info.filename.endswith(".so")
        ]
        results = [
            Result(
                f"{REQUIRED_LIB} is in the bundle",
                any(info.filename == LIB_DIR + REQUIRED_LIB for info in members),
                f"not found under {LIB_DIR}",
            )
        ]
        if not members:
            return results + [Result("the bundle has arm64-v8a libraries", False, f"nothing under {LIB_DIR}")]
        with tempfile.TemporaryDirectory(prefix="check-aab-") as directory:
            for info in members:
                library = Path(info.filename).name
                target = Path(directory) / library
                target.write_bytes(bundle.read(info))
                name = f"{library} has 16 KB LOAD segments"
                try:
                    exponents = tools.load_alignments(target)
                except ToolError as error:
                    results.append(Result(name, False, str(error)))
                    continue
                too_small = sorted({2**e for e in exponents if e < MIN_ALIGN_EXPONENT})
                if not exponents:
                    results.append(Result(name, False, "llvm-objdump shows no LOAD segment"))
                else:
                    results.append(Result(name, not too_small, f"LOAD segments aligned to {too_small} bytes"))
    return results


def check_bundle(aab: Path, expected: Expected, tools) -> list[Result]:
    results: list[Result] = []
    try:
        results.append(check_config(tools.dump_config(aab)))
    except ToolError as error:
        results.append(Result("bundle config asks for 16 KB page alignment", False, str(error)))
    results += check_libraries(aab, tools)
    try:
        results += check_manifest(tools.dump_manifest(aab), expected)
    except ToolError as error:
        results.append(Result("manifest can be dumped", False, str(error)))
    return results


def run(aab: Path, expected: Expected, tools) -> int:
    """Print one line per check, and return the exit code: 0 when every check passed."""
    try:
        results = check_bundle(aab, expected, tools)
    except (OSError, zipfile.BadZipFile) as error:
        results = [Result("the bundle is a readable zip file", False, str(error))]
    for result in results:
        print(result.line())
    return 0 if all(result.passed for result in results) else 1


def find_objdump() -> str:
    """The newest NDK's llvm-objdump under ANDROID_HOME."""
    home = os.environ.get("ANDROID_HOME", str(Path.home() / "Library" / "Android" / "sdk"))
    found = glob.glob(f"{home}/ndk/*/toolchains/llvm/prebuilt/*/bin/llvm-objdump")

    def version(path: str) -> tuple[int, ...]:
        ndk = path.split("/ndk/")[1].split("/")[0]
        return tuple(int(part) if part.isdigit() else 0 for part in ndk.split("."))

    if not found:
        raise SystemExit(f"no NDK with llvm-objdump under {home}/ndk: install one with sdkmanager")
    return max(found, key=version)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("aab", type=Path)
    parser.add_argument("--bundletool", required=True, help="path of bundletool-all.jar")
    parser.add_argument("--java", default=os.path.join(os.environ.get("JAVA_HOME", ""), "bin", "java"))
    parser.add_argument("--objdump", help="llvm-objdump; the newest NDK under ANDROID_HOME by default")
    parser.add_argument("--presets", type=Path, default=PRESET_FILE)
    arguments = parser.parse_args(argv)
    for label, path in (("the bundle", arguments.aab), ("bundletool", Path(arguments.bundletool))):
        if not path.is_file():
            raise SystemExit(f"{label} {path} does not exist")
    options = preset.read_options(arguments.presets.read_text(encoding="utf-8"), PRESET_NAME)
    expected = Expected(options["package/unique_name"], options["version/code"])
    tools = Tools(arguments.bundletool, arguments.java, arguments.objdump or find_objdump())
    return run(arguments.aab, expected, tools)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
