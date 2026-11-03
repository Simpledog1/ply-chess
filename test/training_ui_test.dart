// The Training screens end to end on the desktop layout: set-up, planning
// a collection, solving a puzzle on the board, pausing, and the dashboard.
import 'dart:io';

import 'package:dartchess/dartchess.dart' hide File;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ply/engine/engine_service.dart';
import 'package:ply/main.dart';
import 'package:ply/online/games_browser.dart';
import 'package:ply/storage/game_store.dart';
import 'package:ply/storage/settings.dart';
import 'package:ply/training/puzzle_catalogue.dart';
import 'package:ply/training/training_controller.dart';
import 'package:ply/training/training_store.dart';
import 'package:ply/ui/analysis_controller.dart';
import 'package:ply/ui/board/chess_board.dart';
import 'package:ply/ui/services.dart';

void main() {
  testWidgets('set up, plan a collection, solve on the board, resume', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('ply_train_ui');
    addTearDown(() => dir.deleteSync(recursive: true));
    final settings = Settings(dir);
    final store = GameStore(dir);
    final engine = EngineService();
    final catalogue = PuzzleCatalogue(dir);
    await tester.runAsync(
      () => catalogue.load(
        starterCsv: File('assets/puzzles/lichess_starter.csv')
            .readAsStringSync(),
      ),
    );
    final training = TrainingController(
      catalogue: catalogue,
      store: TrainingStore(dir),
      replyDelay: Duration.zero,
    );
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Services(
        store: store,
        settings: settings,
        engine: engine,
        analysis: AnalysisController(
          engine: engine,
          store: store,
          settings: settings,
        ),
        browser: GamesBrowser(settings: settings),
        training: training,
        tab: ValueNotifier(0),
        child: const PlyApp(),
      ),
    );
    await tester.pump();

    // Writes go to real files, which only complete outside fake time.
    Future<void> act(Future<void> Function() f) async {
      await tester.runAsync(() async {
        await f();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    // 1. The Training section: set-up with no rating.
    await tester.tap(find.text('Training'));
    await tester.pump();
    expect(find.text('Puzzle Training'), findsOneWidget);
    expect(find.text('How it works'), findsOneWidget);
    await act(() => tester.tap(find.text('Continue')));
    expect(training.profile!.estimate, 1200);

    // 2. Calibration can be skipped; then the collection preview.
    expect(find.text('Find your level'), findsOneWidget);
    await act(() => tester.tap(find.text('Skip, use my starting estimate')));
    expect(find.text('Your first collection'), findsOneWidget);
    await tester.tap(find.text('50 puzzles'));
    await tester.pump();
    expect(find.text('General'), findsOneWidget);
    expect(find.text('Targeted'), findsOneWidget);
    await act(
      () => tester.tap(find.text('Create collection and start cycle 1')),
    );
    final c = training.active!;
    expect(c.size, 50);
    expect(c.cycles.single.order, hasLength(50));

    // 3. The solving screen: board, context, timer.
    expect(find.byType(ChessBoard), findsOneWidget);
    expect(find.textContaining('Puzzle 1 of 50'), findsOneWidget);
    expect(find.text('Time'), findsOneWidget);
    final board = tester.getRect(find.byType(ChessBoard));
    Offset center(String sq) {
      final sz = board.width / 8;
      var file = sq.codeUnitAt(0) - 97, rank = int.parse(sq[1]) - 1;
      if (training.session!.solver.solver == Side.black) {
        file = 7 - file;
        rank = 7 - rank;
      }
      return board.topLeft +
          Offset(file * sz + sz / 2, (7 - rank) * sz + sz / 2);
    }

    // Through the real clock: a move may save the attempt to disk.
    Future<void> tapSquare(String sq) => act(() => tester.tapAt(center(sq)));
    Future<void> solveByTaps() async {
      final s = training.session!;
      while (!s.over) {
        final uci = s.puzzle.moves[s.solver.index];
        if (uci.length == 5) {
          await act(() async => training.play(Move.parse(uci)!));
        } else {
          await tapSquare(uci.substring(0, 2));
          await tapSquare(uci.substring(2, 4));
        }
        await act(
          () => Future<void>.delayed(const Duration(milliseconds: 600)),
        ); // the reply
      }
    }

    var s = training.session!;
    final start = s.solver.position.fen;

    // A wrong move by clicking: shown with a red cross, a message, and the
    // board locked; then the piece goes back.
    final wrong = wrongMoveIn(s);
    await tapSquare(wrong.from.name);
    await tapSquare(wrong.to.name);
    expect(find.text('Incorrect move. Try again.'), findsOneWidget);
    expect(s.solver.wrongMoves, 1);
    expect(s.boardPosition.fen, s.solver.start.play(wrong).fen);
    expect(find.byIcon(Icons.close), findsOneWidget);
    final right = s.puzzle.moves[1];
    await tapSquare(right.substring(0, 2)); // ignored while the cross shows
    await tapSquare(right.substring(2, 4));
    expect(s.solver.index, 1);
    expect(s.solver.wrongMoves, 1);
    await act(() => Future<void>.delayed(const Duration(seconds: 1)));
    expect(s.boardPosition.fen, start);
    expect(find.byIcon(Icons.close), findsNothing);

    // A wrong move by dragging: the same feedback.
    final wrong2 = wrongMoveIn(s);
    await act(
      () => tester.dragFrom(
        center(wrong2.from.name),
        center(wrong2.to.name) - center(wrong2.from.name),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250)); // message fade
    expect(s.solver.wrongMoves, 2);
    expect(find.text('Incorrect move. Try again.'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
    await act(() => Future<void>.delayed(const Duration(seconds: 1)));
    expect(s.boardPosition.fen, start);

    // The correct retry: solved, with help.
    await solveByTaps();
    expect(s.result!.solved, isTrue);
    expect(s.result!.firstTryCorrect, isFalse);
    expect(s.result!.wrongMoves, 2);
    expect(find.text('Solved with help'), findsOneWidget);
    expect(find.text('Puzzle solved (with help).'), findsOneWidget);
    expect(find.textContaining('Solution: '), findsOneWidget);
    expect(c.currentCycle!.done, 1);

    // 4. Puzzle 2, solved first try: a green tick and a clear message.
    await tester.tap(find.text('Next puzzle'));
    await tester.pump();
    expect(find.textContaining('Puzzle 2 of 50'), findsOneWidget);
    s = training.session!;
    await solveByTaps();
    expect(s.result!.firstTryCorrect, isTrue);
    expect(find.text('Solved first try'), findsOneWidget);
    expect(find.text('Puzzle solved!'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);

    // 5. Pause on puzzle 3: the dashboard offers to continue.
    await tester.tap(find.text('Next puzzle'));
    await tester.pump();
    await tester.tap(find.textContaining('Pause'));
    await tester.pump();
    expect(find.text('Continue training'), findsOneWidget);
    expect(find.text('50%'), findsWidgets); // first-try accuracy so far
    expect(find.text('Collection history'), findsOneWidget);
    await tester.tap(find.text('Continue training'));
    await tester.pump();
    expect(
      training.session!.puzzle.id,
      c.currentCycle!.order[2],
    ); // same puzzle 3
    // Let the last save finish before the folder is deleted.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
  });
}

/// A legal move that is neither the expected move, a checkmate, a
/// promotion nor written as king-takes-rook (so the solver rejects it).
NormalMove wrongMoveIn(PuzzleSession s) {
  final pos = s.solver.position;
  final expected = s.puzzle.moves[s.solver.index].substring(0, 4);
  for (final e in pos.legalMoves.entries) {
    for (final to in e.value.squares) {
      final m = NormalMove(from: e.key, to: to);
      final pawn = pos.board.pieceAt(e.key)?.role == Role.pawn;
      if ('${e.key.name}${to.name}' != expected &&
          pos.board.pieceAt(to)?.color != pos.turn &&
          !(pawn && (to.rank == Rank.first || to.rank == Rank.eighth)) &&
          !pos.play(m).isCheckmate) {
        return m;
      }
    }
  }
  throw StateError('No wrong move available');
}
