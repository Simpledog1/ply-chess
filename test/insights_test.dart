import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter_test/flutter_test.dart';
import 'package:ply/analysis/eval.dart';
import 'package:ply/analysis/insights.dart';
import 'package:ply/analysis/review.dart';
import 'package:ply/chess/chess_game.dart';
import 'package:ply/storage/game_store.dart';

/// A reviewed game where Black (the user) blunders into 4. Qxf7#.
SavedGame scholarsMate(String id, {Side me = Side.black}) {
  final g = ChessGame.fromPgn(
    '[Opening "Scholar"]\n\n1. e4 e5 2. Qh5 Nc6 3. Bc4 Nf6 4. Qxf7# 1-0',
  );
  PositionAnalysis pa(Eval e, String? b) =>
      PositionAnalysis(eval: e, depth: 12, bestMove: b);
  return SavedGame(
    id: id,
    pgn: g.toPgn(),
    addedAt: DateTime(2026, 1, int.parse(id) + 1),
    myColor: me,
    review: GameReview(
      depth: 12,
      engine: 't',
      moves: [for (final p in g.plies) p.uci],
      positions: [
        pa(const Eval.cp(30), 'e2e4'),
        pa(const Eval.cp(30), 'e7e5'),
        pa(const Eval.cp(30), 'g1f3'),
        pa(const Eval.cp(0), 'b8c6'),
        pa(const Eval.cp(0), 'f1c4'),
        pa(const Eval.cp(20), 'g7g6'),
        pa(const Eval.mate(1, whiteMates: true), 'h5f7'),
        pa(const Eval.mate(0, whiteMates: true), null),
      ],
    ),
  );
}

void main() {
  test('few games: no weakness is claimed', () {
    final ins = Insights.compute([
      scholarsMate('0'),
      scholarsMate('1'),
    ], const Thresholds());
    expect(ins.reviewedGames, 2);
    for (final w in ins.weaknesses) {
      expect(w.evidence(ins.reviewedGames), Evidence.insufficient);
    }
  });

  test('games without a known colour or full review are ignored', () {
    final g = scholarsMate('0');
    final noColor = SavedGame(
      id: 'x',
      pgn: g.pgn,
      addedAt: g.addedAt,
      review: g.review,
    );
    final noReview = g.copyWith(clearReview: true);
    expect(
      Insights.compute([noColor, noReview], const Thresholds()).reviewedGames,
      0,
    );
  });

  test('only the user\'s moves are counted', () {
    final ins = Insights.compute([
      scholarsMate('0', me: Side.white),
    ], const Thresholds());
    expect(ins.count(MoveClass.blunder), 0);
    expect(ins.moves.every((m) => m.review.mover == Side.white), isTrue);
    expect(ins.results['win'], 1);
  });

  test('aggregates over many games', () {
    final games = [for (var i = 0; i < 12; i++) scholarsMate('$i')];
    final ins = Insights.compute(games, const Thresholds());
    expect(ins.reviewedGames, 12);
    expect(ins.count(MoveClass.blunder), 12);
    expect(ins.results['loss'], 12);
    expect(ins.trend.length, 12);
    expect(ins.openingProblems.single.opening, 'Scholar');
    final defence = ins.weaknesses.firstWhere((w) => w.title == 'Defence');
    expect(defence.occurrences, 12);
    expect(defence.games, 12);
    // Only 12 moves were played while worse: too small a sample to judge.
    expect(defence.sample, 12);
    expect(defence.evidence(ins.reviewedGames), Evidence.insufficient);
    final tactics = ins.weaknesses.firstWhere((w) => w.title == 'Tactics');
    expect(tactics.sample, 36);
    expect(tactics.evidence(ins.reviewedGames), Evidence.none);
  });

  test('recurring needs several games and an above-average rate', () {
    WeaknessStat w(int occ, int games, double base) => WeaknessStat(
      title: 't',
      description: 'd',
      occurrences: occ,
      games: games,
      sample: 100,
      baselineRate: base,
    );
    expect(w(10, 5, 0.05).evidence(10), Evidence.recurring);
    expect(
      w(10, 2, 0.05).evidence(10),
      Evidence.normal,
    ); // one or two games only
    expect(w(5, 5, 0.05).evidence(10), Evidence.normal); // not above average
    expect(w(10, 5, 0.05).evidence(4), Evidence.insufficient); // too few games
  });
}
