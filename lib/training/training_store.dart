import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'puzzle.dart';
import 'puzzle_solver.dart';

/// Where the player's chess rating comes from. Ratings from different
/// sources are not interchangeable.
enum RatingSource {
  lichess('Lichess'),
  chessCom('Chess.com'),
  fide('FIDE'),
  other('Other'),
  none('I don\'t know my rating');

  const RatingSource(this.label);
  final String label;
}

/// One try at one puzzle. Never edited after it is recorded.
class Attempt {
  Attempt({
    required this.puzzleId,
    required this.rating,
    required this.themes,
    required this.startedAt,
    required this.completedAt,
    required this.elapsedMs,
    required this.solved,
    required this.firstTryCorrect,
    required this.wrongMoves,
    required this.hintLevel,
    this.skipped = false,
    this.tried = const [],
  });

  final String puzzleId;

  /// The puzzle's rating and themes at the time (kept for statistics).
  final int rating;
  final List<String> themes;
  final DateTime startedAt;
  final DateTime completedAt;
  final int elapsedMs;

  /// Solved in the end (after retries, without the solution being shown).
  final bool solved;

  /// Solved with no wrong move and no hint.
  final bool firstTryCorrect;
  final int wrongMoves;

  /// Highest hint level used (0 = none).
  final int hintLevel;

  /// Skipped (abandoned) by the player.
  final bool skipped;

  /// The player's moves (UCI), right and wrong.
  final List<String> tried;

  bool get failed => !solved && !skipped;

  Map<String, dynamic> toJson() => {
    'p': puzzleId,
    'r': rating,
    'th': themes,
    'start': startedAt.toIso8601String(),
    'end': completedAt.toIso8601String(),
    'ms': elapsedMs,
    'ok': solved,
    'first': firstTryCorrect,
    'wrong': wrongMoves,
    'hint': hintLevel,
    if (skipped) 'skip': true,
    'tried': tried,
  };

  factory Attempt.fromJson(Map<String, dynamic> j) => Attempt(
    puzzleId: j['p'] as String,
    rating: j['r'] as int,
    themes: (j['th'] as List).cast<String>(),
    startedAt: DateTime.parse(j['start'] as String),
    completedAt: DateTime.parse(j['end'] as String),
    elapsedMs: j['ms'] as int,
    solved: j['ok'] as bool,
    firstTryCorrect: j['first'] as bool,
    wrongMoves: j['wrong'] as int,
    hintLevel: j['hint'] as int,
    skipped: j['skip'] as bool? ?? false,
    tried: (j['tried'] as List? ?? const []).cast<String>(),
  );
}

class TrainingProfile {
  TrainingProfile({
    required this.ratingSource,
    this.chessRating,
    required this.estimate,
    required this.deviation,
    this.preferredSize = 100,
    this.wrongMove = WrongMoveBehavior.retry,
    this.hintsEnabled = true,
    List<Attempt>? calibration,
    this.calibrated = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : calibration = calibration ?? [],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  RatingSource ratingSource;
  int? chessRating;

  /// Estimated puzzle-solving rating (Lichess puzzle scale) and its
  /// uncertainty (rating deviation): smaller means more confident.
  double estimate;
  double deviation;

  int preferredSize;
  WrongMoveBehavior wrongMove;
  bool hintsEnabled;

  /// Calibration puzzles solved before the first collection.
  final List<Attempt> calibration;
  bool calibrated;
  final DateTime createdAt;
  DateTime updatedAt;

  Map<String, dynamic> toJson() => {
    'source': ratingSource.name,
    if (chessRating != null) 'rating': chessRating,
    'estimate': estimate,
    'deviation': deviation,
    'size': preferredSize,
    'wrongMove': wrongMove.name,
    'hints': hintsEnabled,
    'calibration': [for (final a in calibration) a.toJson()],
    'calibrated': calibrated,
    'created': createdAt.toIso8601String(),
    'updated': updatedAt.toIso8601String(),
  };

  factory TrainingProfile.fromJson(Map<String, dynamic> j) => TrainingProfile(
    ratingSource: RatingSource.values.byName(j['source'] as String),
    chessRating: j['rating'] as int?,
    estimate: (j['estimate'] as num).toDouble(),
    deviation: (j['deviation'] as num).toDouble(),
    preferredSize: j['size'] as int? ?? 100,
    wrongMove: WrongMoveBehavior.values.byName(
      j['wrongMove'] as String? ?? 'retry',
    ),
    hintsEnabled: j['hints'] as bool? ?? true,
    calibration: [
      for (final a in j['calibration'] as List? ?? const [])
        Attempt.fromJson(a as Map<String, dynamic>),
    ],
    calibrated: j['calibrated'] as bool? ?? false,
    createdAt: DateTime.parse(j['created'] as String),
    updatedAt: DateTime.parse(j['updated'] as String),
  );
}

enum CycleStatus { active, completed }

/// One pass through a collection, in its own saved order.
class TrainingCycle {
  TrainingCycle({
    required this.number,
    required this.seed,
    required this.order,
    this.status = CycleStatus.active,
    DateTime? startedAt,
    this.completedAt,
    List<Attempt>? attempts,
  }) : startedAt = startedAt ?? DateTime.now(),
       attempts = attempts ?? [];

  final int number;

  /// Seed the [order] was shuffled with (kept for reference).
  final int seed;

  /// Puzzle ids in the order they are played in this cycle.
  final List<String> order;
  CycleStatus status;
  final DateTime startedAt;
  DateTime? completedAt;

  /// One attempt per puzzle, appended in [order].
  final List<Attempt> attempts;

  int get done => attempts.length;
  int get remaining => order.length - attempts.length;
  String? get nextPuzzleId => done < order.length ? order[done] : null;

  Map<String, dynamic> toJson() => {
    'n': number,
    'seed': seed,
    'order': order,
    'status': status.name,
    'start': startedAt.toIso8601String(),
    if (completedAt != null) 'end': completedAt!.toIso8601String(),
    'attempts': [for (final a in attempts) a.toJson()],
  };

  factory TrainingCycle.fromJson(Map<String, dynamic> j) => TrainingCycle(
    number: j['n'] as int,
    seed: j['seed'] as int,
    order: (j['order'] as List).cast<String>(),
    status: CycleStatus.values.byName(j['status'] as String),
    startedAt: DateTime.parse(j['start'] as String),
    completedAt: j['end'] == null ? null : DateTime.parse(j['end'] as String),
    attempts: [
      for (final a in j['attempts'] as List)
        Attempt.fromJson(a as Map<String, dynamic>),
    ],
  );
}

enum CollectionStatus { active, completed, abandoned }

/// A fixed set of puzzles trained over [plannedCycles] cycles. Its
/// membership never changes; it keeps a copy of every puzzle so its history
/// stays readable whatever happens to the catalogue.
class TrainingCollection {
  TrainingCollection({
    required this.id,
    required this.number,
    required this.puzzles,
    required this.targetRating,
    this.plannedCycles = 3,
    this.status = CollectionStatus.active,
    Map<String, dynamic>? meta,
    DateTime? createdAt,
    this.completedAt,
    List<TrainingCycle>? cycles,
  }) : meta = meta ?? {},
       createdAt = createdAt ?? DateTime.now(),
       cycles = cycles ?? [] {
    _check();
  }

  final String id;
  final int number;
  final List<Puzzle> puzzles;
  final int targetRating;
  final int plannedCycles;
  CollectionStatus status;

  /// How the collection was chosen (general / targeted counts, themes,
  /// the reason for the difficulty), for display.
  final Map<String, dynamic> meta;
  final DateTime createdAt;
  DateTime? completedAt;
  final List<TrainingCycle> cycles;

  int get size => puzzles.length;
  Iterable<String> get puzzleIds => puzzles.map((p) => p.id);

  Puzzle? puzzle(String id) {
    for (final p in puzzles) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// The cycle being played, if any.
  TrainingCycle? get currentCycle {
    for (final c in cycles) {
      if (c.status == CycleStatus.active) return c;
    }
    return null;
  }

  TrainingCycle? cycle(int n) {
    for (final c in cycles) {
      if (c.number == n) return c;
    }
    return null;
  }

  bool get allCyclesDone =>
      cycles.length == plannedCycles &&
      cycles.every((c) => c.status == CycleStatus.completed);

  /// Invariants: unique puzzles, cycle numbers 1..n without repeats, every
  /// cycle a permutation of the membership, attempts following the order.
  void _check() {
    final ids = puzzles.map((p) => p.id).toSet();
    if (ids.length != puzzles.length) {
      throw const FormatException('Duplicate puzzle in collection');
    }
    final seen = <int>{};
    for (final c in cycles) {
      if (c.number < 1 || c.number > plannedCycles || !seen.add(c.number)) {
        throw FormatException('Bad cycle number ${c.number}');
      }
      if (c.order.length != ids.length || !ids.containsAll(c.order)) {
        throw FormatException('Cycle ${c.number} order does not match');
      }
      for (var i = 0; i < c.attempts.length; i++) {
        if (c.attempts[i].puzzleId != c.order[i]) {
          throw FormatException('Cycle ${c.number} attempts out of order');
        }
      }
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'number': number,
    'targetRating': targetRating,
    'cycles_planned': plannedCycles,
    'status': status.name,
    'meta': meta,
    'created': createdAt.toIso8601String(),
    if (completedAt != null) 'completed': completedAt!.toIso8601String(),
    'puzzles': [for (final p in puzzles) p.toJson()],
    'cycles': [for (final c in cycles) c.toJson()],
  };

  factory TrainingCollection.fromJson(Map<String, dynamic> j) =>
      TrainingCollection(
        id: j['id'] as String,
        number: j['number'] as int,
        targetRating: j['targetRating'] as int,
        plannedCycles: j['cycles_planned'] as int? ?? 3,
        status: CollectionStatus.values.byName(j['status'] as String),
        meta: (j['meta'] as Map?)?.cast<String, dynamic>(),
        createdAt: DateTime.parse(j['created'] as String),
        completedAt: j['completed'] == null
            ? null
            : DateTime.parse(j['completed'] as String),
        puzzles: [
          for (final p in j['puzzles'] as List)
            Puzzle.fromJson(p as Map<String, dynamic>),
        ],
        cycles: [
          for (final c in j['cycles'] as List)
            TrainingCycle.fromJson(c as Map<String, dynamic>),
        ],
      );
}

/// The player's training profile, collections, cycles and attempts, kept
/// in `training.json` (separate from settings and game history). Every
/// change is one atomic write: a temp file renamed into place, so an
/// interrupted write leaves the previous state intact.
class TrainingStore extends ChangeNotifier {
  TrainingStore(this.dir);

  static const schemaVersion = 1;

  final Directory dir;
  TrainingProfile? profile;
  final collections = <TrainingCollection>[];
  String? loadError;

  File get _file => File('${dir.path}/training.json');

  TrainingCollection? get active {
    for (final c in collections) {
      if (c.status == CollectionStatus.active) return c;
    }
    return null;
  }

  /// Ids of every puzzle used in a collection so far.
  Set<String> get usedPuzzleIds => {
    for (final c in collections) ...c.puzzleIds,
  };

  Future<void> load() async {
    if (!await _file.exists()) return;
    try {
      final j = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      final m = _migrate(j);
      profile = m['profile'] == null
          ? null
          : TrainingProfile.fromJson(m['profile'] as Map<String, dynamic>);
      collections
        ..clear()
        ..addAll([
          for (final c in m['collections'] as List)
            TrainingCollection.fromJson(c as Map<String, dynamic>),
        ]);
    } catch (e) {
      // Keep the unreadable file instead of overwriting it on the next save.
      final backup =
          '${_file.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}';
      await _file.rename(backup);
      profile = null;
      collections.clear();
      loadError = 'Training data could not be read and was moved to $backup';
    }
    notifyListeners();
  }

  /// Upgrades older file versions. Version 1 is the first.
  static Map<String, dynamic> _migrate(Map<String, dynamic> j) {
    final v = j['version'] as int? ?? 1;
    if (v > schemaVersion) {
      throw FormatException('Training data is from a newer Ply (v$v)');
    }
    return j;
  }

  Future<void> _queue = Future.value();

  /// Saves run one at a time (overlapping writes would race on the temp
  /// file); each writes the state as it is when it runs.
  Future<void> _save() {
    final next = _queue.then((_) => _write());
    _queue = next.catchError((Object _) {});
    return next;
  }

  Future<void> _write() async {
    await dir.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({
        'version': schemaVersion,
        'profile': profile?.toJson(),
        'collections': [for (final c in collections) c.toJson()],
      }),
      flush: true,
    );
    await tmp.rename(_file.path);
  }

  Future<void> saveProfile(TrainingProfile p) async {
    p.updatedAt = DateTime.now();
    profile = p;
    notifyListeners();
    await _save();
  }

  /// Adds a new collection. Only one can be active at a time.
  Future<void> addCollection(TrainingCollection c) async {
    if (active != null) {
      throw StateError('Finish or abandon the active collection first');
    }
    if (collections.any((x) => x.id == c.id)) {
      throw StateError('Duplicate collection id');
    }
    collections.add(c);
    notifyListeners();
    await _save();
  }

  /// Appends [a] to the active cycle of [c]; it must be the cycle's next
  /// puzzle. Completes the cycle (and, after the last cycle, the
  /// collection) when its final puzzle is recorded.
  Future<void> recordAttempt(TrainingCollection c, Attempt a) async {
    final cycle = c.currentCycle;
    if (cycle == null || cycle.nextPuzzleId != a.puzzleId) {
      throw StateError('Not the next puzzle of the active cycle');
    }
    cycle.attempts.add(a);
    if (cycle.remaining == 0) {
      cycle.status = CycleStatus.completed;
      cycle.completedAt = a.completedAt;
      if (c.allCyclesDone) {
        c.status = CollectionStatus.completed;
        c.completedAt = a.completedAt;
      }
    }
    notifyListeners();
    await _save();
  }

  /// Starts the next cycle of [c] with [order] (same membership).
  Future<TrainingCycle> startCycle(
    TrainingCollection c,
    List<String> order,
    int seed,
  ) async {
    if (c.status != CollectionStatus.active || c.currentCycle != null) {
      throw StateError('A cycle is already running or the collection ended');
    }
    final n = c.cycles.length + 1;
    if (n > c.plannedCycles) throw StateError('All cycles are done');
    final ids = c.puzzleIds.toSet();
    if (order.length != ids.length || !ids.containsAll(order)) {
      throw StateError('Cycle order must use the same puzzles');
    }
    final cycle = TrainingCycle(number: n, seed: seed, order: order);
    c.cycles.add(cycle);
    notifyListeners();
    await _save();
    return cycle;
  }

  Future<void> abandon(TrainingCollection c) async {
    c.status = CollectionStatus.abandoned;
    c.completedAt = DateTime.now();
    notifyListeners();
    await _save();
  }

  /// Deletes the profile and every collection.
  Future<void> deleteAll() async {
    profile = null;
    collections.clear();
    notifyListeners();
    if (await _file.exists()) await _file.delete();
  }
}
