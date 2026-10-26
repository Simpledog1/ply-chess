import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ply/engine/engine_service.dart';
import 'package:ply/main.dart';
import 'package:ply/storage/game_store.dart';
import 'package:ply/storage/settings.dart';
import 'package:ply/ui/analysis_controller.dart';
import 'package:ply/ui/board/chess_board.dart';
import 'package:ply/ui/services.dart';

void main() {
  late Directory dir;
  late Services services;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('ply_app');
    final store = GameStore(dir);
    final settings = Settings(dir);
    final engine = EngineService();
    services = Services(
      store: store,
      settings: settings,
      engine: engine,
      analysis: AnalysisController(
        engine: engine,
        store: store,
        settings: settings,
      ),
      tab: ValueNotifier(0),
      child: const PlyApp(),
    );
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(services);
    await tester.pump();
  }

  /// Taps the centre of [square] (e.g. 'e2') on a white-oriented board.
  Future<void> tapSquare(WidgetTester tester, String square) async {
    final rect = tester.getRect(find.byType(ChessBoard));
    final sq = rect.width / 8;
    final file = square.codeUnitAt(0) - 'a'.codeUnitAt(0);
    final rank = int.parse(square[1]) - 1;
    await tester.tapAt(
      rect.topLeft + Offset(file * sq + sq / 2, (7 - rank) * sq + sq / 2),
    );
    await tester.pump();
  }

  testWidgets('starts on Analyze with a full board and all four sections', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.byType(ChessBoard), findsOneWidget);
    expect(find.byType(PieceImage), findsNWidgets(32));
    for (final label in ['Analyze', 'Games', 'Insights', 'Settings']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('tap-to-move plays moves and keeps the move list in sync', (
    tester,
  ) async {
    await pumpApp(tester);
    await tapSquare(tester, 'e2');
    await tapSquare(tester, 'e4');
    await tapSquare(tester, 'e7');
    await tapSquare(tester, 'e5');
    expect(services.analysis.game.plies.map((p) => p.san), ['e4', 'e5']);
    // The move list sits below the load card; scroll to it like a user would.
    await tester.scrollUntilVisible(
      find.text('e4'),
      120,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('e4'), findsOneWidget);
    expect(find.text('e5'), findsOneWidget);

    // Illegal target: nothing happens.
    await tapSquare(tester, 'g1');
    await tapSquare(tester, 'g4');
    expect(services.analysis.game.length, 2);

    await tester.tap(find.byTooltip('Previous move'));
    await tester.pump();
    expect(services.analysis.ply, 1);
    expect(
      services.analysis.position.fen,
      services.analysis.game.plies[0].after.fen,
    );
    await tester.tap(find.byTooltip('Last move'));
    await tester.pump();
    expect(services.analysis.ply, 2);
  });

  testWidgets('empty Games and Insights tabs explain what to do', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('Games'));
    await tester.pump();
    expect(find.text('No saved games yet'), findsOneWidget);
    await tester.tap(find.text('Insights'));
    await tester.pump();
    expect(find.text('No reviewed games yet'), findsOneWidget);
  });
}
