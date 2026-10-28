// End-to-end desktop flow with a fake Lichess API and a scripted engine:
// choose Lichess, enter a username, load games, open one, analyse it,
// inspect the blunder, and shut the engine down.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ply/engine/engine_service.dart';
import 'package:ply/engine/uci.dart';
import 'package:ply/main.dart';
import 'package:ply/online/games_browser.dart';
import 'package:ply/online/online_games.dart';
import 'package:ply/storage/game_store.dart';
import 'package:ply/storage/settings.dart';
import 'package:ply/ui/analysis_controller.dart';
import 'package:ply/ui/services.dart';

const pgn = '''
[Event "Rated Blitz game"]
[Site "https://lichess.org/scholar1"]
[Date "2026.10.25"]
[White "Opp"]
[Black "Ply_Tester"]
[Result "1-0"]
[UTCDate "2026.10.25"]
[UTCTime "20:00:00"]
[WhiteElo "1480"]
[BlackElo "1500"]
[TimeControl "180+2"]

1. e4 e5 2. Qh5 Nc6 3. Bc4 Nf6 4. Qxf7# 1-0''';

/// Answers searches from a per-ply script (scores relative to the side to
/// move, as UCI engines report them).
class ScriptedEngine implements EngineTransport {
  ScriptedEngine(this.script);
  final List<(String, String)> script;
  final _out = StreamController<String>.broadcast(sync: true);
  final sent = <String>[];
  int _ply = 0;

  @override
  Stream<String> get lines => _out.stream;

  @override
  void send(String c) {
    sent.add(c);
    scheduleMicrotask(() {
      if (c == 'uci') {
        _out
          ..add('id name ScriptFish')
          ..add('uciok');
      } else if (c == 'isready') {
        _out.add('readyok');
      } else if (c.startsWith('position')) {
        final m = c.split(' moves ');
        _ply = m.length > 1 ? m[1].trim().split(' ').length : 0;
      } else if (c.startsWith('go')) {
        final (score, best) = script[_ply];
        _out
          ..add('info depth 12 multipv 1 score $score pv $best')
          ..add('bestmove $best');
      }
    });
  }

  @override
  Future<void> close() async {}
}

void main() {
  testWidgets('load, analyse and inspect a game on the desktop layout', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('ply_e2e');
    addTearDown(() => dir.deleteSync(recursive: true));
    final settings = Settings(dir);
    final store = GameStore(dir);
    final engineIo = ScriptedEngine(const [
      ('cp 30', 'e2e4'),
      ('cp -30', 'e7e5'),
      ('cp 30', 'g1f3'),
      ('cp 0', 'b8c6'),
      ('cp 0', 'f1c4'),
      ('cp -20', 'g7g6'), // Black to move: White +0.20
      ('mate 1', 'h5f7'),
    ]);
    final engine = EngineService(connect: () async => engineIo);
    final api = <Uri>[];
    final browser = GamesBrowser(
      settings: settings,
      httpGet: (uri, accept) async {
        api.add(uri);
        return switch (uri.path) {
          '/api/user/ply_tester' => HttpReply(
            200,
            jsonEncode({'username': 'Ply_Tester'}),
          ),
          '/api/games/user/ply_tester' => const HttpReply(200, pgn),
          _ => const HttpReply(404, '{}'),
        };
      },
    );
    final analysis = AnalysisController(
      engine: engine,
      store: store,
      settings: settings,
    );
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Services(
        store: store,
        settings: settings,
        engine: engine,
        analysis: analysis,
        browser: browser,
        tab: ValueNotifier(0),
        child: const PlyApp(),
      ),
    );
    await tester.pump();

    // 1. Choose Lichess and enter the username.
    await tester.tap(find.text('Lichess'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'Ply_Tester');
    await tester.tap(find.text('Load games'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(browser.error, isNull);
    expect(settings.profile!.key, 'lichess:ply_tester');
    expect(find.text('vs Opp (1480)'), findsOneWidget);

    // 2. Open the game: the board turns to the user's side (Black).
    await tester.tap(find.text('vs Opp (1480)'));
    await tester.pump();
    expect(analysis.game.length, 7);
    expect(analysis.gameProfile, 'lichess:ply_tester');
    expect(analysis.orientation.name, 'black');

    // 3. Analyse with the (scripted) engine.
    await tester.tap(find.text('Analyse'));
    for (
      var i = 0;
      i < 40 && (analysis.reviewing || analysis.review == null);
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(analysis.review!.complete, isTrue);
    expect(store.games, isEmpty); // local history is off by default

    // 4. Review tab lists the blunder and a learning point.
    await tester.tap(find.widgetWithText(Tab, 'Review'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Key mistakes'), findsOneWidget);
    expect(find.textContaining('Nf6??'), findsWidgets);
    expect(find.text('Allowed a forced mate'), findsOneWidget);

    // 5. Jump to the mistake on the board.
    await tester.tap(find.text('Show move').first);
    await tester.pump();
    expect(analysis.ply, 6);

    // 6. Closing the app shuts the engine down.
    await tester.runAsync(() => engine.engine.then((e) => e.dispose()));
    expect(engineIo.sent.last, 'quit');
  });
}
