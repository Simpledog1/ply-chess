# Changelog

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
