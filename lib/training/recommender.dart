import 'dart:math' as math;

import 'puzzle.dart';
import 'training_stats.dart';
import 'training_store.dart';

/// Tunable numbers of the recommendation rules, in one place. They are
/// Ply's own choices, not a published standard.
class RecommenderConfig {
  const RecommenderConfig({
    this.calibrationLength = 12,
    this.targetedShare = 0.30,
    this.centerOffset = -100,
    this.halfWidth = 150,
    this.maxHalfWidth = 450,
    this.minThemeAttempts = 8,
    this.weakMargin = 0.10,
    this.maxWeakThemes = 3,
    this.fastMedianSeconds = 45,
  });

  /// Puzzles in the first calibration.
  final int calibrationLength;

  /// Share of a collection aimed at weak themes (when any are known).
  final double targetedShare;

  /// Collections are centred this far from the estimate: at −100 the
  /// expected first-try success is about 64% (Elo formula), demanding but
  /// solvable, which suits repetition training.
  final int centerOffset;
  final int halfWidth;
  final int maxHalfWidth;

  /// A theme needs this many first-exposure attempts before Ply calls it
  /// weak, and a first-try rate this far below the player's overall rate.
  final int minThemeAttempts;
  final double weakMargin;
  final int maxWeakThemes;

  /// Median solving time (cycle 1) counted as fast.
  final int fastMedianSeconds;
}

/// Starting estimate of puzzle strength from a chess rating.
/// shortcut: rough offsets between rating pools (Chess.com and FIDE about
/// 250 points below Lichess at club level); calibration corrects them.
(double, double) initialEstimate(RatingSource source, int? rating) {
  if (rating == null || source == RatingSource.none) return (1200, 350);
  final lichess = switch (source) {
    RatingSource.chessCom || RatingSource.fide => rating + 250,
    _ => rating,
  };
  return (lichess.clamp(600, 2800).toDouble(), 250);
}

/// Expected first-try success for a puzzle of [puzzle] rating.
double expectedScore(double estimate, num puzzle) =>
    1 / (1 + math.pow(10, (puzzle - estimate) / 400));

/// Updates the estimate after one attempt (Elo-style, with a step that
/// shrinks as the estimate becomes more certain). Only correctness counts
/// here: a solve after a wrong move or hint scores 0.3, a miss 0.
(double, double) updateEstimate(double estimate, double deviation, Attempt a) {
  final score = a.firstTryCorrect ? 1.0 : (a.solved ? 0.3 : 0.0);
  final k = (deviation * 0.2).clamp(16.0, 70.0);
  final next = estimate + k * (score - expectedScore(estimate, a.rating));
  return (next.clamp(400, 3000).toDouble(), math.max(60.0, deviation * 0.93));
}

String confidenceLabel(double deviation) => deviation >= 200
    ? 'low'
    : deviation >= 110
    ? 'medium'
    : 'high';

/// Picks the next calibration puzzle: the closest rating to the current
/// estimate, avoiding repeated themes and used puzzles (adaptive).
Puzzle? nextCalibrationPuzzle(
  Iterable<Puzzle> catalogue,
  double estimate,
  List<Attempt> done,
) {
  final used = done.map((a) => a.puzzleId).toSet();
  final recentThemes = {
    for (final a in done.reversed.take(3)) primaryThemeOf(a.themes),
  };
  Puzzle? best;
  var bestScore = double.infinity;
  for (final p in catalogue) {
    if (used.contains(p.id) || p.playerMoves > 3) continue;
    final s =
        (p.rating - estimate).abs() +
        (recentThemes.contains(p.primaryTheme) ? 150 : 0);
    if (s < bestScore) {
      bestScore = s;
      best = p;
    }
  }
  return best;
}

/// Themes where the player is clearly below their own average, judged on
/// first exposures only (calibration and cycle 1), with a minimum sample.
List<String> weakThemes(
  List<Attempt> firstExposures, {
  RecommenderConfig config = const RecommenderConfig(),
}) {
  if (firstExposures.isEmpty) return const [];
  final overall =
      firstExposures.where((a) => a.firstTryCorrect).length /
      firstExposures.length;
  final stats = themeStats(firstExposures).values
      .where((s) => s.attempts >= config.minThemeAttempts && s.theme != 'mate');
  final weak =
      stats.where((s) => s.firstTryRate <= overall - config.weakMargin).toList()
        ..sort((a, b) => a.firstTryRate.compareTo(b.firstTryRate));
  return [for (final s in weak.take(config.maxWeakThemes)) s.theme];
}

/// How difficulty changes after a collection, judged on cycle 1 (first
/// exposure): accuracy and speed together.
({int delta, String reason}) difficultyChange(
  AttemptSummary cycle1, {
  RecommenderConfig config = const RecommenderConfig(),
}) {
  final acc = cycle1.firstTryRate;
  final median = cycle1.medianTime;
  if (acc == null || cycle1.attempted < 20) {
    return (delta: 0, reason: 'Not enough results yet: same difficulty.');
  }
  if (acc >= 80 &&
      median != null &&
      median.inSeconds <= config.fastMedianSeconds) {
    return (
      delta: 75,
      reason: 'Accurate and quick: puzzles get a little harder.',
    );
  }
  if (acc >= 80) {
    return (
      delta: 0,
      reason: 'Accurate but slow: same difficulty, aim for faster recognition.',
    );
  }
  if (acc < 55) {
    return (
      delta: -100,
      reason: 'Many first-try misses: puzzles get a little easier.',
    );
  }
  return (delta: 0, reason: 'Mixed results: same difficulty.');
}

/// A planned collection, or the reason it cannot be built.
class CollectionPlan {
  CollectionPlan({
    required this.puzzles,
    required this.center,
    required this.halfWidth,
    required this.general,
    required this.targeted,
    required this.targetThemes,
    this.reusesOldPuzzles = false,
  });

  /// Puzzles in membership order (cycle orders are made separately).
  final List<Puzzle> puzzles;
  final int center;
  final int halfWidth;
  final int general;
  final int targeted;
  final List<String> targetThemes;
  final bool reusesOldPuzzles;

  Map<String, dynamic> toMeta(String reason) => {
    'center': center,
    'halfWidth': halfWidth,
    'general': general,
    'targeted': targeted,
    'targetThemes': targetThemes,
    'reason': reason,
    if (reusesOldPuzzles) 'reusesOldPuzzles': true,
  };
}

class Shortage {
  Shortage({
    required this.wanted,
    required this.available,
    required this.availableWithReuse,
  });
  final int wanted;

  /// New (never used) puzzles within the widest rating range.
  final int available;

  /// Including puzzles from earlier collections.
  final int availableWithReuse;

  String get message =>
      'Only $available new puzzles fit your level (you asked for $wanted). '
      'Download more puzzles, choose a smaller collection'
      '${availableWithReuse >= wanted ? ', or allow puzzles from earlier collections' : ''}.';
}

/// Builds a collection of [size] puzzles around [estimate]: about 70%
/// general, ability-matched puzzles spread over many themes, and about 30%
/// from [weak] themes (if any). Puzzles in [exclude] (earlier collections)
/// are avoided unless [allowReuse]. Never returns fewer than [size]
/// puzzles: a [Shortage] explains what is missing instead.
Object buildCollection({
  required Iterable<Puzzle> catalogue,
  required int size,
  required double estimate,
  List<String> weak = const [],
  Set<String> exclude = const {},
  bool allowReuse = false,
  int seed = 1,
  RecommenderConfig config = const RecommenderConfig(),
}) {
  final rng = math.Random(seed);
  final center = (estimate + config.centerOffset).round();
  final pool = [
    for (final p in catalogue)
      if (allowReuse || !exclude.contains(p.id)) p,
  ];
  final targeted = weak.isEmpty ? 0 : (size * config.targetedShare).round();
  var half = config.halfWidth;
  List<Puzzle> inRange() => [
    for (final p in pool)
      if ((p.rating - center).abs() <= half) p,
  ];
  var range = inRange();
  while (range.length < size && half < config.maxHalfWidth) {
    half += 100;
    range = inRange();
  }
  if (range.length < size) {
    if (!allowReuse) {
      final withReuse = catalogue
          .where((p) => (p.rating - center).abs() <= config.maxHalfWidth)
          .length;
      return Shortage(
        wanted: size,
        available: range.length,
        availableWithReuse: withReuse,
      );
    }
    return Shortage(
      wanted: size,
      available: range.length,
      availableWithReuse: range.length,
    );
  }

  final picked = <String, Puzzle>{};
  // Targeted: an even share per weak theme.
  if (targeted > 0) {
    final per = (targeted / weak.length).ceil();
    for (final t in weak) {
      final c = [
        for (final p in range)
          if (p.themes.contains(t) && !picked.containsKey(p.id)) p,
      ]..shuffle(rng);
      for (final p in c.take(per)) {
        if (picked.length >= targeted) break;
        picked[p.id] = p;
      }
    }
  }
  final targetedCount = picked.length;
  // General: the natural mix of the rating range, but no main theme above
  // about 12% (at least 2 each), so the collection stays varied without
  // over-weighting rare patterns.
  final cap = math.max(2, (size * 0.12).ceil());
  final perTheme = <String, int>{
    for (final p in picked.values) p.primaryTheme: 0,
  };
  for (final p in picked.values) {
    perTheme[p.primaryTheme] = perTheme[p.primaryTheme]! + 1;
  }
  final rest = [
    for (final p in range)
      if (!picked.containsKey(p.id)) p,
  ]..shuffle(rng);
  for (final relax in [false, true]) {
    for (final p in rest) {
      if (picked.length >= size) break;
      if (picked.containsKey(p.id)) continue;
      final n = perTheme[p.primaryTheme] ?? 0;
      if (!relax && n >= cap) continue;
      picked[p.id] = p;
      perTheme[p.primaryTheme] = n + 1;
    }
  }
  return CollectionPlan(
    puzzles: picked.values.toList(),
    center: center,
    halfWidth: half,
    general: picked.length - targetedCount,
    targeted: targetedCount,
    targetThemes: weak,
    reusesOldPuzzles: allowReuse && picked.keys.any(exclude.contains),
  );
}

/// The order of a cycle: difficulty thirds interleaved (so the cycle is
/// neither easy-to-hard nor clumped) and no two neighbours sharing a
/// primary theme where it can be avoided. Deterministic for a [seed].
List<String> cycleOrder(List<Puzzle> puzzles, int seed) {
  final rng = math.Random(seed);
  final sorted = [...puzzles]..sort((a, b) => a.rating.compareTo(b.rating));
  final third = (sorted.length / 3).ceil();
  final bands = [
    for (var i = 0; i < sorted.length; i += third)
      sorted.sublist(i, math.min(i + third, sorted.length))..shuffle(rng),
  ];
  final pattern = [...List.generate(bands.length, (i) => i)]..shuffle(rng);
  final out = <Puzzle>[];
  while (bands.any((b) => b.isNotEmpty)) {
    for (final i in pattern) {
      if (bands[i].isNotEmpty) out.add(bands[i].removeLast());
    }
  }
  // Break up neighbours with the same primary theme.
  for (var i = 1; i < out.length; i++) {
    if (out[i].primaryTheme != out[i - 1].primaryTheme) continue;
    for (var j = i + 1; j < out.length; j++) {
      // out[j] moves to i (next to i-1); out[i] moves to j.
      final fitsHere = out[j].primaryTheme != out[i - 1].primaryTheme;
      final left = j - 1 == i ? out[j] : out[j - 1];
      final fitsThere =
          out[i].primaryTheme != left.primaryTheme &&
          (j + 1 >= out.length ||
              out[i].primaryTheme != out[j + 1].primaryTheme);
      if (fitsHere && fitsThere) {
        final t = out[i];
        out[i] = out[j];
        out[j] = t;
        break;
      }
    }
  }
  return [for (final p in out) p.id];
}
