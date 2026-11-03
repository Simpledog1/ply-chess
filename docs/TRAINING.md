# Puzzle Training (Woodpecker method) — how it works and how to maintain it

Puzzle Training lets a player solve a fixed collection of tactics puzzles
three times (three *cycles*) to make the patterns automatic, then builds the
next collection from the results. This document describes the
implementation as it is, for maintainers.

## Where the code lives

| File | Role |
|---|---|
| `lib/training/puzzle.dart` | `Puzzle` model, Lichess CSV and API parsing, validation, theme names |
| `lib/training/puzzle_catalogue.dart` | Starter pack + downloaded puzzles (`puzzles.json`), imports |
| `lib/training/puzzle_solver.dart` | Solving one puzzle: moves, replies, wrong moves, hints |
| `lib/training/training_store.dart` | Profile, collections, cycles, attempts (`training.json`) |
| `lib/training/training_stats.dart` | Summaries, theme statistics, mastery rule, `TrainingInsightsSource` |
| `lib/training/recommender.dart` | Rating estimate, calibration, weak themes, collections, cycle order |
| `lib/training/training_controller.dart` | Glue for the screens; downloads and CSV import |
| `lib/ui/training/` | Screens: set-up, calibration, planning, dashboard, solving, results, dialogs |
| `assets/puzzles/lichess_starter.csv` | Bundled starter pack (7,938 puzzles) |
| `tool/build_puzzle_pack.js` | Rebuilds the starter pack from the Lichess database |

The chess rules (legality, FEN, SAN, castling, en passant, promotion) come
from `dartchess`, the board is Ply's `ChessBoard`, and moves are compared as
normalized UCI with `standardUci`, the same helpers the game analyser uses.
Stockfish is not used by training: every puzzle comes with a verified
solution.

## Puzzle source and licensing

- **Lichess open puzzle database**, <https://database.lichess.org/#puzzles>,
  released under **CC0** ("Database exports are released under the Creative
  Commons CC0 license"), so it may be stored and redistributed.
- CSV columns: `PuzzleId,FEN,Moves,Rating,RatingDeviation,Popularity,NbPlays,
  Themes,GameUrl,OpeningTags[,DailyDate]`. `FEN` is the position *before*
  the opponent's move; `Moves` are UCI, the first is the opponent's, the
  rest alternate player/opponent. Every player move is the only good move,
  except mate in one where any mate wins.
- The download is `lichess_db_puzzle.csv.zst` (about 310 MB, 6.19 million
  puzzles in the 2026-11-01 export). It is written by `pzstd`: each Zstandard
  frame is preceded by a *skippable frame* holding its size, which some
  decoders (Node's) reject; `tool/build_puzzle_pack.js` strips them.
- **Lichess puzzle API** for in-app downloads:
  `GET https://lichess.org/api/puzzle/batch/{angle}?nb=N` works without an
  account. Each puzzle comes with the game's SAN moves up to the puzzle and
  the player's solution (UCI). Ply replays the game, takes the position
  before the last game move as the FEN and that move as the opponent's first
  move, which gives the database convention.

## Data model (JSON, not SQL)

Ply stores everything in JSON files in its data folder
(`%APPDATA%\Simpledog1\Ply` on Windows), written to a temporary file and
renamed into place (atomic). An unreadable file is renamed
`*.corrupt-<time>` instead of being overwritten. Training adds two files
next to `settings.json` and `ply_data.json`:

- `puzzles.json` (`PuzzleCatalogue`, schema version 1): downloaded or
  imported puzzles and an import log
  (`{at, source, added, dup, rej}`). The starter pack is read from the app
  bundle, never copied.
- `training.json` (`TrainingStore`, schema version 1):
  - `profile`: rating source and rating, estimated puzzle rating and its
    deviation, preferred collection size, wrong-move behaviour, hints,
    calibration attempts.
  - `collections[]`: id, number, status (`active`/`completed`/`abandoned`),
    target rating, selection metadata, timestamps, a **copy of every
    puzzle** in membership order, and `cycles[]`.
  - `cycles[]`: number (1–3), seed, `order` (puzzle ids), status,
    timestamps, `attempts[]`.
  - `attempts[]`: puzzle id, rating and themes at the time, start/end,
    elapsed ms, solved, first-try correct, wrong moves, hint level, skipped,
    the moves tried.

How this covers the relational design in the specification:

| Spec table | Here |
|---|---|
| `puzzles`, `puzzle_themes` | `Puzzle` in the starter pack / `puzzles.json` (themes as a list) |
| `training_profiles` | `profile` in `training.json` (one local player) |
| `training_collections` + `collection_puzzles` | `collections[]` with their puzzle copies; order = membership order |
| `training_cycles` | `cycles[]`, one per number, checked unique |
| `puzzle_attempts` | `attempts[]`, append-only |
| `theme_statistics` | computed from attempts on demand (`themeStats`), so it can never drift |

Integrity rules, checked whenever a collection is created or loaded
(`TrainingCollection._check`): no duplicate puzzle; cycle numbers 1..3, each
at most once; every cycle order is a permutation of the membership; attempts
follow the cycle order. `TrainingStore` also enforces one active collection,
attempts only for the next puzzle of the active cycle, and new cycles only
with the same membership.

**Migrations:** bump `schemaVersion` and add a step in
`TrainingStore._migrate` (and the catalogue's loader). A file from a newer
Ply is refused and kept aside rather than misread.

## Solving

`PuzzleSolver` plays the opponent's first move, then for each player move:
legal moves only; correct if its normalized UCI equals the expected move or
it gives checkmate; then the opponent's reply is played (after a short
delay in the UI). Wrong moves: **Retry** (default) counts the mistake and
keeps the puzzle open; **Reveal** shows the solution and fails the puzzle.
Hints: 1 = theme, 2 = which piece (badge on the board), 3 = the move
(arrow). Any wrong move or hint removes first-try credit. Skip records an
abandoned attempt; Solution records a failed one. Pausing mid-puzzle records
nothing; that puzzle starts again with a fresh clock.

### Move feedback

Every move gets visible feedback (`TrainingController.play`,
`PuzzleSession.feedback`, `_PuzzleBoard`). The solver's position never
holds a wrong move: the session shows one temporarily through
`shownPosition` / `shownMove`, and `busy` makes the board read-only and
disables Hint, Reset, Solution and Skip while feedback plays, so rapid
input cannot slip through. Clicks and drags reach the same `play`.

| Result | Board | Panel |
|---|---|---|
| Correct | move squares green, ✓ on the target, green frame; the reply follows after `replyDelay` (450 ms) | "Correct! Keep going." |
| Solved | the same green marking | "Puzzle solved!" (or "…(with help)"), then the result card |
| Wrong, Retry | the move stays on the board for `wrongDelay` (900 ms): squares red, ✗ on the target, red frame, a short sideways shake; then the piece goes back | "Incorrect move. Try again." (stays red until the next move) |
| Wrong, Reveal | the wrong move as above, then the solution replayed from the starting point: an arrow before each move, one step every `stepDelay` (700 ms), ending on the final position | "Incorrect move. Here is the solution.", then the numbered solution |
| Solution button | the same replay | the numbered solution |

The shake is skipped when the system asks for reduced animations. Sounds
are optional (Training settings → Sound effects, off by default): a system
alert for wrong moves and a click for a solved puzzle, through
`SystemSound`; on Windows the click may be silent. Nothing depends on sound.
Each new message fades in, so a repeated wrong move still visibly
registers.

## Recommendations (`recommender.dart`, all numbers in `RecommenderConfig`)

These are Ply's own, explainable rules, not a published standard.

1. **Starting estimate** (Lichess puzzle scale): the Lichess rating as is;
   Chess.com and FIDE +250 (a rough pool offset); no rating → 1200. The
   deviation starts at 250 (rating given) or 350 (none).
2. **Calibration**: 12 adaptive puzzles, each the closest rating to the
   current estimate (avoiding the last themes and puzzles with more than
   three moves). Each attempt updates the estimate Elo-style:
   `score` = 1 first try, 0.3 solved with help, 0 otherwise;
   `K = clamp(0.2 × deviation, 16, 70)`; deviation ×0.93 per attempt (min
   60). Confidence: low ≥ 200, medium ≥ 110, high below.
3. **Only first exposures move the estimate**: calibration and cycle 1.
   Cycles 2 and 3 measure memory and speed, not strength.
4. **Weak themes**: from first exposures only; a theme needs at least 8
   attempts and a first-try rate at least 10 points below the player's
   overall rate; at most 3, weakest first. With too little data there are
   none, and the collection is simply diverse.
5. **Difficulty change** after a collection, from its cycle 1 (needs 20+
   attempts): ≥ 80% first-try and median ≤ 45 s → +75; ≥ 80% but slower →
   same; < 55% → −100; otherwise same.
6. **Collection**: centred at `estimate + change − 100` (about 64% expected
   first-try success), ±150 rating, widened by 100 up to ±450 if needed.
   About 30% targeted (split over the weak themes) when any are known, the
   rest general: the natural mix of the range with no main theme above
   ~12% (the main theme is the most telling motif, by a priority list).
   Puzzles from earlier collections are excluded unless the player allows
   reuse. If too few puzzles fit, a `Shortage` explains it and the UI offers
   downloads, reuse or a smaller size; a collection is never silently
   smaller.
7. **Cycle order**: puzzles split into rating thirds, interleaved in a
   seeded random pattern, then neighbours with the same main theme are
   swapped apart. Each cycle has its own seed; the order is saved, so a
   resumed cycle keeps its order.

**Mastery** (`MasteryRules`): a puzzle is *provisionally mastered* when its
last two attempts were first-try solves within 60 s. A rough guide only.

## Statistics

`AttemptSummary`: first-try accuracy (solved with no wrong move or hint ÷
attempted), eventual accuracy (solved ÷ attempted), average and median time
of solved puzzles (skips and failures excluded and reported separately),
wrong moves, hints. `themeStats`: attempts, first-try rate, average time,
distinct puzzles and *repeated success* (puzzles solved first try in two or
more cycles).

`TrainingInsightsSource` (implemented by `TrainingStats`) exposes the
puzzle rating, first-exposure theme results and cycle history for a future
Insights link. Insights itself does not use it yet, and puzzle results are
not presented as evidence of weaknesses in real games.

## Offline and online

Everything needed to train is local: the starter pack ships with Ply, and
downloaded puzzles, collections, cycles and attempts are in the data folder.
Online is only needed to download more puzzles (Training → cloud icon):
pick 100/200/500 and themes; batches of 50 from the API are parsed,
validated (FEN, every move replayed), de-duplicated, and saved in one write
at the end (or with what was fetched when cancelled). Errors (offline,
timeout, HTTP 429, server errors) leave the library unchanged. A
decompressed Lichess CSV can also be imported: it is streamed line by line
and a random sample of up to 20,000 valid puzzles is kept.

## Maintenance

- **Rebuild the starter pack** (needs Node 22.15+ for zstd):
  ```
  curl -O https://database.lichess.org/lichess_db_puzzle.csv.zst
  node tool/build_puzzle_pack.js lichess_db_puzzle.csv.zst assets/puzzles/lichess_starter.csv
  ```
  Then update the export date and SHA-256 in `THIRD_PARTY_NOTICES.md`. The
  selection is deterministic for a given export. `test/puzzle_test.dart`
  checks that every bundled puzzle validates.
- **Tune the rules** in `RecommenderConfig` and `MasteryRules`; the tests in
  `test/training_test.dart` pin the behaviour.
- **Delete data**: Settings → Profiles & privacy → Delete puzzle training
  data (downloaded puzzles stay).

## Tests

- `test/puzzle_test.dart`: CSV/API parsing, validation, the whole starter
  pack, the catalogue (duplicates, restart, corrupt file), the solver
  (multi-move, Retry, Reveal, any mate, castling both ways, en passant,
  promotion, hints, reset).
- `test/training_test.dart`: 50/100/200 collections, mixed themes, the
  70/30 split, different levels, no repeats, shortages, cycle order,
  three cycles with the same membership, resume after restart, ordering and
  membership rules, one active collection, abandoned history, corrupt and
  newer files, statistics, weak-theme minimum sample, difficulty rules,
  calibration, mastery, downloads (fixture of a real API answer, duplicates,
  rate limit), CSV sampling.
- `test/training_ui_test.dart`: set-up, skipping calibration, planning a
  50-puzzle collection, solving a real puzzle by tapping the board, pausing
  and resuming at the same puzzle.
