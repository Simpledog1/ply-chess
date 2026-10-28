import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter_test/flutter_test.dart';
import 'package:ply/analysis/eval.dart';
import 'package:ply/analysis/lessons.dart';
import 'package:ply/analysis/review.dart';
import 'package:ply/chess/chess_game.dart';

PositionAnalysis pa(Eval e, String? best, [List<String> pv = const []]) =>
    PositionAnalysis(eval: e, depth: 14, bestMove: best, pv: pv);

/// One-move game from [fen] with engine data before/after the move.
List<Lesson> lessonsOf(
  String fen,
  String move,
  PositionAnalysis before,
  PositionAnalysis after,
) {
  final g = ChessGame.fromFen(fen).playUci(0, move)!;
  final data = GameReview(
    depth: 14,
    engine: 't',
    moves: [g.plies.single.uci],
    positions: [before, after],
  );
  final moves = reviewMoves(g, data, const Thresholds());
  return findLessons(g, data, moves);
}

void main() {
  test('queen moved onto a square a pawn attacks is a hanging piece', () {
    final l = lessonsOf(
      '4k3/8/4p3/8/8/8/8/3QK3 w - - 0 1',
      'd1d5',
      pa(const Eval.cp(900), 'd1d2'),
      pa(const Eval.cp(0), 'e6d5', ['e6d5']),
    );
    expect(l.single.kind, LessonKind.hangingPiece);
    expect(l.single.text, contains('queen on d5'));
  });

  test('a missed knight fork of king and rook is reported as a fork', () {
    final l = lessonsOf(
      'r3k3/8/8/1N6/8/8/8/4K3 w - - 0 1',
      'e1e2',
      pa(const Eval.cp(500), 'b5c7', ['b5c7', 'e8d8', 'c7a8']),
      pa(const Eval.cp(0), 'a8a5'),
    );
    expect(l.single.kind, LessonKind.missedFork);
    expect(l.single.text, contains('Nc7+'));
  });

  test('leaving the back rank to a rook mate is a back-rank weakness', () {
    final l = lessonsOf(
      '4r1k1/5ppp/8/8/8/8/5PPP/3Q2K1 w - - 0 1',
      'd1a4',
      pa(const Eval.cp(0), 'g1f1'),
      pa(const Eval.mate(1, whiteMates: false), 'e8e1', ['e8e1']),
    );
    expect(l.single.kind, LessonKind.backRank);
  });

  test('a missed forced mate is reported first', () {
    final l = lessonsOf(
      '6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1',
      'g1f2',
      pa(const Eval.mate(1, whiteMates: true), 'a1a8', ['a1a8']),
      pa(const Eval.cp(500), 'g8f8'),
    );
    expect(l.single.kind, LessonKind.missedMate);
    expect(l.single.text, contains('mate in 1'));
  });

  test('good moves produce no lessons; side filter applies', () {
    final g = ChessGame.fromPgn('1. e4 e5');
    final data = GameReview(
      depth: 14,
      engine: 't',
      moves: [for (final p in g.plies) p.uci],
      positions: [
        pa(const Eval.cp(30), 'e2e4'),
        pa(const Eval.cp(30), 'e7e5'),
        pa(const Eval.cp(30), 'g1f3'),
      ],
    );
    final moves = reviewMoves(g, data, const Thresholds());
    expect(findLessons(g, data, moves), isEmpty);
    expect(findLessons(g, data, moves, side: Side.black), isEmpty);
  });

  test('grouping sorts by frequency', () {
    final grouped = groupLessons(const [
      Lesson(LessonKind.opening, 0, 'a'),
      Lesson(LessonKind.hangingPiece, 3, 'b'),
      Lesson(LessonKind.hangingPiece, 9, 'c'),
    ]);
    expect(grouped.first.$1, LessonKind.hangingPiece);
    expect(grouped.first.$2.length, 2);
  });
}
