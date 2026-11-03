// Renders the main screens to PNG files for visual checks, using the real
// widget tree, real fonts and a real Stockfish review. Skipped unless both
// PLY_RENDER_DIR and STOCKFISH_PATH are set:
//   PLY_RENDER_DIR=out STOCKFISH_PATH=/path/to/stockfish flutter test test/render_screens_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dartchess/dartchess.dart' show Move, NormalMove, Side;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ply/analysis/openings.dart';
import 'package:ply/analysis/review_runner.dart';
import 'package:ply/chess/chess_game.dart';
import 'package:ply/engine/engine_service.dart';
import 'package:ply/online/games_browser.dart';
import 'package:ply/online/online_games.dart';
import 'package:ply/engine/uci.dart';
import 'package:ply/main.dart';
import 'package:ply/storage/game_store.dart';
import 'package:ply/storage/settings.dart';
import 'package:ply/ui/analysis_controller.dart';
import 'package:ply/ui/board/chess_board.dart';
import 'package:ply/ui/services.dart';
import 'package:ply/training/puzzle_catalogue.dart';
import 'package:ply/training/training_controller.dart';
import 'package:ply/training/recommender.dart';
import 'package:ply/training/training_store.dart';

const opera = '''
[Event "Paris"]
[Site "Paris FRA"]
[Date "1858.11.02"]
[White "Paul Morphy"]
[Black "Duke Karl / Count Isouard"]
[Result "1-0"]
[Opening "Philidor Defense"]

1. e4 e5 2. Nf3 d6 3. d4 Bg4 4. dxe5 Bxf3 5. Qxf3 dxe5 6. Bc4 Nf6 7. Qb3 Qe7
8. Nc3 c6 9. Bg5 b5 10. Nxb5 cxb5 11. Bxb5+ Nbd7 12. O-O-O Rd8 13. Rxd7 Rxd7
14. Rd1 Qe6 15. Bxd7+ Nxd7 16. Qb8+ Nxb8 17. Rd8# 1-0
''';

Future<void> _loadFonts() async {
  final root =
      Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable)
          .parent
          .parent
          .parent
          .parent
          .parent
          .parent
          .path;
  final dir = '$root/bin/cache/artifacts/material_fonts';
  Future<ByteData> f(String n) async =>
      ByteData.sublistView(await File('$dir/$n').readAsBytes());
  await (FontLoader('Roboto')
        ..addFont(f('roboto-regular.ttf'))
        ..addFont(f('roboto-medium.ttf'))
        ..addFont(f('roboto-bold.ttf')))
      .load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(f('materialicons-regular.otf'))).load();
}

void main() {
  final out = Platform.environment['PLY_RENDER_DIR'];
  final sf = Platform.environment['STOCKFISH_PATH'];
  final skip = out == null || sf == null
      ? 'PLY_RENDER_DIR / STOCKFISH_PATH not set'
      : null;

  testWidgets('render screens', (tester) async {
    final key = GlobalKey();
    final dir = Directory.systemTemp.createTempSync('ply_render');
    late Services services;
    await tester.runAsync(() async {
      await _loadFonts();
      await precachePieces();
      final store = GameStore(dir);
      final settings = Settings(dir)..usernames = ['Duke Karl / Count Isouard'];
      final engine = EngineService();
      final uci = UciEngine(await ProcessTransport.start(sf!));
      await uci.init(threads: 4, hashMb: 64);
      final g = ChessGame.fromPgn(opera);
      final review = await runReview(engine: uci, game: g, depth: 14);
      final saved = SavedGame(
        id: 'opera',
        pgn: g.toPgn(),
        addedAt: DateTime(2026, 10, 1),
        myColor: Side.black,
        review: review,
      );
      await store.upsert(saved);
      for (final (i, pgn) in [
        '[White "Duke Karl / Count Isouard"]\n[Black "Rival"]\n[Result "1/2-1/2"]\n[Date "2026.09.12"]\n[TimeControl "600+5"]\n\n1. d4 d5 2. c4 e6 3. Nc3 Nf6 1/2-1/2',
        '[White "Rival"]\n[Black "Duke Karl / Count Isouard"]\n[Result "0-1"]\n[Date "2026.09.20"]\n[TimeControl "180+2"]\n\n1. e4 c5 2. Nf3 d6 0-1',
      ].indexed) {
        await store.upsert(
          SavedGame(
            id: 'g$i',
            pgn: ChessGame.fromPgn(pgn).toPgn(),
            addedAt: DateTime(2026, 9, i + 1),
            myColor: GameStore.detectColor(
              ChessGame.fromPgn(pgn),
              settings.usernames,
            ),
          ),
        );
      }
      await store.addPosition(
        SavedPosition(
          id: 'p',
          fen: g.positionAt(19).fen,
          note: 'Why does 10.Nxb5 work?',
          addedAt: DateTime(2026, 10, 2),
        ),
      );
      await uci.dispose();
      services = Services(
        store: store,
        settings: settings,
        engine: engine,
        analysis: AnalysisController(
          engine: engine,
          store: store,
          settings: settings,
        ),
        // Recent-games panel fed from a local fixture, not the network.
        browser: GamesBrowser(
          settings: settings,
          httpGet: (uri, accept) async => uri.path.startsWith('/api/user/')
              ? const HttpReply(200, '{"username":"Morphy"}')
              : HttpReply(
                  200,
                  opera.replaceFirst(
                    '[Site "Paris FRA"]',
                    '[Site "https://lichess.org/opera1858"]',
                  ),
                ),
        ),
        training: TrainingController(
          catalogue: PuzzleCatalogue(dir),
          store: TrainingStore(dir),
          // Long enough to capture the wrong-move feedback.
          wrongDelay: const Duration(seconds: 10),
        ),
        tab: ValueNotifier(0),
        child: RepaintBoundary(key: key, child: const PlyApp()),
      );
      services.analysis.setBook(
        OpeningBook.parse([
          for (final f in 'abcde'.split(''))
            File('assets/openings/$f.tsv').readAsStringSync(),
        ]),
      );
      services.analysis.loadSaved(saved, atPly: 22);
      await services.browser.open(ChessSite.lichess, 'Morphy');
    });

    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(services);

    Future<void> shot(String name) async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump(const Duration(milliseconds: 400));
      }
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(
          pixelRatio: tester.view.devicePixelRatio,
        );
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory(out!).createSync(recursive: true);
        File('$out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    await shot('analyze');
    services.analysis.goTo(0);
    await shot('analyze_top');
    await tester.tap(find.byTooltip('Analysis settings'));
    await shot('settings_sheet');
    Navigator.of(tester.element(find.byType(Dialog))).pop();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byTooltip('Share game'));
    await shot('share');
    Navigator.of(tester.element(find.byType(Dialog))).pop();
    await tester.pump(const Duration(seconds: 1));
    services.analysis.goTo(22);
    services.settings.update((s) => s.themeMode = ThemeMode.light);
    await shot('analyze_light');
    services.settings.update((s) => s.themeMode = ThemeMode.dark);
    services.tab.value = 2;
    await shot('games');
    services.tab.value = 3;
    await shot('insights');
    services.tab.value = 4;
    await shot('settings');

    // Desktop (Windows) layout: board left, Game Analysis panel right.
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    services.tab.value = 0;
    services.analysis.goTo(17);
    await shot('desktop_report');
    await tester.tap(find.text('Analysis'));
    await shot('desktop_analyze');
    // A what-if move, checked by Stockfish in the background.
    services.analysis.goTo(18);
    services.analysis.userMove(Move.parse('c4b5')!);
    services.analysis.userMove(Move.parse('c6b5')!);
    services.analysis.userMove(Move.parse('c3b5')!);
    services.analysis.goTo(19);
    for (var i = 0; i < 40 && services.analysis.lastMoveReview == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pump(const Duration(milliseconds: 200));
    }
    await shot('desktop_whatif');
    services.analysis.backToGame();
    await tester.tap(find.byTooltip('Your games and imports'));
    await shot('desktop_games');
    await tester.tap(find.text('Report'));
    // Smallest desktop window and a common laptop size.
    tester.view.physicalSize = const Size(1000, 640);
    services.analysis.goTo(12);
    await shot('desktop_1000');
    tester.view.physicalSize = const Size(1366, 768);
    await shot('desktop_1366');
    tester.view.physicalSize = const Size(1920, 1080);
    services.analysis.goTo(31);
    await shot('desktop_1920');
    // Windows display scaling: the board must stay sharp.
    tester.view.devicePixelRatio = 1.25;
    await shot('desktop_125');
    tester.view.devicePixelRatio = 1.5;
    await shot('desktop_150');

    // Puzzle Training.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    final t = services.training;
    services.tab.value = 1;
    await tester.runAsync(
      () => t.catalogue.load(
        starterCsv: File('assets/puzzles/lichess_starter.csv')
            .readAsStringSync(),
      ),
    );
    await shot('training_setup');
    await tester.runAsync(() async {
      await t.createProfile(source: RatingSource.lichess, rating: 1600);
      await t.skipCalibration();
    });
    await shot('training_plan');
    await tester.runAsync(
      () =>
          t.createCollection(t.planCollection(100, seed: 5) as CollectionPlan),
    );
    t.nextInCycle();
    await shot('training_solve');
    // A wrong move: shown in red with a cross, then taken back.
    final ws = t.session!;
    final expected = ws.puzzle.moves[1].substring(0, 4);
    final pos = ws.solver.position;
    NormalMove? wrong;
    for (final e in pos.legalMoves.entries) {
      for (final to in e.value.squares) {
        if (wrong == null &&
            '${e.key.name}${to.name}' != expected &&
            pos.board.pieceAt(to)?.color != pos.turn) {
          wrong = NormalMove(from: e.key, to: to);
        }
      }
    }
    t.play(wrong!);
    await shot('training_wrong');
    await tester.pump(const Duration(seconds: 11));
    final s = t.session!;
    while (!s.over) {
      // On the real clock: the final move saves the attempt to disk.
      await tester.runAsync(() async {
        if (!s.solver.replyPending) {
          t.play(Move.parse(s.puzzle.moves[s.solver.index])!);
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump(const Duration(milliseconds: 500));
    }
    await shot('training_solved');
    t.closeSession();
    await shot('training_dashboard');
    // Let the last saves finish before the folder is deleted.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    dir.deleteSync(recursive: true);
  }, skip: skip != null);
}
