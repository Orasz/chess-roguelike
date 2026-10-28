"""Read one option of an export preset out of game/export_presets.cfg.

The Makefile uses it to name the bundle after the preset's version, and check_aab.py to know what the
bundle must contain, so the version and the application id are written in one place only.

    python3 -m tools.release.preset game/export_presets.cfg "Android Play" version/code
"""

import configparser
import re
import sys


def read_options(cfg_text: str, preset_name: str) -> dict[str, str]:
    """Return the options of the preset called preset_name, with the quotes of string values removed."""
    parser = configparser.ConfigParser(interpolation=None, delimiters=("=",), comment_prefixes=(";",))
    parser.optionxform = str  # keep the case of the keys
    parser.read_string(cfg_text)
    for section in parser.sections():
        if not re.fullmatch(r"preset\.\d+", section):
            continue
        if parser[section].get("name", "").strip('"') == preset_name:
            options = f"{section}.options"
            if not parser.has_section(options):
                return {}
            return {key: value.strip().strip('"') for key, value in parser[options].items()}
    raise KeyError(f'no export preset named "{preset_name}"')


def main(argv: list[str]) -> int:
    if len(argv) != 4:
        print("usage: preset.py <export_presets.cfg> <preset name> <option key>", file=sys.stderr)
        return 2
    path, name, key = argv[1:]
    with open(path, encoding="utf-8") as handle:
        try:
            options = read_options(handle.read(), name)
        except KeyError as error:
            print(error.args[0], file=sys.stderr)
            return 1
    if key not in options:
        print(f'preset "{name}" has no option {key}', file=sys.stderr)
        return 1
    print(options[key])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
