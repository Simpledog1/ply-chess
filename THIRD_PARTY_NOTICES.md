# Third-party notices

Ply's own source code is released under the MIT License (see `LICENSE`).
Ply also bundles or links the third-party components below. Several are
licensed under the GNU GPL, so **the distributed Android app (APK) as a whole
is covered by the GNU GPL version 3**. Its complete source is this repository
plus the upstream sources referenced below.

The in-app "Licenses and credits" page (Settings → About) shows the full
license text of every bundled component.

## Stockfish 19 — chess engine

- Version: Stockfish 19, release tag `sf_19`, commit
  `edb0d9db6731067ec50ce619ff372b463bc4dd5d`
- Binaries, from <https://github.com/official-stockfish/Stockfish/releases/tag/sf_19>:
  - Windows: `stockfish-windows-x86-64-universal.exe`
    (archive SHA-256 `3c8bf1f9ea66a09350a40df4f632288285ac206d99f33ab5842c408fc30b48a7`,
    binary SHA-256 `45bc8e4969147db9c2eb533810637994619bff0eacc81ccfd9854394901bcbd0`),
    installed unmodified as `stockfish\stockfish.exe` next to `Ply.exe`,
    together with the release's `Copying.txt`, `AUTHORS`, README and complete
    `src` folder.
  - Android: `stockfish-android-arm64-universal`
    (archive SHA-256 `ebb24051aa4a222b4daaf049b882ecf1163d370c128fe02316602643f4d5e426`,
    binary SHA-256 `ffd8fc2004d3d19f9fdab95d84c92709aea92e8d3af405eda0b281b23cf1daf8`),
    packaged unmodified as `lib/arm64-v8a/libstockfish.so`.
- It runs as a separate process and Ply talks to it over the UCI protocol.
- License: GNU GPL v3 (`LICENSES/GPL-3.0.txt`). Copyright the Stockfish
  developers (see the `AUTHORS` file in the release).
- Corresponding source: the same release tag on GitHub; the release archive
  that the build downloads also contains the complete source (`stockfish/src`).
  The embedded NNUE network (`nn-1a298aa575a0.nnue`) is part of that release.

## Cburnett chess pieces — artwork

- Author: Colin M. L. Burnett (Cburnett)
- Files: the twelve SVGs in `assets/pieces/cburnett/`, unmodified copies from
  <https://github.com/lichess-org/lila/tree/5b44d719ec5913dd62aa965f4b8d21e60a00c2c1/public/piece/cburnett>
- License: GNU GPL v2 or later (`LICENSES/GPL-2.0.txt`), as stated in Lichess's
  `COPYING.md`. The original drawings on Wikimedia Commons are offered by the
  author under GFDL 1.2+, CC BY-SA 3.0, BSD or GPLv2+ (user's choice).
- The launcher icon uses the pawn outline from the same set.

## Opening names

- Source: <https://github.com/lichess-org/chess-openings> at commit
  `a6189a30dc273ccb21fc2536a9a2fefd5592a67a` (files `a.tsv`–`e.tsv`,
  unmodified, in `assets/openings/`)
- License: CC0 1.0 (public domain dedication)

## Online services (optional)

Loading games by username calls the public APIs of Chess.com
(`api.chess.com/pub`) and Lichess (`lichess.org/api`). No account or key is
used, and nothing is sent except the username. Ply is not affiliated with
either site.

## Dart / Flutter packages

| Package | License | Notes |
|---|---|---|
| [dartchess](https://pub.dev/packages/dartchess) 0.14.0 | GPL-3.0 | Chess rules, SAN, FEN, PGN (by the Lichess developers) |
| [flutter_svg](https://pub.dev/packages/flutter_svg) | MIT | Renders the piece SVGs |
| [file_picker](https://pub.dev/packages/file_picker) | MIT | PGN open/save through the system file dialogs |
| [path_provider](https://pub.dev/packages/path_provider) | BSD-3-Clause | App storage directory |
| [Flutter](https://flutter.dev) SDK | BSD-3-Clause | Includes Roboto and Material Icons fonts (Apache-2.0) |

Transitive dependencies and their licenses are listed in `pubspec.lock` and
on the in-app licenses page.

## Methods (not code)

- Win-percentage curve, move accuracy formula and default
  inaccuracy/mistake/blunder thresholds follow the formulas published in the
  Lichess source code (lila). They are re-implemented here; no Lichess code is
  copied.

## Windows installer

The Windows installer is built with [Inno Setup](https://jrsoftware.org/isinfo.php);
the installer program it produces contains only Ply's files and Inno Setup's
own installer runtime, distributed under the Inno Setup license.
