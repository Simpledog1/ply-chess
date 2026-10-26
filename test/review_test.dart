import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ply/analysis/eval.dart';
import 'package:ply/analysis/review.dart';
import 'package:ply/analysis/review_runner.dart';
import 'package:ply/chess/chess_game.dart';
import 'package:ply/engine/uci.dart';

import 'uci_test.dart' show FakeEngine;

PositionAnalysis pa(Eval e, [String? best, List<String> pv = const []]) =>
    PositionAnalysis(eval: e, depth: 14, bestMove: best, pv: pv);

GameReview reviewOf(ChessGame g, List<PositionAnalysis?> ps) => GameReview(
  depth: 14,
  engine: 'test',
  moves: [for (final p in g.plies) p.uci],
  positions: ps,
);

void main() {
  // 1. e4 e5 2. Qh5 Nc6 3. Bc4 Nf6?? 4. Qxf7#
  final game = ChessGame.fromPgn('1. e4 e5 2. Qh5 Nc6 3. Bc4 Nf6 4. Qxf7#');
  final data = reviewOf(game, [
    pa(const Eval.cp(30), 'e2e4'),
    pa(const Eval.cp(30), 'e7e5'),
    pa(const Eval.cp(30), 'g1f3'),
    pa(const Eval.cp(0), 'b8c6'),
    pa(const Eval.cp(0), 'f1c4'),
    pa(const Eval.cp(20), 'g7g6', ['g7g6', 'h5f3']),
    pa(const Eval.mate(1, whiteMates: true), 'h5f7', ['h5f7']),
    pa(terminalEval(game.last)!),
  ]);
  const t = Thresholds();
  final r = reviewMoves(game, data, t);

  test('engine best move is classified best with full accuracy', () {
    expect(r[0]!.cls, MoveClass.best);
    expect(r[0]!.accuracy, 100);
    expect(r[6]!.cls, MoveClass.best);
  });

  test('small win% loss is good, not an error', () {
    expect(r[2]!.cls, MoveClass.good);
    expect(r[2]!.loss, closeTo(const Eval.cp(30).whiteWinPercent - 50, 1e-9));
  });

  test('allowing mate is a blunder from the mover\'s perspective', () {
    final m = r[5]!;
    expect(m.mover, Side.black);
    expect(m.cls, MoveClass.blunder);
    expect(m.tags, contains(MoveTag.allowedMate));
    expect(m.winAfter, 0);
    expect(m.bestSan, 'g6');
    expect(m.explanation, contains('Stockfish preferred g6'));
    expect(m.explanation, contains('forced mate in 1'));
    expect(m.replyLine, '4. Qxf7#');
  });

  test('checkmate on the board is evaluated by the rules', () {
    final e = terminalEval(game.last)!;
    expect(e.isMate, isTrue);
    expect(e.mateIn, 0);
    expect(e.whiteMates, isTrue);
  });

  test('summary counts and accuracy per side', () {
    final w = summarize(r, Side.white);
    final b = summarize(r, Side.black);
    expect(w.counts[MoveClass.best], 3);
    expect(w.counts[MoveClass.good], 1);
    expect(b.counts[MoveClass.blunder], 1);
    expect(b.accuracy!, lessThan(w.accuracy!));
    expect(criticalMoments(r).first.ply, 5);
  });

  test('missed mate is tagged', () {
    final g = ChessGame.fromPgn('1. e4 e5 2. Qh5 Nc6 3. Bc4 Nf6 4. Qf3');
    final rv = reviewMoves(
      g,
      reviewOf(g, [...data.positions.take(7), pa(const Eval.cp(20), 'f6e4')]),
      t,
    );
    expect(rv[6]!.tags, contains(MoveTag.missedMate));
    expect(rv[6]!.tags, contains(MoveTag.missedWin));
    expect(rv[6]!.tags, contains(MoveTag.tacticalMiss));
    expect(missedOpportunities(rv).first.ply, 6);
  });

  test('only legal move is forced', () {
    final g = ChessGame.fromFen('k7/8/2K5/8/8/8/8/1R6 b - - 0 1')
        .playUci(0, 'a8a7');
    // Rook covers the b-file, king covers b7: only Ka7 is legal.
    expect(g, isNotNull);
    final rv = reviewMoves(
      g!,
      reviewOf(g, [
        pa(const Eval.cp(900), 'a8a7'),
        pa(const Eval.cp(1200), 'b6c6'),
      ]),
      t,
    );
    // Even if the engine names it, a single legal move is reported as forced.
    expect(rv.single!.cls, MoveClass.forced);
  });

  test('missing analysis leaves gaps instead of guessing', () {
    final partial = reviewOf(game, [
      ...data.positions.take(3),
      ...List.filled(5, null),
    ]);
    final rv = reviewMoves(game, partial, t);
    expect(rv[0], isNotNull);
    expect(rv[1], isNotNull);
    expect(rv[2], isNull);
    expect(partial.complete, isFalse);
  });

  test('thresholds are configurable', () {
    expect(t.classify(1), MoveClass.excellent);
    expect(t.classify(4.9), MoveClass.good);
    expect(t.classify(5), MoveClass.inaccuracy);
    expect(t.classify(10), MoveClass.mistake);
    expect(t.classify(15), MoveClass.blunder);
    const strict = Thresholds(inaccuracy: 3, mistake: 6, blunder: 9);
    expect(strict.classify(7), MoveClass.mistake);
    expect(Thresholds.fromJson(strict.toJson()).blunder, 9);
  });

  test('review matches only the same move sequence', () {
    expect(data.matches(game), isTrue);
    final other = game.playUci(2, 'g1f3')!;
    expect(data.matches(other), isFalse);
    expect(GameReview.fromJson(data.toJson()).matches(game), isTrue);
  });

  test('accuracy formula', () {
    expect(moveAccuracy(50, 50), 100);
    expect(moveAccuracy(50, 60), 100);
    expect(moveAccuracy(60, 10), lessThan(15));
    expect(moveAccuracy(55, 50), inInclusiveRange(80, 90));
  });

  group('runReview', () {
    test('searches every non-terminal position at the same depth', () async {
      final t = FakeEngine()
        ..searchOutput = ['info depth 8 score cp 10 pv e2e4'];
      final e = UciEngine(t);
      await e.init();
      final rv = await runReview(engine: e, game: game, depth: 8);
      expect(rv.complete, isTrue);
      expect(
        t.sent.where((s) => s == 'go depth 8').length,
        game.length,
      ); // final mate skipped
      expect(rv.positions.last!.eval.mateIn, 0);
      expect(t.sent, contains('ucinewgame'));
    });

    test('cancel keeps a partial review, resume finishes it', () async {
      final t = FakeEngine()
        ..searchOutput = ['info depth 8 score cp 10 pv e2e4'];
      final e = UciEngine(t);
      await e.init();
      var n = 0;
      final partial = await runReview(
        engine: e,
        game: game,
        depth: 8,
        isCancelled: () => n >= 3,
        onProgress: (_) => n++,
      );
      expect(partial.complete, isFalse);
      expect(partial.analysedCount, 3);
      t.sent.clear();
      final done = await runReview(
        engine: e,
        game: game,
        depth: 8,
        resume: partial,
      );
      expect(done.complete, isTrue);
      expect(t.sent.where((s) => s.startsWith('go')).length, game.length - 3);
    });
  });
}
