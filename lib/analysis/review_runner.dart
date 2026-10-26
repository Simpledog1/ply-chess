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
    final pos = game.positionAt(i);
    final terminal = terminalEval(pos);
    if (terminal != null) {
      positions[i] = PositionAnalysis(eval: terminal, depth: depth);
    } else {
      final r = await engine.search(
        fen: game.initialFen,
        moves: game.ucisBefore(i),
        turn: pos.turn,
        depth: depth,
        multiPv: multiPv,
      );
      if (!r.complete) break; // stopped: keep only fully searched positions
      positions[i] = PositionAnalysis(
        eval: r.best!.eval,
        depth: r.depth,
        bestMove: r.bestMove,
        pv: r.best!.pv.take(10).toList(),
        second: r.lines.length > 1 ? r.lines[1].eval : null,
      );
    }
    onProgress?.call(snapshot());
  }
  return snapshot();
}
