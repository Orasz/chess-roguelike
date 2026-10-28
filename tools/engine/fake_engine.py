"""A scripted stand-in for a UCI engine, for the tests of the engine tools.

`write_fake_engine` writes an executable Python script that speaks just enough UCI: it
answers `uci`, `isready`, `position`, `go` and `bench` with canned lines, and appends every
command it receives to a log file so a test can check what was sent.
"""

import json
import os
import stat
import sys

TEMPLATE = '''#!{python}
import json
import sys

CONFIG = json.loads({config!r})
position = ""

with open(CONFIG["log"], "a") as log:
    for line in sys.stdin:
        line = line.strip()
        log.write(line + "\\n")
        log.flush()
        if line == "uci":
            print("id name Fake")
            print("uciok")
        elif line == "isready":
            print("readyok")
        elif line.startswith("position fen "):
            position = line[len("position fen "):].split(" moves ")[0]
        elif line.startswith("go"):
            for out in CONFIG["replies"].get(position, CONFIG["default"]):
                print(out)
        elif line == "bench":
            print("Nodes searched  : " + str(CONFIG["nodes"]), file=sys.stderr)
            print("Nodes/second    : 1000", file=sys.stderr)
        elif line == "quit":
            break
        sys.stdout.flush()
'''


def reply(cp=None, mate=None, best="e2e4"):
    """The lines of one search: a score (`cp` or `mate`, from the side to move) and a best move."""
    score = "score mate {}".format(mate) if mate is not None else "score cp {}".format(cp)
    return ["info depth 10 {} pv {}".format(score, best), "bestmove {}".format(best)]


def write_fake_engine(directory, name="engine", default=None, replies=None, nodes=1000):
    """Writes an engine script into `directory` and returns (path, path of its command log).

    `default` is the reply to a `go` for a position not in `replies`, which maps the FEN of a
    `position` command to its reply lines. `nodes` is the total that `bench` reports.
    """
    path = os.path.join(directory, name)
    log = path + ".log"
    config = {
        "log": log,
        "default": default or reply(cp=0),
        "replies": replies or {},
        "nodes": nodes,
    }
    with open(path, "w") as f:
        f.write(TEMPLATE.format(python=sys.executable, config=json.dumps(config)))
    os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)
    return path, log
