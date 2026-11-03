import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dartchess/dartchess.dart' show Move, Position;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show SystemSound, SystemSoundType;

import '../online/online_games.dart';
import 'puzzle.dart';
import 'puzzle_catalogue.dart';
import 'puzzle_solver.dart';
import 'recommender.dart';
import 'training_stats.dart';
import 'training_store.dart';

enum SessionKind { calibration, collection }

/// The puzzle on the board right now.
class PuzzleSession {
  PuzzleSession(this.kind, this.solver, this.number, this.total)
    : startedAt = DateTime.now(),
      clock = Stopwatch()..start();

  final SessionKind kind;
  final PuzzleSolver solver;

  /// 1-based position in the cycle (or calibration) and its length.
  final int number;
  final int total;
  final DateTime startedAt;
  final Stopwatch clock;

  /// The latest feedback line ("Correct", "Incorrect move", a hint...).
  String? message;
  PuzzleHint? hint;

  /// How the last move went, for the board's colours and animation.
  /// [feedbackId] changes with every move, so animations replay.
  MoveFeedback feedback = MoveFeedback.none;
  int feedbackId = 0;

  /// What the board shows instead of the solver's position for a moment:
  /// a wrong move before it is taken back, or a step of the solution.
  Position? shownPosition;
  String? shownMove;

  /// Arrow for the next solution move while the solution is replayed.
  String? solutionArrow;

  /// Feedback is playing: board and buttons ignore input until it ends.
  bool busy = false;

  /// The recorded attempt once the puzzle is over.
  Attempt? result;

  Puzzle get puzzle => solver.puzzle;
  bool get over => result != null;
  Position get boardPosition => shownPosition ?? solver.position;
  String? get boardMove => shownMove ?? solver.lastMove;
}

enum MoveFeedback {
  none,

  /// The player's move was right; the reply follows.
  correct,

  /// The player's move was wrong (shown, then taken back or answered).
  wrong,

  /// The puzzle is solved.
  solved,

  /// The solution is being shown.
  solution,
}

/// Progress of a puzzle download.
class DownloadProgress {
  const DownloadProgress(this.fetched, this.wanted);
  final int fetched, wanted;
}

/// Glue between the training screens and the catalogue, store, solver and
/// recommender. The rules themselves live in those files.
class TrainingController extends ChangeNotifier {
  TrainingController({
    required this.catalogue,
    required this.store,
    HttpGet? httpGet,
    this.config = const RecommenderConfig(),
    this.replyDelay = const Duration(milliseconds: 450),
    this.wrongDelay = const Duration(milliseconds: 900),
    this.stepDelay = const Duration(milliseconds: 700),
  }) : _get = httpGet ?? defaultHttpGet {
    store.addListener(notifyListeners);
    catalogue.addListener(notifyListeners);
  }

  final PuzzleCatalogue catalogue;
  final TrainingStore store;
  final RecommenderConfig config;

  /// Pause before the opponent's reply, how long a wrong move stays on the
  /// board, and the pace of a replayed solution.
  final Duration replyDelay;
  final Duration wrongDelay;
  final Duration stepDelay;
  final HttpGet _get;

  PuzzleSession? session;
  Timer? _reply;

  /// Runs [f] for session [s] after [d], unless the puzzle changed.
  void _later(PuzzleSession s, Duration d, VoidCallback f) {
    _reply?.cancel();
    _reply = Timer(d, () {
      if (!identical(session, s)) return;
      f();
      notifyListeners();
    });
  }

  void _sound(SystemSoundType t) {
    if (profile?.sounds ?? false) SystemSound.play(t);
  }

  TrainingProfile? get profile => store.profile;
  TrainingCollection? get active => store.active;
  late final TrainingStats stats = TrainingStats(store);

  // --- profile and calibration ---------------------------------------------

  Future<void> createProfile({
    required RatingSource source,
    int? rating,
    int size = 100,
    WrongMoveBehavior wrongMove = WrongMoveBehavior.retry,
    bool hints = true,
  }) async {
    final (est, dev) = initialEstimate(source, rating);
    await store.saveProfile(
      TrainingProfile(
        ratingSource: source,
        chessRating: rating,
        estimate: est,
        deviation: dev,
        preferredSize: size,
        wrongMove: wrongMove,
        hintsEnabled: hints,
      ),
    );
  }

  Future<void> updatePreferences({
    int? size,
    WrongMoveBehavior? wrongMove,
    bool? hints,
    bool? sounds,
  }) async {
    final p = profile!;
    if (size != null) p.preferredSize = size;
    if (wrongMove != null) p.wrongMove = wrongMove;
    if (hints != null) p.hintsEnabled = hints;
    if (sounds != null) p.sounds = sounds;
    await store.saveProfile(p);
  }

  /// Skips calibration; the estimate stays at its starting value.
  Future<void> skipCalibration() async {
    final p = profile!..calibrated = true;
    await store.saveProfile(p);
  }

  /// Starts (or continues) calibration with the next adaptive puzzle.
  /// Returns false when calibration is complete.
  bool nextCalibration() {
    final p = profile!;
    if (p.calibration.length >= config.calibrationLength) return false;
    final puzzle = nextCalibrationPuzzle(
      catalogue.all,
      p.estimate,
      p.calibration,
    );
    if (puzzle == null) return false;
    _open(
      SessionKind.calibration,
      puzzle,
      p.calibration.length + 1,
      config.calibrationLength,
    );
    return true;
  }

  // --- collections ---------------------------------------------------------

  /// First exposures (calibration and every cycle 1) for weak themes.
  List<Attempt> get firstExposures => [
    ...?profile?.calibration,
    for (final c in store.collections) ...?c.cycle(1)?.attempts,
  ];

  /// The difficulty change suggested by the last finished collection.
  ({int delta, String reason}) get nextAdjustment {
    for (final c in store.collections.reversed) {
      if (c.status != CollectionStatus.completed) continue;
      return difficultyChange(
        AttemptSummary(c.cycle(1)!.attempts),
        config: config,
      );
    }
    return (
      delta: 0,
      reason: profile?.calibration.isNotEmpty ?? false
          ? 'Matched to your calibration results.'
          : 'Matched to your rating; Ply adjusts as you train.',
    );
  }

  /// Plans a collection: a [CollectionPlan] or a [Shortage].
  Object planCollection(int size, {bool allowReuse = false, int? seed}) {
    final adj = nextAdjustment;
    return buildCollection(
      catalogue: catalogue.all,
      size: size,
      estimate: profile!.estimate + adj.delta,
      weak: weakThemes(firstExposures, config: config),
      exclude: store.usedPuzzleIds,
      allowReuse: allowReuse,
      seed: seed ?? DateTime.now().millisecondsSinceEpoch,
      config: config,
    );
  }

  /// Saves [plan] as the new collection and starts its first cycle.
  Future<TrainingCollection> createCollection(CollectionPlan plan) async {
    final number = store.collections.length + 1;
    final seed = DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
    final c = TrainingCollection(
      id: 'c$number-$seed',
      number: number,
      puzzles: plan.puzzles,
      targetRating: plan.center,
      meta: plan.toMeta(nextAdjustment.reason),
      cycles: [
        TrainingCycle(
          number: 1,
          seed: seed,
          order: cycleOrder(plan.puzzles, seed),
        ),
      ],
    );
    await store.addCollection(c);
    return c;
  }

  /// Starts the next cycle of the active collection in a fresh order.
  Future<void> startNextCycle() async {
    final c = active!;
    final seed = DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
    await store.startCycle(c, cycleOrder(c.puzzles, seed), seed);
  }

  Future<void> abandonActive() async {
    closeSession();
    await store.abandon(active!);
  }

  /// Opens the next puzzle of the active cycle. False when the cycle (or
  /// collection) has nothing left to play.
  bool nextInCycle() {
    final c = active;
    final cycle = c?.currentCycle;
    final id = cycle?.nextPuzzleId;
    if (c == null || cycle == null || id == null) return false;
    _open(SessionKind.collection, c.puzzle(id)!, cycle.done + 1, c.size);
    return true;
  }

  // --- solving ---------------------------------------------------------------

  void _open(SessionKind kind, Puzzle p, int number, int total) {
    _reply?.cancel();
    session = PuzzleSession(
      kind,
      PuzzleSolver(p, behavior: profile?.wrongMove ?? WrongMoveBehavior.retry),
      number,
      total,
    );
    notifyListeners();
  }

  void closeSession() {
    _reply?.cancel();
    session = null;
    notifyListeners();
  }

  /// A move from the board (tap or drag). Every move gets feedback:
  /// a correct one is marked and answered; a wrong one stays on the board
  /// for [wrongDelay] marked as wrong, then is taken back (Retry) or
  /// followed by the solution (Reveal). Input is ignored meanwhile.
  MoveVerdict play(Move move) {
    final s = session;
    if (s == null || s.over || s.busy) return MoveVerdict.ignored;
    final before = s.solver.position;
    final v = s.solver.play(move);
    if (v == MoveVerdict.ignored) return v;
    s.hint = null;
    s.solutionArrow = null;
    s.feedbackId++;
    switch (v) {
      case MoveVerdict.correct:
        s.feedback = MoveFeedback.correct;
        s.message = 'Correct! Keep going.';
        s.busy = true;
        _later(s, replyDelay, () {
          s.solver.reply();
          s.feedback = MoveFeedback.none;
          s.busy = false;
        });
      case MoveVerdict.solved:
        s.feedback = MoveFeedback.solved;
        s.message = s.solver.firstTryCorrect
            ? 'Puzzle solved!'
            : 'Puzzle solved (with help).';
        _sound(SystemSoundType.click);
        _finish(s);
      case MoveVerdict.wrong:
        _showWrong(s, before, move);
        s.message = 'Incorrect move. Try again.';
        _later(s, wrongDelay, () {
          s.shownPosition = null;
          s.shownMove = null;
          s.busy = false;
        });
      case MoveVerdict.revealed:
        _showWrong(s, before, move);
        s.message = 'Incorrect move. Here is the solution.';
        _finish(s);
        _later(s, wrongDelay, () => _replaySolution(s, 0));
      case MoveVerdict.ignored:
        break;
    }
    notifyListeners();
    return v;
  }

  /// Puts the wrong [move] on the board for a moment, marked as wrong.
  void _showWrong(PuzzleSession s, Position before, Move move) {
    s.feedback = MoveFeedback.wrong;
    s.shownPosition = before.play(move);
    s.shownMove = s.solver.tried.last;
    s.busy = true;
    _sound(SystemSoundType.alert);
  }

  /// Replays the shown solution move by move from where it started, with
  /// an arrow before each move.
  void _replaySolution(PuzzleSession s, int i) {
    final steps = s.solver.revealSteps;
    s.feedback = MoveFeedback.solution;
    if (i == 0) {
      s.shownPosition = s.solver.revealFrom;
      s.shownMove = null;
      s.message = 'The solution: ${formatSolution(s.puzzle)}';
    }
    if (i >= steps.length) {
      s.shownPosition = null;
      s.shownMove = null;
      s.solutionArrow = null;
      s.busy = false;
      return;
    }
    s.busy = true;
    s.solutionArrow = steps[i].$2;
    _later(s, stepDelay, () {
      s.shownPosition = steps[i].$1;
      s.shownMove = steps[i].$2;
      s.solutionArrow = null;
      _later(s, stepDelay, () => _replaySolution(s, i + 1));
    });
  }

  void hint() {
    final s = session;
    if (s == null || s.over || s.busy || !(profile?.hintsEnabled ?? true)) {
      return;
    }
    s.hint = s.solver.hint();
    s.message = s.hint!.text;
    notifyListeners();
  }

  void resetPuzzle() {
    final s = session;
    if (s == null || s.over || s.busy) return;
    _reply?.cancel();
    s.solver.reset();
    s.hint = null;
    s.feedback = MoveFeedback.none;
    s.message = 'Back to the start position.';
    notifyListeners();
  }

  /// Gives up: the solution is shown and the puzzle counts as failed.
  void showSolution() {
    final s = session;
    if (s == null || s.over || s.busy) return;
    _reply?.cancel();
    s.solver.showSolution();
    _finish(s);
    _replaySolution(s, 0);
    notifyListeners();
  }

  /// Skips the puzzle: recorded as abandoned (never as solved).
  void skip() {
    final s = session;
    if (s == null || s.over || s.busy) return;
    _reply?.cancel();
    s.message = 'Skipped.';
    _finish(s, skipped: true);
    notifyListeners();
  }

  void _finish(PuzzleSession s, {bool skipped = false}) {
    s.clock.stop();
    final sol = s.solver;
    final a = Attempt(
      puzzleId: s.puzzle.id,
      rating: s.puzzle.rating,
      themes: s.puzzle.themes,
      startedAt: s.startedAt,
      completedAt: DateTime.now(),
      elapsedMs: s.clock.elapsedMilliseconds,
      solved: sol.solved,
      firstTryCorrect: sol.firstTryCorrect,
      wrongMoves: sol.wrongMoves,
      hintLevel: sol.hintLevel,
      skipped: skipped,
      tried: List.of(sol.tried),
    );
    s.result = a;
    unawaited(_record(s.kind, a));
  }

  Future<void> _record(SessionKind kind, Attempt a) async {
    final p = profile!;
    if (kind == SessionKind.calibration) {
      p.calibration.add(a);
      final (e, d) = updateEstimate(p.estimate, p.deviation, a);
      p
        ..estimate = e
        ..deviation = d;
      if (p.calibration.length >= config.calibrationLength) {
        p.calibrated = true;
      }
      await store.saveProfile(p);
      return;
    }
    final c = active!;
    final first = c.currentCycle?.number == 1;
    await store.recordAttempt(c, a);
    // Only first exposures move the estimate: later cycles test memory.
    if (first) {
      final (e, d) = updateEstimate(p.estimate, p.deviation, a);
      p
        ..estimate = e
        ..deviation = d;
      await store.saveProfile(p);
    }
  }

  // --- downloads and imports -------------------------------------------------

  bool _cancelDownload = false;
  bool downloading = false;
  DownloadProgress? progress;
  String? downloadError;

  void cancelDownload() => _cancelDownload = true;

  /// Downloads [count] puzzles from the Lichess puzzle API, [batch] at a
  /// time, cycling through [themes] ('mix' for any). Valid new puzzles
  /// are added in one write at the end (or when cancelled, the ones
  /// already fetched); a failure keeps the catalogue as it was.
  Future<ImportReport?> download({
    int count = 200,
    List<String> themes = const ['mix'],
    int batch = 50,
  }) async {
    if (downloading) return null;
    downloading = true;
    _cancelDownload = false;
    downloadError = null;
    progress = DownloadProgress(0, count);
    notifyListeners();
    final fetched = <Puzzle>[];
    var rejected = 0;
    try {
      var i = 0;
      while (fetched.length < count && !_cancelDownload) {
        final angle = themes[i++ % themes.length];
        final nb = math.min(batch, count - fetched.length);
        final uri = Uri.https('lichess.org', '/api/puzzle/batch/$angle', {
          'nb': '$nb',
        });
        final body = await _fetch(uri);
        final list =
            (jsonDecode(body) as Map<String, dynamic>)['puzzles'] as List;
        if (list.isEmpty) break;
        for (final j in list) {
          try {
            fetched.add(
              Puzzle.fromLichessApi(
                j as Map<String, dynamic>,
                importedAt: DateTime.now(),
              ),
            );
          } on FormatException {
            rejected++;
          } on TypeError {
            rejected++;
          }
        }
        progress = DownloadProgress(fetched.length, count);
        notifyListeners();
      }
      final report = await catalogue.addAll(
        fetched,
        source: 'Lichess puzzle API (${themes.join(', ')})',
      );
      return ImportReport(
        added: report.added,
        duplicates: report.duplicates,
        rejected: report.rejected + rejected,
        reasons: report.reasons,
      );
    } on OnlineException catch (e) {
      downloadError = e.message;
    } on FormatException {
      downloadError = 'Lichess sent an unexpected answer';
    } finally {
      downloading = false;
      notifyListeners();
    }
    return null;
  }

  Future<String> _fetch(Uri uri) async {
    final HttpReply r;
    try {
      r = await _get(uri, 'application/json');
    } on TimeoutException {
      throw const OnlineException('Lichess took too long to answer');
    } on SocketException {
      throw const OnlineException('No internet connection');
    } on HandshakeException {
      throw const OnlineException('Secure connection failed');
    } on HttpException {
      throw const OnlineException('The connection was interrupted');
    }
    return switch (r.status) {
      200 => r.body,
      429 => throw const OnlineException(
        'Lichess is rate-limiting requests; wait a minute and try again',
      ),
      >= 500 => throw const OnlineException(
        'Lichess is having problems right now',
      ),
      _ => throw OnlineException('Lichess returned an error (${r.status})'),
    };
  }

  /// Imports a Lichess puzzle CSV (decompressed) from [path], reading it
  /// line by line and keeping a random sample of at most [max] valid
  /// puzzles, so even the full database fits in memory.
  Future<ImportReport> importCsv(String path, {int max = 20000}) async {
    final rng = math.Random();
    final sample = <Puzzle>[];
    var seen = 0, rejected = 0;
    final lines = File(path)
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (line.isEmpty || line.startsWith('PuzzleId')) continue;
      final Puzzle p;
      try {
        p = Puzzle.fromLichessCsv(line, importedAt: DateTime.now());
      } on FormatException {
        rejected++;
        continue;
      }
      if (validatePuzzle(p) != null) {
        rejected++;
        continue;
      }
      seen++;
      if (sample.length < max) {
        sample.add(p);
      } else {
        final j = rng.nextInt(seen);
        if (j < max) sample[j] = p;
      }
    }
    final r = await catalogue.addAll(
      sample,
      source: 'CSV file ${path.split(RegExp(r'[\\/]')).last}',
    );
    return ImportReport(
      added: r.added,
      duplicates: r.duplicates,
      rejected: r.rejected + rejected,
      reasons: r.reasons,
    );
  }

  @override
  void dispose() {
    _reply?.cancel();
    store.removeListener(notifyListeners);
    catalogue.removeListener(notifyListeners);
    super.dispose();
  }
}
