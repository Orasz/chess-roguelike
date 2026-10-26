class_name EngineEval
extends RefCounted
## One engine evaluation, parsed from a UCI `info ... score ...` line.
## Scores are from the side to move's point of view, as UCI reports them.

var depth: int = 0
var multipv: int = 1
## True when `value` counts moves to mate rather than centipawns.
var is_mate: bool = false
## Centipawns, or moves to mate when `is_mate` (negative: the side to move gets mated).
var value: int = 0
var nodes: int = 0
var nps: int = 0
var time_ms: int = 0
var pv: PackedStringArray = PackedStringArray()
