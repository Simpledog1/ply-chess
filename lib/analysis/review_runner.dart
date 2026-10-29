import '../chess/chess_game.dart';
import '../engine/uci.dart';
import 'review.dart';

/// Analyses every position of [game] at the same fixed [depth], so that all
/// evaluations in a review come from comparable searches.
///
/// Positions already present in [resume] (same moves and depth) are kept.
/// When [isCancelled] turns true the current search is stopped and the
/// partial review is returned; unfinished positions stay null.
Future<GameReview> runReview({
  required UciEngine engine,
  required ChessGame game,
  required int depth,
  int multiPv = 2,
  GameReview? resume,
  bool Function()? isCancelled,
  void Function(GameReview partial)? onProgress,
}) async {
  final reuse = resume != null && resume.depth == depth && resume.matches(game);
  final positions = reuse
      ? List<PositionAnalysis?>.of(resume.positions)
      : List<PositionAnalysis?>.filled(game.length + 1, null);
  GameReview snapshot() => GameReview(
    depth: depth,
    engine: engine.name ?? 'Stockfish',
    moves: [for (final p in game.plies) p.uci],
    positions: List.of(positions),
  );

  if (!reuse) await engine.newGame();
  for (var i = 0; i <= game.length; i++) {
    if (isCancelled?.call() ?? false) break;
    if (positions[i] != null) continue;
    final r = await analysePosition(engine, game, i, depth, multiPv: multiPv);
    if (r == null) break; // stopped: keep only fully searched positions
    positions[i] = r;
    onProgress?.call(snapshot());
  }
  return snapshot();
}

/// Analyses the position after [i] plies of [game] the way a review does
/// (fixed [depth], two lines). Finished positions are scored by the rules.
/// Returns null when the search was stopped before it completed.
Future<PositionAnalysis?> analysePosition(
  UciEngine engine,
  ChessGame game,
  int i,
  int depth, {
  int multiPv = 2,
}) async {
  final pos = game.positionAt(i);
  final terminal = terminalEval(pos);
  if (terminal != null) return PositionAnalysis(eval: terminal, depth: depth);
  final r = await engine.search(
    fen: game.initialFen,
    moves: game.ucisBefore(i),
    turn: pos.turn,
    depth: depth,
    multiPv: multiPv,
  );
  if (!r.complete) return null;
  return PositionAnalysis(
    eval: r.best!.eval,
    depth: r.depth,
    bestMove: r.bestMove,
    pv: r.best!.pv.take(10).toList(),
    second: r.lines.length > 1 ? r.lines[1].eval : null,
  );
}
