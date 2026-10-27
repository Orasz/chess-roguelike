# 0002 — Vertical slice: one zone, played on the phone

- **Date:** 2026-10-27
- **Status:** accepted
- **Context:**
  - Spec §14, step 2
  - Plan [`docs/superpowers/plans/2026-10-27-vertical-slice.md`](../superpowers/plans/2026-10-27-vertical-slice.md)
  - Decision [0001 — Engine integration](0001-engine-integration.md)

## Context

Decision 0001 proved that Stockfish runs inside the game on a real arm64 phone. The next step in
spec §14 is a vertical slice: one zone with placeholder art, a few Lichess puzzles, one theory
encounter, one strong enemy with HP as advantage, run HP, one item, and save/resume. The slice had
to show that these pieces make a game on the phone, and it had to give the open-beta plan
measurements and tuning notes from real play.

## What was built

The work is in Tasks 1–16 of the plan. Task 17 built the APK and ran the device check.

- **The zone.** Five hand-made chunks, written as ASCII rows in JSON. A run stacks the start
  chunk, two of the three middle chunks in a seeded order, and the gate chunk. The player walks
  where the screen is tapped, and the camera follows him.
- **Puzzles.** Lichess one-move puzzles from the Italian Game: 240 puzzles and 80 strong
  positions, in an 83 KB subset. A wrong answer costs HP and is explained: the arrow, the theme,
  and one sentence built from Stockfish's reply.
- **Theory.** The Italian Game encounter. The enemy answers with book moves, and a move that
  leaves the book is taken back and explained with hand-written text.
- **The strong enemy.** A Lichess `advantage` position that the player must convert within 12
  moves. HP is the advantage: each move costs the win chance it throws away, and the enemy's bar
  empties as the advantage grows.
- **The run.** Run HP, the potion, and an atomic save. The app resumes where it was left, in the
  middle of a battle too.
- **Chess rules.** Legal moves come from Stockfish's own move generator, through the bridge.
  There is no move generator in GDScript.

During the build, some decisions changed how the slice behaves compared with the plan text:

- The board shows the player's own move at once, before the engine answers.
- The arrow after a mistake stays through the enemy's reply, until the player moves again.
- Engine waits count foreground time only. Going to the background never turns a pending search
  into a draw.
- The board is a whole multiple of the 16 px art: 640 px on a screen 720 px wide.
- A save that cannot be loaded leaves only "New run". That covers a corrupt file, another
  version's file, and a run that is already over.

## Measurements

**Device:** the same Nothing Phone (3) as in 0001.
- Model A024, Android 17 (SDK 37), Snapdragon SM8735, `arm64-v8a`.
- The screen is 1260×2800 (9:20). The game sees it as 720×1600.

**Build:**
- Debug APK `build/slice.apk`: **128.0 MB** (127,967,184 bytes).
- Package `io.github.chessroguelike.slice`, named `Chess Roguelike Slice`. The full net is still
  embedded, as in 0001.

**How the checks were run:** as in 0001, from the Mac with `adb`. The game was driven with
`input tap`, `swipe` and `keyevent`, and screenshots came from `screencap`. The save was read with
`run-as`, and logcat ran for the whole session. Two Club runs (rating 1200) were played.

| # | Check | Result |
|---|---|---|
| 1 | Cold start | ✅ The first frame appears 331 ms after launch (257 ms on relaunch). The engine is ready 2.0 s after launch (1.3 s on relaunch), before any battle can open |
| 2 | Screen shape | ✅ No black bars on the 9:20 screen, in the overworld or in battle |
| 3 | New Club run, tap to move | ✅ The player walks to the tile tapped, and the camera follows him |
| 4 | Puzzle, right and wrong | ✅ A wrong answer costs 10 HP and shows the arrow, the theme and the sentence. The right answer wins |
| 5 | Theory encounter | ✅ Leaving the book costs 5 HP once per position and is explained. Finishing the line wins |
| 6 | Strong enemy | ✅ Both bars move, and a bad move costs HP (26 HP for one). Both battles resolved, by escape |
| 7 | Potion | ✅ It heals from the HUD and in battle |
| 8 | Swipe away from Recents mid-battle, then relaunch | ✅ ActivityManager killed the app with `remove task`. After Continue, the screen was identical to the one before the swipe, with the same position and HP |
| 9 | Home during the enemy's search, wait 10 s, return | ✅ The same process survived, and the enemy's move was applied. The move was charged once (17 HP) |
| 10 | logcat and `dumpsys meminfo` | ✅ No `FATAL` and no crash signal. The only `SIG 9` lines come from the two kills made on purpose (Back and the Recents swipe) |

The earlier reviews asked for a few more checks:

| # | Check | Result |
|---|---|---|
| E1 | Safe area | ⚠️ The status bar is hidden. The camera hole is inside the enemy plate, and it covers the top of "re" in the longest name, "Knight of the Centre" |
| E2 | The dialogue scrolls with a finger | Not testable here. The longest text fits the 9:20 dialogue box. A drag inside it moves nothing on the board |
| E3 | A tap walks to the tile tapped | ✅ Three taps, three exact tiles |
| E4 | A tap on the HUD plate does not walk | ✅ |
| E5 | Home and Back save | ✅ Back quits the app, cleanly. The relaunch shows Continue, which resumes the battle as it was |
| E6 | The hint arrow after the enemy's reply | Recorded for the author: see the Consequences |
| E7 | One tap selects, the second moves | ✅ |

**Memory after a battle** (`dumpsys meminfo`): TOTAL PSS **460,565 KB** (about 450 MiB), native
heap 222,516 KB. 0001 measured 451 MB and 214 MB after the spike's session. The slice's screens,
art and run state add little: the net still dominates.

## Decision

**The slice is complete and runs on the phone.** Every check of the brief passes, and a run plays
from the menu to the exit. Save and resume survive Home, Back and a swipe from Recents, in the
middle of a battle too. Its architecture is kept for the open beta:
- the `ChessEngine` autoload, the one engine of the process, behind `UciEngine`;
- encounters as pure logic, rendered by the battle screen;
- the run as data in one atomic save.

## Consequences

These are inputs to the open-beta plan.

- **The net strategy spike comes first.** The slice did not change the numbers of 0001: the APK
  is 128 MB, and the app uses about 450 MiB in total. The options are still the light net and
  `EvalFile` from `user://`, as 0001 describes.
- **Tuning, from playing two runs:**
  - **The strong enemy cannot be beaten in 12 moves, even with perfect play.** One run followed
    the game's own hint at every move and won the queen on move 2. It still ended at +786 against
    the +800 needed, and the enemy escaped. Stockfish's normalised centipawns put a queen-up
    middlegame near +500. Retune `DECISIVE_CP` or `STRONG_MOVE_LIMIT`, or use a win-chance
    threshold.
  - **Strong battles are expensive.** One battle cost about 58 HP: two mistakes (26 and 17 HP),
    then the escape (15 HP).
  - **Every Club puzzle is a mate in one.** All 46 puzzles within reach of a 1200 rating are mate
    in one, and puzzles repeat across runs.
  - **The hint can cost HP.** Following the hint once cost 2 HP, because the evaluation moved
    between two searches. A wider dead zone would absorb that noise.
  - **The explanation can name a reply the enemy does not play.** It reads "the best reply is
    Be6", while the enemy picks another move.
  - **The enemy bar can jump at the first move.** It starts at 1.0 even when `cp_start` is above
    600. There the bar's own formula gives less (0.5 at +700), so a neutral first move would halve
    it. This was found by reading the code; the device runs did not show it.
  - **The theory dialogue goes stale.** It keeps the last "leaves the book" text to the end of the
    line, and the win shows no text of its own.
  - **A resumed battle shows nothing in the dialogue.** Its last explanation and arrow are gone.
  - **The mistake arrow reads as advice.** After the enemy's reply, it can look like "play this
    now" rather than "you should have played this". The author will judge it.
  - **Potions went unused.** Both runs ended with potions left.
  - **A zone takes about 3 minutes of adb play, mandatory encounters only.** The run that tried
    every encounter and check took 16 minutes. A human will take longer over the puzzles and the
    strong enemy's moves.
- **The final application id is a beta decision.** The slice uses
  `io.github.chessroguelike.slice`.
- **What did not fully pass:**
  - **E1.** The camera hole covers the top of "re" in "Knight of the Centre". A wider top margin,
    or the display's safe area, would clear it.
  - **E2.** Scrolling could not be tested on a 9:20 screen. It needs a 9:16 phone.
  - **The icon.** The project has no icon, so the APK shows Godot's default launcher icon.
