import 'puzzle.dart';
import 'training_store.dart';

/// Results of a set of attempts (a cycle, a collection, calibration).
class AttemptSummary {
  AttemptSummary(List<Attempt> attempts)
    : attempted = attempts.length,
      firstTry = attempts.where((a) => a.firstTryCorrect).length,
      solved = attempts.where((a) => a.solved).length,
      skipped = attempts.where((a) => a.skipped).length,
      failed = attempts.where((a) => a.failed).length,
      wrongMoves = attempts.fold(0, (n, a) => n + a.wrongMoves),
      hinted = attempts.where((a) => a.hintLevel > 0).length,
      _solvedMs = [
        for (final a in attempts)
          if (a.solved) a.elapsedMs,
      ]..sort();

  final int attempted;
  final int firstTry;

  /// Solved in the end, with or without wrong moves or hints.
  final int solved;

  /// Abandoned by the player (reported separately, never counted solved).
  final int skipped;

  /// The solution was shown (Reveal) without the player solving it.
  final int failed;
  final int wrongMoves;
  final int hinted;
  final List<int> _solvedMs;

  /// First-attempt accuracy in percent: solved with no wrong move or hint.
  double? get firstTryRate =>
      attempted == 0 ? null : 100 * firstTry / attempted;

  /// Eventual accuracy in percent.
  double? get solvedRate => attempted == 0 ? null : 100 * solved / attempted;

  /// Mean solving time of solved puzzles (abandoned and failed excluded).
  Duration? get averageTime => _solvedMs.isEmpty
      ? null
      : Duration(
          milliseconds: _solvedMs.reduce((a, b) => a + b) ~/ _solvedMs.length,
        );

  Duration? get medianTime => _solvedMs.isEmpty
      ? null
      : Duration(milliseconds: _solvedMs[_solvedMs.length ~/ 2]);

  double get wrongMovesPerPuzzle => attempted == 0 ? 0 : wrongMoves / attempted;
}

/// Performance on one tactical theme.
class ThemeStat {
  ThemeStat(this.theme);
  final String theme;
  int attempts = 0;
  int firstTry = 0;
  int solved = 0;
  int solvedMs = 0;
  final puzzles = <String>{};

  /// Puzzles solved first try in at least two different cycles.
  int repeatedSuccess = 0;

  double get firstTryRate => attempts == 0 ? 0 : firstTry / attempts;
  Duration? get averageTime =>
      solved == 0 ? null : Duration(milliseconds: solvedMs ~/ solved);
}

/// Per-theme statistics over [attempts]; [cycleOf] tells which cycle an
/// attempt came from (for repeated success). Rebuilt from the attempts
/// each time, so it can never drift from the recorded history.
Map<String, ThemeStat> themeStats(
  Iterable<Attempt> attempts, {
  int Function(Attempt)? cycleOf,
  bool motifsOnly = true,
}) {
  final out = <String, ThemeStat>{};
  final firstTryCycles = <String, Set<int>>{};
  for (final a in attempts) {
    final themes = motifsOnly
        ? a.themes.where((t) => !nonMotifThemes.contains(t) || t == 'mate')
        : a.themes;
    for (final t in themes) {
      final s = out.putIfAbsent(t, () => ThemeStat(t));
      s.attempts++;
      s.puzzles.add(a.puzzleId);
      if (a.firstTryCorrect) s.firstTry++;
      if (a.solved) {
        s.solved++;
        s.solvedMs += a.elapsedMs;
      }
    }
    if (a.firstTryCorrect && cycleOf != null) {
      (firstTryCycles[a.puzzleId] ??= {}).add(cycleOf(a));
    }
  }
  for (final s in out.values) {
    s.repeatedSuccess = s.puzzles
        .where((p) => (firstTryCycles[p]?.length ?? 0) >= 2)
        .length;
  }
  return out;
}

/// When a puzzle counts as provisionally mastered. A working rule of
/// thumb for the dashboard, not a validated measure of chess skill.
class MasteryRules {
  const MasteryRules({this.cycles = 2, this.maxSeconds = 60});

  /// The latest [cycles] attempts must all be first-try solves.
  final int cycles;

  /// ...each within this time.
  final int maxSeconds;

  bool mastered(List<Attempt> history) {
    if (history.length < cycles) return false;
    final recent = history.sublist(history.length - cycles);
    return recent.every(
      (a) => a.firstTryCorrect && a.elapsedMs <= maxSeconds * 1000,
    );
  }
}

/// Puzzles of [c] that are provisionally mastered.
int masteredCount(
  TrainingCollection c, [
  MasteryRules rules = const MasteryRules(),
]) {
  var n = 0;
  for (final id in c.puzzleIds) {
    final history = [
      for (final cy in c.cycles)
        for (final a in cy.attempts)
          if (a.puzzleId == id) a,
    ];
    if (rules.mastered(history)) n++;
  }
  return n;
}

/// Read-only view of training results for other parts of Ply (a future
/// Insights integration). It reports puzzle performance only; it does not
/// claim that puzzle results reflect weaknesses in real games.
abstract interface class TrainingInsightsSource {
  /// Estimated puzzle-solving rating and its deviation, if a profile exists.
  (double, double)? get puzzleRating;

  /// First-exposure (cycle 1 and calibration) performance per theme.
  Map<String, ThemeStat> get firstExposureThemes;

  /// Summary of every completed cycle, oldest first.
  List<(TrainingCollection, TrainingCycle, AttemptSummary)> get cycleHistory;
}

/// [TrainingInsightsSource] backed by the training store.
class TrainingStats implements TrainingInsightsSource {
  TrainingStats(this.store);
  final TrainingStore store;

  @override
  (double, double)? get puzzleRating {
    final p = store.profile;
    return p == null ? null : (p.estimate, p.deviation);
  }

  @override
  Map<String, ThemeStat> get firstExposureThemes => themeStats([
    ...?store.profile?.calibration,
    for (final c in store.collections) ...?c.cycle(1)?.attempts,
  ]);

  @override
  List<(TrainingCollection, TrainingCycle, AttemptSummary)> get cycleHistory =>
      [
        for (final c in store.collections)
          for (final cy in c.cycles)
            if (cy.status == CycleStatus.completed)
              (c, cy, AttemptSummary(cy.attempts)),
      ];
}
