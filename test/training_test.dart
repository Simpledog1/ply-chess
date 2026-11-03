// Woodpecker training: collections, cycles, persistence, statistics,
// recommendations, calibration and downloads.
import 'dart:convert';
import 'dart:io';

import 'package:dartchess/dartchess.dart' hide File;
import 'package:flutter_test/flutter_test.dart';
import 'package:ply/online/online_games.dart';
import 'package:ply/training/puzzle.dart';
import 'package:ply/training/puzzle_catalogue.dart';
import 'package:ply/training/puzzle_solver.dart';
import 'package:ply/training/recommender.dart';
import 'package:ply/training/training_controller.dart';
import 'package:ply/training/training_stats.dart';
import 'package:ply/training/training_store.dart';

final starterCsv = File('assets/puzzles/lichess_starter.csv')
    .readAsStringSync();
final pack = parsePuzzleCsv(starterCsv).puzzles;

Attempt attempt(
  Puzzle p, {
  bool first = true,
  bool solved = true,
  int ms = 20000,
  bool skipped = false,
}) => Attempt(
  puzzleId: p.id,
  rating: p.rating,
  themes: p.themes,
  startedAt: DateTime(2026, 11, 2),
  completedAt: DateTime(2026, 11, 2),
  elapsedMs: ms,
  solved: solved,
  firstTryCorrect: first && solved,
  wrongMoves: first ? 0 : 1,
  hintLevel: 0,
  skipped: skipped,
);

CollectionPlan plan(
  int size, {
  double est = 1500,
  List<String> weak = const [],
}) => buildCollection(
  catalogue: pack,
  size: size,
  estimate: est,
  weak: weak,
  seed: 7,
) as CollectionPlan;

/// A legal move in the session's position that is neither the expected
/// move nor a checkmate (so the solver must reject it).
NormalMove wrongMoveIn(PuzzleSession s) {
  final pos = s.solver.position;
  final expected = s.puzzle.moves[s.solver.index].substring(0, 4);
  for (final e in pos.legalMoves.entries) {
    for (final to in e.value.squares) {
      final m = NormalMove(from: e.key, to: to);
      if ('${e.key.name}${to.name}' != expected &&
          pos.board.pieceAt(to)?.color != pos.turn && // not castling form
          !pos.play(m).isCheckmate) {
        return m;
      }
    }
  }
  throw StateError('No wrong move available');
}

/// Plays the solver's own solution through the controller.
Future<void> solve(TrainingController c) async {
  final s = c.session!;
  while (!s.over) {
    final uci = s.puzzle.moves[s.solver.index];
    c.play(Move.parse(uci)!);
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  await Future<void>.delayed(const Duration(milliseconds: 5));
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('ply_train'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('collections', () {
    for (final size in [50, 100, 200]) {
      test('$size puzzles: exact size, unique, mixed themes', () {
        final p = plan(size);
        expect(p.puzzles, hasLength(size));
        expect(p.puzzles.map((x) => x.id).toSet(), hasLength(size));
        final themes = p.puzzles.map((x) => x.primaryTheme).toSet();
        expect(themes.length, greaterThanOrEqualTo(size >= 100 ? 15 : 10));
        for (final x in p.puzzles) {
          expect((x.rating - p.center).abs(), lessThanOrEqualTo(p.halfWidth));
        }
      });
    }

    test('70% general and 30% targeted at weak themes', () {
      final p = plan(100, weak: ['fork', 'pin']);
      expect(p.targeted, 30);
      expect(p.general, 70);
      final hits = p.puzzles.where(
        (x) => x.themes.contains('fork') || x.themes.contains('pin'),
      );
      expect(hits.length, greaterThanOrEqualTo(30));
    });

    test('no weak themes known: no targeted share', () {
      final p = plan(50);
      expect(p.targeted, 0);
      expect(p.general, 50);
    });

    test('players at different levels get different puzzles', () {
      double mean(CollectionPlan p) =>
          p.puzzles.map((x) => x.rating).reduce((a, b) => a + b) /
          p.puzzles.length;
      final weak = plan(100, est: 900), strong = plan(100, est: 2000);
      expect(mean(strong) - mean(weak), greaterThan(800));
    });

    test('earlier collections are not repeated', () {
      final first = plan(100);
      final next = buildCollection(
        catalogue: pack,
        size: 100,
        estimate: 1500,
        exclude: first.puzzles.map((p) => p.id).toSet(),
        seed: 8,
      ) as CollectionPlan;
      expect(
        next.puzzles
            .map((p) => p.id)
            .toSet()
            .intersection(first.puzzles.map((p) => p.id).toSet()),
        isEmpty,
      );
    });

    test('too few puzzles: a shortage, never a smaller collection', () {
      final r = buildCollection(
        catalogue: pack.take(40),
        size: 100,
        estimate: 1500,
      );
      expect(r, isA<Shortage>());
      expect((r as Shortage).wanted, 100);
      expect(r.message, contains('Download more puzzles'));
    });

    test('cycle order mixes difficulty and themes, stable per seed', () {
      final p = plan(100).puzzles;
      final a = cycleOrder(p, 11), b = cycleOrder(p, 11), c = cycleOrder(p, 12);
      expect(a, b);
      expect(a, isNot(c));
      expect(a.toSet(), p.map((x) => x.id).toSet());
      final byId = {for (final x in p) x.id: x};
      var same = 0;
      for (var i = 1; i < a.length; i++) {
        if (byId[a[i]]!.primaryTheme == byId[a[i - 1]]!.primaryTheme) same++;
      }
      expect(same, lessThanOrEqualTo(3));
      final ratings = a.map((id) => byId[id]!.rating).toList();
      final sorted = [...ratings]..sort();
      expect(ratings, isNot(sorted));
      // Each quarter of the cycle has easy and hard puzzles.
      for (var q = 0; q < 4; q++) {
        final part = ratings.sublist(q * 25, q * 25 + 25)..sort();
        expect(part.last - part.first, greaterThan(150));
      }
    });
  });

  group('cycles and persistence', () {
    TrainingCollection newCollection(List<Puzzle> ps) => TrainingCollection(
      id: 'c1',
      number: 1,
      puzzles: ps,
      targetRating: 1400,
      cycles: [TrainingCycle(number: 1, seed: 1, order: cycleOrder(ps, 1))],
    );

    test(
      'three cycles over the same puzzles, resumable after restart',
      () async {
        final ps = plan(50).puzzles;
        final store = TrainingStore(dir);
        final c = newCollection(ps);
        await store.addCollection(c);
        // Half of cycle 1, then "restart".
        for (final id in c.currentCycle!.order.take(20)) {
          await store.recordAttempt(c, attempt(c.puzzle(id)!));
        }
        final reopened = TrainingStore(dir);
        await reopened.load();
        final r = reopened.active!;
        expect(r.currentCycle!.number, 1);
        expect(r.currentCycle!.done, 20);
        expect(r.currentCycle!.nextPuzzleId, c.currentCycle!.order[20]);
        expect(r.currentCycle!.order, c.currentCycle!.order);

        Future<void> finishCycle() async {
          for (
            var id = r.currentCycle?.nextPuzzleId;
            id != null;
            id = r.currentCycle?.nextPuzzleId
          ) {
            await reopened.recordAttempt(r, attempt(r.puzzle(id)!));
          }
        }

        await finishCycle();
        expect(r.cycle(1)!.status, CycleStatus.completed);
        expect(r.status, CollectionStatus.active);
        for (final n in [2, 3]) {
          await reopened.startCycle(r, cycleOrder(r.puzzles, n), n);
          expect(r.currentCycle!.order.toSet(), ps.map((p) => p.id).toSet());
          await finishCycle();
        }
        expect(r.status, CollectionStatus.completed);
        expect(r.cycles.map((c) => c.attempts.length), [50, 50, 50]);
        expect(
          () => reopened.startCycle(r, cycleOrder(r.puzzles, 4), 4),
          throwsStateError,
        );
      },
    );

    test('back-to-back saves do not collide', () async {
      final store = TrainingStore(dir);
      final c = newCollection(plan(50).puzzles);
      await store.addCollection(c);
      await Future.wait([
        for (final id in c.currentCycle!.order.take(10))
          store.recordAttempt(c, attempt(c.puzzle(id)!)),
      ]);
      final again = TrainingStore(dir);
      await again.load();
      expect(again.active!.currentCycle!.done, 10);
    });

    test('attempts must follow the cycle order', () async {
      final ps = plan(50).puzzles;
      final store = TrainingStore(dir);
      final c = newCollection(ps);
      await store.addCollection(c);
      final wrong = c.puzzle(c.currentCycle!.order[5])!;
      expect(() => store.recordAttempt(c, attempt(wrong)), throwsStateError);
    });

    test('a cycle cannot change the membership', () async {
      final ps = plan(50).puzzles;
      final store = TrainingStore(dir);
      final c = newCollection(ps);
      await store.addCollection(c);
      for (final id in c.currentCycle!.order) {
        await store.recordAttempt(c, attempt(c.puzzle(id)!));
      }
      final other = [...c.cycle(1)!.order]..[0] = pack.last.id;
      expect(() => store.startCycle(c, other, 2), throwsStateError);
      expect(
        () => TrainingCollection(
          id: 'x',
          number: 2,
          puzzles: [ps[0], ps[0]],
          targetRating: 1,
        ),
        throwsFormatException,
      );
    });

    test('one active collection; abandoned ones stay in history', () async {
      final store = TrainingStore(dir);
      final c = newCollection(plan(50).puzzles);
      await store.addCollection(c);
      expect(
        () => store.addCollection(
          TrainingCollection(
            id: 'c2',
            number: 2,
            puzzles: plan(50, est: 2000).puzzles,
            targetRating: 1900,
          ),
        ),
        throwsStateError,
      );
      await store.abandon(c);
      final reopened = TrainingStore(dir);
      await reopened.load();
      expect(reopened.active, isNull);
      expect(reopened.collections.single.status, CollectionStatus.abandoned);
      expect(reopened.collections.single.size, 50);
    });

    test('unreadable or newer data is kept aside', () async {
      File('${dir.path}/training.json').writeAsStringSync('{"version": 99}');
      final store = TrainingStore(dir);
      await store.load();
      expect(store.loadError, contains('moved'));
      expect(store.profile, isNull);
      expect(
        dir.listSync().where((f) => f.path.contains('.corrupt-')),
        hasLength(1),
      );
    });
  });

  group('statistics and rules', () {
    test('accuracy: first-try, eventual, skipped separately', () {
      final ps = pack.take(4).toList();
      final s = AttemptSummary([
        attempt(ps[0]),
        attempt(ps[1], first: false),
        attempt(ps[2], solved: false, skipped: true),
        attempt(ps[3], solved: false),
      ]);
      expect(s.firstTryRate, 25);
      expect(s.solvedRate, 50);
      expect(s.skipped, 1);
      expect(s.failed, 1);
      expect(s.averageTime, const Duration(seconds: 20));
    });

    test('a theme needs a minimum sample before it is called weak', () {
      final forks = pack.where((p) => p.themes.contains('fork')).toList();
      final others = pack.where((p) => !p.themes.contains('fork')).toList();
      final few = [
        for (final p in forks.take(3)) attempt(p, solved: false),
        for (final p in others.take(20)) attempt(p),
      ];
      expect(weakThemes(few), isNot(contains('fork')));
      final many = [
        for (final p in forks.take(10)) attempt(p, solved: false),
        for (final p in others.take(20)) attempt(p),
      ];
      expect(weakThemes(many), contains('fork'));
    });

    test('difficulty changes weigh accuracy and speed together', () {
      List<Attempt> run(int good, int ms) => [
        for (final p in pack.take(good)) attempt(p, ms: ms),
        for (final p in pack.skip(good).take(50 - good))
          attempt(p, solved: false),
      ];
      expect(difficultyChange(AttemptSummary(run(45, 20000))).delta, 75);
      expect(difficultyChange(AttemptSummary(run(45, 90000))).delta, 0);
      expect(difficultyChange(AttemptSummary(run(20, 20000))).delta, -100);
      expect(difficultyChange(AttemptSummary(run(33, 20000))).delta, 0);
      // A handful of quick solves is not enough to raise difficulty.
      expect(
        difficultyChange(AttemptSummary(run(45, 20000).take(5).toList())).delta,
        0,
      );
    });

    test('estimates: starting points and calibration', () {
      expect(initialEstimate(RatingSource.none, null), (1200, 350));
      expect(initialEstimate(RatingSource.chessCom, 1000).$1, 1250);
      expect(initialEstimate(RatingSource.lichess, 1800), (1800, 250));
      var (e, d) = (1200.0, 350.0);
      for (final p in pack.where((p) => p.rating > 1500).take(12)) {
        (e, d) = updateEstimate(e, d, attempt(p));
      }
      expect(e, greaterThan(1500));
      expect(d, lessThan(200));
      expect(confidenceLabel(350), 'low');
      expect(confidenceLabel(d), isNot('low'));
    });

    test('mastery needs repeated quick first-try solves', () {
      final p = pack.first;
      const rules = MasteryRules();
      expect(rules.mastered([attempt(p)]), isFalse);
      expect(rules.mastered([attempt(p), attempt(p)]), isTrue);
      expect(rules.mastered([attempt(p), attempt(p, first: false)]), isFalse);
      expect(rules.mastered([attempt(p), attempt(p, ms: 90000)]), isFalse);
    });

    test('theme statistics count repeated success across cycles', () {
      final p = pack.firstWhere((x) => x.themes.contains('fork'));
      final a1 = attempt(p), a2 = attempt(p);
      final cycles = {a1: 1, a2: 2};
      final s = themeStats([a1, a2], cycleOf: (a) => cycles[a]!)['fork']!;
      expect(s.attempts, 2);
      expect(s.puzzles, {p.id});
      expect(s.repeatedSuccess, 1);
    });
  });

  group('controller', () {
    Future<TrainingController> open({HttpGet? get}) async {
      final catalogue = PuzzleCatalogue(dir);
      await catalogue.load(starterCsv: starterCsv);
      final store = TrainingStore(dir);
      await store.load();
      return TrainingController(
        catalogue: catalogue,
        store: store,
        httpGet: get,
        replyDelay: const Duration(milliseconds: 10),
        wrongDelay: const Duration(milliseconds: 40),
        stepDelay: const Duration(milliseconds: 5),
      );
    }

    test('calibration, a collection, and resuming after restart', () async {
      final c = await open();
      await c.createProfile(source: RatingSource.none, size: 50);
      expect(c.profile!.estimate, 1200);
      while (c.nextCalibration()) {
        await solve(c);
      }
      expect(c.profile!.calibration, hasLength(12));
      expect(c.profile!.calibrated, isTrue);
      expect(c.profile!.estimate, greaterThan(1200)); // all solved
      final p = c.planCollection(50, seed: 3) as CollectionPlan;
      final col = await c.createCollection(p);
      expect(col.cycles.single.order, hasLength(50));
      for (var i = 0; i < 3; i++) {
        expect(c.nextInCycle(), isTrue);
        await solve(c);
      }
      c.nextInCycle();
      c.skip();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(col.currentCycle!.done, 4);
      expect(col.currentCycle!.attempts.last.skipped, isTrue);
      expect(col.currentCycle!.attempts.last.solved, isFalse);
      // Restart.
      final again = await open();
      expect(again.active!.currentCycle!.done, 4);
      expect(again.nextInCycle(), isTrue);
      expect(again.session!.puzzle.id, col.currentCycle!.order[4]);
      expect(again.session!.number, 5);
    });

    test('wrong move with Retry costs first-try credit', () async {
      final c = await open();
      await c.createProfile(source: RatingSource.lichess, rating: 1500);
      c.nextCalibration();
      final s = c.session!;
      expect(c.play(wrongMoveIn(s)), MoveVerdict.wrong);
      await solve(c);
      final a = c.profile!.calibration.single;
      expect(a.solved, isTrue);
      expect(a.firstTryCorrect, isFalse);
      expect(a.wrongMoves, 1);
    });

    group('move feedback', () {
      test('Retry: the wrong move is shown, locked, then taken back', () async {
        final c = await open();
        await c.createProfile(source: RatingSource.lichess, rating: 1500);
        c.nextCalibration();
        final s = c.session!;
        final start = s.solver.position.fen;
        final wrong = wrongMoveIn(s);
        expect(c.play(wrong), MoveVerdict.wrong);
        // Shown on the board, marked wrong, input locked.
        expect(s.feedback, MoveFeedback.wrong);
        expect(s.message, 'Incorrect move. Try again.');
        expect(s.boardPosition.fen, s.solver.start.play(wrong).fen);
        expect(s.boardMove, s.solver.tried.last);
        expect(s.busy, isTrue);
        final right = Move.parse(s.puzzle.moves[1])!;
        expect(c.play(right), MoveVerdict.ignored);
        expect(s.solver.wrongMoves, 1); // the ignored move is not counted
        // Then taken back: the real position is untouched.
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(s.busy, isFalse);
        expect(s.shownPosition, isNull);
        expect(s.boardPosition.fen, start);
        // A correct retry is marked correct and continues.
        expect(c.play(right), isNot(MoveVerdict.ignored));
        expect(s.feedback, anyOf(MoveFeedback.correct, MoveFeedback.solved));
        await solve(c);
        expect(s.feedback, MoveFeedback.solved);
        expect(s.message, 'Puzzle solved (with help).');
        expect(c.profile!.calibration.single.wrongMoves, 1);
      });

      test('several wrong moves are all counted', () async {
        final c = await open();
        await c.createProfile(source: RatingSource.lichess, rating: 1500);
        c.nextCalibration();
        final s = c.session!;
        for (var i = 0; i < 3; i++) {
          expect(c.play(wrongMoveIn(s)), MoveVerdict.wrong);
          await Future<void>.delayed(const Duration(milliseconds: 80));
        }
        await solve(c);
        final a = c.profile!.calibration.single;
        expect(a.wrongMoves, 3);
        expect(a.solved, isTrue);
        expect(a.tried.length, greaterThanOrEqualTo(4));
      });

      test('first-try solve is marked solved', () async {
        final c = await open();
        await c.createProfile(source: RatingSource.lichess, rating: 1500);
        c.nextCalibration();
        await solve(c);
        expect(c.session!.feedback, MoveFeedback.solved);
        expect(c.session!.message, 'Puzzle solved!');
      });

      test('Reveal: wrong move shown, then the solution played out', () async {
        final c = await open();
        await c.createProfile(
          source: RatingSource.lichess,
          rating: 1500,
          wrongMove: WrongMoveBehavior.reveal,
        );
        c.nextCalibration();
        final s = c.session!;
        final wrong = wrongMoveIn(s);
        expect(c.play(wrong), MoveVerdict.revealed);
        expect(s.feedback, MoveFeedback.wrong);
        expect(s.message, 'Incorrect move. Here is the solution.');
        expect(s.boardPosition.fen, s.solver.start.play(wrong).fen);
        expect(s.over, isTrue); // recorded as not solved straight away
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(s.feedback, MoveFeedback.solution);
        for (var i = 0; i < 100 && s.busy; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(s.busy, isFalse);
        expect(s.shownPosition, isNull);
        expect(s.boardPosition.fen, s.solver.revealSteps.last.$1.fen);
        expect(s.message, startsWith('The solution: '));
        final a = c.profile!.calibration.single;
        expect(a.solved, isFalse);
        expect(a.firstTryCorrect, isFalse);
        expect(a.wrongMoves, 1);
      });

      test('the Solution button replays the solution', () async {
        final c = await open();
        await c.createProfile(source: RatingSource.lichess, rating: 1500);
        c.nextCalibration();
        final s = c.session!;
        c.showSolution();
        expect(s.feedback, MoveFeedback.solution);
        expect(s.boardPosition.fen, s.solver.start.fen);
        expect(s.solutionArrow, s.puzzle.moves[1]);
        for (var i = 0; i < 100 && s.busy; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(s.boardPosition.fen, s.solver.position.fen);
        expect(c.profile!.calibration.single.solved, isFalse);
      });

      test('a restart mid-puzzle starts that puzzle afresh', () async {
        final c = await open();
        await c.createProfile(source: RatingSource.lichess, rating: 1500);
        await c.skipCalibration();
        await c.createCollection(
          c.planCollection(50, seed: 4) as CollectionPlan,
        );
        c.nextInCycle();
        final first = c.session!.puzzle.id;
        c.play(wrongMoveIn(c.session!));
        c.play(wrongMoveIn(c.session!)); // ignored while the first shows
        await Future<void>.delayed(const Duration(milliseconds: 20));
        // Ply closes before the puzzle is finished.
        final again = await open();
        expect(again.active!.currentCycle!.done, 0); // nothing recorded
        again.nextInCycle();
        expect(again.session!.puzzle.id, first);
        expect(again.session!.solver.wrongMoves, 0);
        expect(
          again.session!.boardPosition.fen,
          again.session!.solver.start.fen,
        );
      });
    });

    test(
      'downloads: valid puzzles added, duplicates and errors handled',
      () async {
        final batch = File('test/fixtures/lichess_puzzle_batch.json')
            .readAsStringSync();
        var status = 200;
        final c = await open(
          get: (uri, accept) async {
            expect(uri.path, startsWith('/api/puzzle/batch/'));
            return HttpReply(status, batch);
          },
        );
        final before = c.catalogue.size;
        final r = await c.download(count: 2, themes: ['fork']);
        expect(r!.added, 2);
        expect(c.catalogue.size, before + 2);
        final again = await c.download(count: 2, themes: ['fork']);
        expect(again!.added, 0);
        expect(again.duplicates, 2);
        status = 429;
        expect(await c.download(count: 2), isNull);
        expect(c.downloadError, contains('rate-limiting'));
        expect(c.catalogue.size, before + 2);
      },
    );

    test('CSV import samples at most the requested number', () async {
      final c = await open();
      // 30 valid rows with fresh ids, plus one broken line.
      final rows = starterCsv.split('\n').skip(1).take(30).toList();
      final lines = [
        'PuzzleId,FEN,Moves,Rating',
        for (var i = 0; i < rows.length; i++)
          rows[i].replaceFirst(RegExp('^[^,]+'), 'new$i'),
        'broken line',
      ];
      final f = File('${dir.path}/sample.csv')
        ..writeAsStringSync(lines.join('\n'));
      final r = await c.importCsv(f.path, max: 10);
      expect(r.added, 10);
      expect(r.rejected, 1);
    });
  });

  test('fixture is a real API answer', () {
    final j = jsonDecode(
      File('test/fixtures/lichess_puzzle_batch.json').readAsStringSync(),
    );
    expect((j['puzzles'] as List), hasLength(2));
  });
}
