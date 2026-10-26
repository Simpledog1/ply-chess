import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ply/analysis/eval.dart';
import 'package:ply/analysis/openings.dart';
import 'package:ply/analysis/review.dart';
import 'package:ply/chess/chess_game.dart';
import 'package:ply/online/online_games.dart';

PositionAnalysis pa(Eval e, String? best, {Eval? second}) =>
    PositionAnalysis(eval: e, depth: 14, bestMove: best, second: second);

GameReview reviewOf(ChessGame g, List<PositionAnalysis> ps) => GameReview(
  depth: 14,
  engine: 't',
  moves: [for (final p in g.plies) p.uci],
  positions: ps,
);

void main() {
  const tsv =
      'eco\tname\tpgn\n'
      'C50\tItalian Game\t1. e4 e5 2. Nf3 Nc6 3. Bc4\n'
      'C20\tKing\'s Pawn Game\t1. e4 e5\n';
  final book = OpeningBook.parse([tsv]);

  group('opening book', () {
    test('names the deepest listed position', () {
      final g = ChessGame.fromPgn('1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. c3');
      expect(book.openingOf(g), ('C50', 'Italian Game'));
      expect(book.contains(g.positionAt(4)), isTrue); // after 2...Nc6
      expect(book.contains(g.positionAt(6)), isFalse); // after 3...Bc5
    });

    test('theory stops at the first move out of the book', () {
      final g = ChessGame.fromPgn('1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5');
      final data = reviewOf(g, [
        for (var i = 0; i <= g.length; i++) pa(const Eval.cp(30), 'a2a3'),
      ]);
      final r = reviewMoves(g, data, const Thresholds(), book: book);
      expect(r.take(5).every((m) => m!.cls == MoveClass.theory), isTrue);
      expect(r[5]!.cls, isNot(MoveClass.theory));
      // Theory moves are not counted as decisions in accuracy.
      expect(summarize(r, r[0]!.mover).moves, 0);

      final off = reviewMoves(
        g,
        data,
        const Thresholds(),
        book: book,
        options: const ClassOptions(theory: false),
      );
      expect(off.any((m) => m!.cls == MoveClass.theory), isFalse);
    });

    test('real Lichess opening list loads and names common openings', () {
      final real = OpeningBook.parse([
        for (final f in 'abcde'.split(''))
          File('assets/openings/$f.tsv').readAsStringSync(),
      ]);
      expect(real.size, greaterThan(3000));
      final ruy = ChessGame.fromPgn('1. e4 e5 2. Nf3 Nc6 3. Bb5 a6');
      expect(real.openingOf(ruy)!.$2, startsWith('Ruy Lopez'));
      final qgd = ChessGame.fromPgn('1. d4 d5 2. c4 e6');
      expect(real.openingOf(qgd)!.$2, contains("Queen's Gambit Declined"));
    });
  });

  group('critical', () {
    final g = ChessGame.fromPgn('1. e4');
    test('best move with a much worse second choice is critical', () {
      final r = reviewMoves(
        g,
        reviewOf(g, [
          pa(const Eval.cp(30), 'e2e4', second: const Eval.cp(-300)),
          pa(const Eval.cp(30), 'e7e5'),
        ]),
        const Thresholds(),
      );
      expect(r.single!.cls, MoveClass.critical);
      expect(r.single!.explanation, contains('only move that holds'));
    });

    test('a close second choice keeps it plain best; can be switched off', () {
      final close = reviewOf(g, [
        pa(const Eval.cp(30), 'e2e4', second: const Eval.cp(20)),
        pa(const Eval.cp(30), 'e7e5'),
      ]);
      expect(
        reviewMoves(g, close, const Thresholds()).single!.cls,
        MoveClass.best,
      );
      final far = reviewOf(g, [
        pa(const Eval.cp(30), 'e2e4', second: const Eval.cp(-300)),
        pa(const Eval.cp(30), 'e7e5'),
      ]);
      final r = reviewMoves(
        g,
        far,
        const Thresholds(),
        options: const ClassOptions(critical: false),
      );
      expect(r.single!.cls, MoveClass.best);
    });
  });

  group('brilliant', () {
    test('sacrifice detection', () {
      final italian = ChessGame.fromPgn('1. e4 e5 2. Nf3 Nc6 3. Bc4 Nf6');
      // Bxf7+: the bishop can be taken by the king.
      expect(isSacrifice(italian.last, 'c4f7'), isTrue);
      // Developing a knight to a safe square is not a sacrifice.
      expect(isSacrifice(ChessGame.standard().last, 'g1f3'), isFalse);
      // Pawn moves never count.
      expect(isSacrifice(ChessGame.standard().last, 'e2e4'), isFalse);
      // Capturing a queen with a queen gains as much as it risks.
      final trade = ChessGame.fromFen('3qk3/8/8/8/8/8/8/3QK3 w - - 0 1');
      expect(isSacrifice(trade.last, 'd1d8'), isFalse);
      // Taking a defended pawn with the queen hangs it to the defender.
      final hang = ChessGame.fromPgn(
        '1. d4 d5 2. c4 dxc4 3. e3 e5 4. Bxc4 exd4 5. exd4',
      );
      expect(isSacrifice(hang.last, 'd8d4'), isTrue);
    });

    test('best move that sacrifices and keeps the game is brilliant', () {
      final g = ChessGame.fromPgn('1. e4 e5 2. Nf3 Nc6 3. Bc4 Nf6 4. Bxf7+');
      final data = reviewOf(g, [
        for (var i = 0; i < g.length; i++)
          pa(const Eval.cp(30), g.plies[i].uci),
        pa(const Eval.cp(60), null),
      ]);
      final r = reviewMoves(g, data, const Thresholds());
      expect(r.last!.cls, MoveClass.brilliant);
      expect(r.last!.accuracy, 100);
      final off = reviewMoves(
        g,
        data,
        const Thresholds(),
        options: const ClassOptions(brilliant: false),
      );
      expect(off.last!.cls, MoveClass.best);
    });

    test('a losing sacrifice is not brilliant', () {
      final g = ChessGame.fromPgn('1. e4 e5 2. Nf3 Nc6 3. Bc4 Nf6 4. Bxf7+');
      final data = reviewOf(g, [
        for (var i = 0; i < g.length; i++)
          pa(const Eval.cp(-400), g.plies[i].uci),
        pa(const Eval.cp(-450), null),
      ]);
      expect(
        reviewMoves(g, data, const Thresholds()).last!.cls,
        MoveClass.best,
      );
    });
  });

  test('second-best evaluation survives JSON', () {
    final p = pa(
      const Eval.cp(10),
      'e2e4',
      second: const Eval.mate(2, whiteMates: false),
    );
    final back = PositionAnalysis.fromJson(p.toJson());
    expect(back.second, const Eval.mate(2, whiteMates: false));
  });

  test('multi-game PGN export is split per game', () {
    const text =
        '[Event "A"]\r\n[White "x"]\r\n\r\n1. e4 e5 1-0\r\n\r\n\r\n'
        '[Event "B"]\n[White "y"]\n\n1. d4 d5 0-1\n';
    final games = OnlineGames.splitPgn(text);
    expect(games.length, 2);
    expect(ChessGame.fromPgn(games[1]).headers['White'], 'y');
  });
}
