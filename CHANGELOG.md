# Changelog

## 1.3.1 — Game loading in the analysis panel

### Changed
- Site, username and **Load games** moved from the top bar into the Game
  Analysis panel (Your games view), above the games list. The top bar now
  holds only the Ply name and the section tabs, aligned to the right.

## 1.3.0 — Board left, Game Analysis panel right

### Changed
- **New desktop layout**: the board takes the left side and grows with the
  window (player names and ratings above and below it); everything else
  lives in one **Game Analysis** panel on the right: a tool row (your
  games, analyse / deeper review / stop, flip, settings, share, save,
  more), a **Report | Analysis** switch, and the move buttons at the bottom.
  The separate games column and the controls under the board are gone.
- **Report**: winning-chances graph (follows the shown move, click to
  jump), each player's accuracy, a classification table per player (click
  a count to go to that player's next move of that kind), key moments and
  learning points.
- **Analysis**: the move card, a new **Best for … now** row (Stockfish's
  move and line for the position on the board, and how the game's move
  compared), the live engine and the move list with the what-if line.
- **Your games** (the back arrow): recent games plus Paste PGN, Open PGN and
  FEN. Loading games shows it; opening a game shows its report; a what-if
  move shows the Analysis view.
- The top bar hides its tagline on windows narrower than 1280 px so the
  section tabs stay visible.

## 1.2.1 — What-if line in the move list, sharper board

### Changed
- The what-if line is shown inside the move list on the right, in an
  amber block under the game move it branches from, with its own Undo and
  Back to game. Its moves can be clicked to show their positions. The bar
  under the board is gone.

### Fixed
- Blurry board and pieces: the board was sized and placed on fractional
  pixels, so every square edge and piece outline was smeared across two
  pixels (at every Windows display scaling). It now snaps to whole physical
  pixels at any window size and scaling.
- An engine reporting the null move `0000` as its best move no longer
  breaks the board's suggestion arrow.

## 1.2.0 — One-screen analysis and move feedback

### Added
- **Move card**: the shown move's rating in plain words (Best, Excellent,
  Good, Inaccuracy, Mistake, Blunder…), the evaluation before → after with a
  short description ("White is better"), Stockfish's move with **Show line**,
  and what follows. It updates on every step through the game, and shows an
  honest pending state ("Checking your move…", "Analysis not available yet")
  instead of a guess.
- **What-if moves**: moving a piece on an analysed or loaded game starts a
  separate line, labelled *Your what-if move*. Stockfish checks the new
  position in the background at the review's depth, reusing the stored
  analysis for everything else. **Undo** (Backspace) and **Back to game**
  (Esc) return to the game; the game and its review are never changed.
- Results of background checks are cached per position, and outdated
  searches are stopped when you move on, so a result cannot appear on the
  wrong move.

### Changed
- **The game review is on the analysis screen.** The Review tab and the
  separate report page are gone; summary, winning-chances graph, key
  moments, well-played moves and learning points sit under the move list
  (collapsible) and jump to their positions on the board.
- **Redesigned interface**: refined dark and light themes, bordered panels,
  a clearer Analyse game button with progress, a two-column move list with
  quality symbols and tooltips, a what-if bar under the board, a welcome
  card, tooltips on secondary controls, and layouts checked at 1366×768,
  1440×900 and 1920×1080.
- Moves played on a new board or FEN position are also checked in the
  background; once a game is analysed, board moves become what-ifs.
- The live engine is keyed to the shown position, so it never shows a line
  for a different position after you switch lines.


## 1.1.0 — Windows desktop app

### Added
- **Windows desktop app** (`Ply.exe`) with an installer (`Ply-Setup-1.1.0.exe`,
  per-user, no admin rights) and a portable zip. Stockfish 19 for Windows is
  bundled.
- **Profiles**: pick Lichess or Chess.com, type a username, load recent public
  games. Profiles are keyed by site + username, remembered between sessions,
  and only saved once the site confirms the account exists.
- **Paged game loading** with "Load more" (Lichess game export with a time
  cursor; Chess.com monthly archives fetched only as needed), a 10-minute
  in-memory cache, cancel, and clear messages for unknown users, rate limits,
  outages and offline use.
- **Desktop layout**: top bar, recent games | board | analysis panel with
  Moves and Review tabs; keyboard navigation (←/→, Home/End, F, Space, E).
- **Review tab** with key mistakes (played move, best move, evaluation
  before → after, engine line, jump buttons) and **learning points** from the
  game: missed or allowed mates, back-rank mates, hanging pieces, missed
  forks and tactics, king safety, missed defences, slipped wins, poor
  exchanges, opening errors. **Deeper review** at depth 20 on demand.
- Insights count learning points across saved games and only call one
  recurring with enough evidence (3+ games out of 5+ reviewed).

### Changed
- **Local history is now optional and off by default.** Games and analysis
  stay in memory until Ply closes. When turned on, reviewed games are saved
  locally; a profile's data, or all history, can be deleted in Settings.
- The Games tab is now **History**.
- Windows data lives in `%APPDATA%\Simpledog1\Ply`, never in the install
  folder.

### Fixed
- Chess.com lists the current month in a player's archive index but can
  answer 404 for it, which Ply reported as "player not found". Missing
  months are now treated as empty.

## 1.0.0 — Android

First release: Stockfish 19 on the phone, board with Cburnett pieces,
PGN/FEN import and export, game review with Brilliant / Critical / Best /
Excellent / Good / Theory / Inaccuracy / Mistake / Blunder / Forced
classifications, local game library and Insights.
