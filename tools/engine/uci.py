"""A minimal UCI driver, for the offline tools.

It starts a UCI engine binary (a desktop Stockfish build) and searches positions with it.
Every command is written from a fixed template: the FEN and the moves are checked against
the characters they may hold, so no text reaches the engine that is not a position or a move.
The game itself never uses this module, it goes through `UciEngine`.
"""

import re
import subprocess
from typing import NamedTuple, Optional

_FEN = re.compile(r"[pnbrqkPNBRQK1-8/]+ [wb] (?:[KQkq]+|-) (?:[a-h][36]|-)(?: \d+ \d+)?")
_MOVE = re.compile(r"[a-h][1-8][a-h][1-8][qrbn]?")
_NODES = re.compile(r"Nodes searched\s*:\s*(\d+)")


class Result(NamedTuple):
    """The outcome of a search. `cp` and `mate` are from the side to move; one of them is None."""

    best: str
    cp: Optional[int]
    mate: Optional[int]


class Engine:
    """One engine process. Close it when done: it is also a context manager."""

    def __init__(self, path: str):
        # Stockfish prints the `bench` summary on stderr, so both streams are read as one.
        self._process = subprocess.Popen(
            [path],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        self._send("uci")
        self._read_until(lambda line: line == "uciok")
        self._send("setoption name Threads value 1")
        self._send("setoption name Hash value 16")
        self._send("isready")
        self._read_until(lambda line: line == "readyok")

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()

    def search(
        self,
        fen: str,
        moves: list[str],
        movetime_ms: Optional[int] = None,
        depth: Optional[int] = None,
    ) -> Result:
        """Searches `fen` after `moves` (long algebraic) for `movetime_ms` or to `depth`."""
        if (movetime_ms is None) == (depth is None):
            raise ValueError("give exactly one of movetime_ms and depth")
        if not _FEN.fullmatch(fen):
            raise ValueError("not a FEN: {!r}".format(fen))
        for move in moves:
            if not _MOVE.fullmatch(move):
                raise ValueError("not a move: {!r}".format(move))
        command = "position fen " + fen
        if moves:
            command += " moves " + " ".join(moves)
        self._send(command)
        if movetime_ms is not None:
            self._send("go movetime {}".format(int(movetime_ms)))
        else:
            self._send("go depth {}".format(int(depth)))

        cp: Optional[int] = None
        mate: Optional[int] = None
        best = ""
        while True:
            line = self._readline()
            tokens = line.split()
            if tokens[:1] == ["bestmove"]:
                best = tokens[1]
                break
            if tokens[:1] != ["info"] or "score" not in tokens or "pv" not in tokens:
                continue
            if "lowerbound" in tokens or "upperbound" in tokens:
                continue
            kind, value = tokens[tokens.index("score") + 1 : tokens.index("score") + 3]
            cp, mate = (int(value), None) if kind == "cp" else (None, int(value))
        return Result(best, cp, mate)

    def bench_nodes(self) -> int:
        """Runs the engine's `bench` and returns the total number of nodes it searched."""
        self._send("bench")
        while True:
            found = _NODES.search(self._readline())
            if found:
                break
        # The summary goes on for a line or two: wait for the engine to be idle again.
        self._send("isready")
        self._read_until(lambda line: line == "readyok")
        return int(found.group(1))

    def close(self):
        if self._process.poll() is None:
            try:
                self._send("quit")
            except OSError:
                pass
            try:
                self._process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self._process.kill()
                self._process.wait()
        for stream in (self._process.stdin, self._process.stdout):
            if stream:
                stream.close()

    def _send(self, command: str):
        self._process.stdin.write(command + "\n")
        self._process.stdin.flush()

    def _readline(self) -> str:
        line = self._process.stdout.readline()
        if not line:
            raise EOFError("the engine closed its output")
        return line.strip()

    def _read_until(self, done):
        while not done(self._readline()):
            pass
