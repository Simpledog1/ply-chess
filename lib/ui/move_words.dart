import '../analysis/eval.dart';
import '../analysis/review.dart';

/// One plain sentence on what a rated move did, built only from the
/// classification and the engine's tags.
String moveHeadline(MoveReview m) {
  if (m.tags.contains(MoveTag.allowedMate)) {
    return 'This allows a forced checkmate.';
  }
  if (m.tags.contains(MoveTag.missedMate)) {
    return 'There was a forced checkmate here, and this lets it go.';
  }
  final hopeless = m.winBefore <= 10;
  final winning = m.winBefore >= 90;
  final slipped = m.tags.contains(MoveTag.missedWin);
  return switch (m.cls) {
    MoveClass.brilliant =>
      'A strong sacrifice: Stockfish\'s top choice, even though it gives '
          'up material.',
    MoveClass.critical => 'The only move that keeps the position together.',
    MoveClass.best =>
      winning
          ? 'Stockfish\'s top choice. It keeps the win on track.'
          : 'Stockfish\'s top choice in this position.',
    MoveClass.excellent =>
      hopeless
          ? 'The position was already very difficult; this move does not '
                'make it worse.'
          : 'Practically as good as Stockfish\'s top choice.',
    MoveClass.good =>
      hopeless
          ? 'The position was already very difficult; this keeps it about '
                'the same.'
          : 'A sound move. Stockfish found something a little more precise.',
    MoveClass.theory => 'A well-known opening move.',
    MoveClass.forced => 'The only legal move.',
    MoveClass.inaccuracy => 'A small slip that gives up some winning chances.',
    MoveClass.mistake =>
      slipped
          ? 'This lets a winning position slip away.'
          : 'This gives away a good part of the winning chances.',
    MoveClass.blunder =>
      slipped
          ? 'A serious error that throws away a winning position.'
          : 'A serious error that can decide the game.',
  };
}

/// Rough words for an evaluation, for readers who don't use pawn units.
/// shortcut: the cut-offs (0.4 / 1.2 / 3 pawns) are Ply's own wording, not
/// a chess standard; revisit if users find them misleading.
String evalWords(Eval e) {
  if (e.isMate) {
    final who = e.whiteMates ? 'White' : 'Black';
    return e.mateIn == 0 ? '$who has won' : '$who mates in ${e.mateIn}';
  }
  final c = e.cp!;
  final who = c > 0 ? 'White' : 'Black';
  final a = c.abs();
  if (a < 40) return 'about equal';
  if (a < 120) return 'slightly better for $who';
  if (a < 300) return '$who is better';
  return '$who is winning';
}
