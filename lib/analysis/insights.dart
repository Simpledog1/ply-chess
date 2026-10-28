import 'package:dartchess/dartchess.dart';

import '../storage/game_store.dart';
import 'lessons.dart';
import 'review.dart';

/// Evidence needed before Ply calls something a pattern.
const minGamesForInsights = 5;
const minGamesForPattern = 3;
const minSampleMoves = 30;

enum Evidence {
  insufficient('Not enough data'),
  none('Not observed'),
  normal('In line with your average'),
  recurring('Recurring');

  const Evidence(this.label);
  final String label;
}

class WeaknessStat {
  WeaknessStat({
    required this.title,
    required this.description,
    required this.occurrences,
    required this.games,
    required this.sample,
    required this.baselineRate,
  });

  final String title;
  final String description;

  /// Number of qualifying errors.
  final int occurrences;

  /// Distinct games with at least one qualifying error.
  final int games;

  /// Moves in the situations this category looks at.
  final int sample;

  /// Your general error rate for the same error severity, per move.
  final double baselineRate;

  double get rate => sample == 0 ? 0 : occurrences / sample;

  Evidence evidence(int reviewedGames) {
    if (reviewedGames < minGamesForInsights || sample < minSampleMoves) {
      return Evidence.insufficient;
    }
    if (occurrences == 0) return Evidence.none;
    if (games >= minGamesForPattern && rate >= baselineRate * 1.25) {
      return Evidence.recurring;
    }
    return Evidence.normal;
  }
}

class MyMove {
  MyMove(this.game, this.review);
  final SavedGame game;
  final MoveReview review;
}

class OpeningProblem {
  OpeningProblem(this.opening, this.errors, this.games);
  final String opening;
  final int errors;
  final int games;
}

class Insights {
  Insights._({
    required this.reviewedGames,
    required this.moves,
    required this.trend,
    required this.phaseAccuracy,
    required this.phaseMoves,
    required this.weaknesses,
    required this.missedTactics,
    required this.openingProblems,
    required this.results,
    required this.lessons,
  });

  /// Games with a complete review and a known colour for the user.
  final int reviewedGames;
  final List<MyMove> moves;

  /// (game date, the user's accuracy in that game), oldest first.
  final List<(DateTime, double)> trend;
  final Map<Phase, double?> phaseAccuracy;
  final Map<Phase, int> phaseMoves;
  final List<WeaknessStat> weaknesses;
  final List<MyMove> missedTactics;
  final List<OpeningProblem> openingProblems;
  final Map<String, int> results;

  /// Learning points across reviewed games: kind -> (occurrences, games).
  final Map<LessonKind, (int, int)> lessons;

  /// A learning point is called recurring only with enough evidence.
  bool isRecurring(LessonKind k) {
    final v = lessons[k];
    return v != null &&
        reviewedGames >= minGamesForInsights &&
        v.$2 >= minGamesForPattern;
  }

  double? get averageAccuracy => _mean(trend.map((t) => t.$2));

  /// Mean accuracy of the last 10 games and of the 10 before them.
  (double?, double?) get recentVsPrevious {
    final acc = trend.map((t) => t.$2).toList();
    final recent = acc.length > 10 ? acc.sublist(acc.length - 10) : acc;
    final prev = acc.length > 10
        ? acc.sublist(acc.length > 20 ? acc.length - 20 : 0, acc.length - 10)
        : <double>[];
    return (_mean(recent), _mean(prev));
  }

  int count(MoveClass c) => moves.where((m) => m.review.cls == c).length;

  static Insights compute(
    List<SavedGame> games,
    Thresholds t, {
    ClassOptions options = const ClassOptions(),
    OpeningLookup? book,
  }) {
    final used = [
      for (final g in games)
        if (g.myColor != null &&
            g.review != null &&
            g.review!.complete &&
            g.review!.matches(g.game))
          g,
    ]..sort((a, b) => a.date.compareTo(b.date));

    final moves = <MyMove>[];
    final trend = <(DateTime, double)>[];
    final results = <String, int>{'win': 0, 'loss': 0, 'draw': 0};
    final lessonCounts = <LessonKind, (int, int)>{};
    final lessonGames = <LessonKind, Set<String>>{};
    for (final g in used) {
      final rs = reviewMoves(
        g.game,
        g.review!,
        t,
        options: options,
        book: book,
      );
      final mine = [
        for (final r in rs)
          if (r != null && r.mover == g.myColor && !r.cls.isRoutine)
            MyMove(g, r),
      ];
      moves.addAll(mine);
      for (final l in findLessons(g.game, g.review!, rs, side: g.myColor)) {
        final (n, games) = lessonCounts[l.kind] ?? (0, 0);
        final seen = lessonGames.putIfAbsent(l.kind, () => <String>{});
        lessonCounts[l.kind] = (n + 1, seen.add(g.id) ? games + 1 : games);
      }
      final acc = summarize(rs, g.myColor!).accuracy;
      if (acc != null) trend.add((g.date, acc));
      final res = g.myResult;
      if (res != null) results[res] = results[res]! + 1;
    }

    bool err(MyMove m) => m.review.cls.isError;
    bool serious(MyMove m) => m.review.cls.isSerious;
    final baseErr = moves.isEmpty
        ? 0.0
        : moves.where(err).length / moves.length;
    final baseSerious = moves.isEmpty
        ? 0.0
        : moves.where(serious).length / moves.length;

    WeaknessStat stat(
      String title,
      String desc,
      bool Function(MyMove) inScope,
      bool Function(MyMove) isHit,
      double baseline,
    ) {
      final scope = moves.where(inScope).toList();
      final hits = scope.where(isHit).toList();
      return WeaknessStat(
        title: title,
        description: desc,
        occurrences: hits.length,
        games: hits.map((m) => m.game.id).toSet().length,
        sample: scope.length,
        baselineRate: baseline,
      );
    }

    final weaknesses = [
      stat(
        'Tactics',
        'Mistakes or blunders where Stockfish\'s move was a capture, check or '
            'promotion, or where a forced mate was missed.',
        (_) => true,
        (m) =>
            m.review.tags.contains(MoveTag.tacticalMiss) ||
            m.review.tags.contains(MoveTag.missedMate),
        baseSerious,
      ),
      stat(
        'Defence',
        'Mistakes or blunders made while already worse (below 40% winning '
            'chances), or moves that allowed a forced mate.',
        (m) =>
            m.review.winBefore < 40 ||
            m.review.tags.contains(MoveTag.allowedMate),
        (m) => serious(m) || m.review.tags.contains(MoveTag.allowedMate),
        baseSerious,
      ),
      stat(
        'Converting advantages',
        'Positions where you had at least 70% winning chances and a move '
            'dropped them to 55% or less.',
        (m) => m.review.winBefore >= 70,
        (m) => m.review.tags.contains(MoveTag.missedWin),
        baseSerious,
      ),
      stat(
        'Opening',
        'Inaccuracies or worse in the first 10 moves.',
        (m) => m.review.phase == Phase.opening,
        err,
        baseErr,
      ),
      stat(
        'Quiet middlegames',
        'Inaccuracies or worse in roughly balanced middlegame positions where '
            'the best move was not a capture, check or promotion.',
        (m) =>
            m.review.phase == Phase.middlegame &&
            !m.review.bestIsForcing &&
            m.review.winBefore >= 35 &&
            m.review.winBefore <= 65,
        err,
        baseErr,
      ),
      stat(
        'Endgame',
        'Inaccuracies or worse once at most six pieces (excluding kings and '
            'pawns) remain.',
        (m) => m.review.phase == Phase.endgame,
        err,
        baseErr,
      ),
    ];

    final phaseAccuracy = <Phase, double?>{};
    final phaseMoves = <Phase, int>{};
    for (final p in Phase.values) {
      final pm = moves.where((m) => m.review.phase == p);
      phaseMoves[p] = pm.length;
      phaseAccuracy[p] = _mean(pm.map((m) => m.review.accuracy));
    }

    final missed = moves
        .where(
          (m) =>
              m.review.tags.contains(MoveTag.tacticalMiss) ||
              m.review.tags.contains(MoveTag.missedMate),
        )
        .toList()
        .reversed
        .toList();

    // Opening errors grouped by the PGN "Opening" (or ECO) header.
    final byOpening = <String, List<MyMove>>{};
    for (final m in moves) {
      if (m.review.phase != Phase.opening || !err(m)) continue;
      final name = m.game.headers['Opening'] ?? m.game.headers['ECO'];
      if (name == null || name == '?') continue;
      (byOpening[name] ??= []).add(m);
    }
    final openingProblems = [
      for (final e in byOpening.entries)
        if (e.value.map((m) => m.game.id).toSet().length >= minGamesForPattern)
          OpeningProblem(
            e.key,
            e.value.length,
            e.value.map((m) => m.game.id).toSet().length,
          ),
    ]..sort((a, b) => b.errors.compareTo(a.errors));

    return Insights._(
      reviewedGames: used.length,
      moves: moves,
      trend: trend,
      phaseAccuracy: phaseAccuracy,
      phaseMoves: phaseMoves,
      weaknesses: weaknesses,
      missedTactics: missed,
      openingProblems: openingProblems,
      results: results,
      lessons: lessonCounts,
    );
  }
}

double? _mean(Iterable<double> xs) {
  if (xs.isEmpty) return null;
  return xs.reduce((a, b) => a + b) / xs.length;
}

extension SideName on Side {
  String get label => this == Side.white ? 'White' : 'Black';
}
