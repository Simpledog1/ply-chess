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
    final s = training.session!;
    final board = tester.getRect(find.byType(ChessBoard));
    Future<void> tapSquare(String sq) async {
      final sz = board.width / 8;
      var file = sq.codeUnitAt(0) - 97, rank = int.parse(sq[1]) - 1;
      if (s.solver.solver == Side.black) {
        file = 7 - file;
        rank = 7 - rank;
      }
      // Through the real clock: the move may save the attempt to disk.
      await act(
        () => tester.tapAt(
          board.topLeft + Offset(file * sz + sz / 2, (7 - rank) * sz + sz / 2),
        ),
      );
    }

    // Play the solution by tapping squares (promotions via the controller).
    while (!s.over) {
      final uci = s.puzzle.moves[s.solver.index];
      if (uci.length == 5) {
        training.play(Move.parse(uci)!);
      } else {
        await tapSquare(uci.substring(0, 2));
        await tapSquare(uci.substring(2, 4));
      }
      await act(() async {});
    }
    expect(s.result!.firstTryCorrect, isTrue);
    expect(find.text('Solved first try'), findsOneWidget);
    expect(find.textContaining('Solution: '), findsOneWidget);
    expect(c.currentCycle!.done, 1);

    // 4. Next puzzle, then pause: the dashboard offers to continue.
    await tester.tap(find.text('Next puzzle'));
    await tester.pump();
    expect(find.textContaining('Puzzle 2 of 50'), findsOneWidget);
    await tester.tap(find.textContaining('Pause'));
    await tester.pump();
    expect(find.text('Continue training'), findsOneWidget);
    expect(find.text('100%'), findsWidgets); // first-try accuracy so far
    expect(find.text('Collection history'), findsOneWidget);
    await tester.tap(find.text('Continue training'));
    await tester.pump();
    expect(
      training.session!.puzzle.id,
      c.currentCycle!.order[1],
    ); // same puzzle 2
    // Let the last save finish before the folder is deleted.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
  });
}
