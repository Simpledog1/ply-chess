// Renders the main screens to PNG files for visual checks, using the real
// widget tree, real fonts and a real Stockfish review. Skipped unless both
// PLY_RENDER_DIR and STOCKFISH_PATH are set:
//   PLY_RENDER_DIR=out STOCKFISH_PATH=/path/to/stockfish flutter test test/render_screens_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ply/analysis/openings.dart';
import 'package:ply/analysis/review_runner.dart';
import 'package:ply/chess/chess_game.dart';
import 'package:ply/engine/engine_service.dart';
import 'package:ply/engine/uci.dart';
import 'package:ply/main.dart';
import 'package:ply/storage/game_store.dart';
import 'package:ply/storage/settings.dart';
import 'package:ply/ui/analysis_controller.dart';
import 'package:ply/ui/board/chess_board.dart';
import 'package:ply/ui/review_screen.dart';
import 'package:ply/ui/services.dart';

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
        final image = await boundary.toImage(pixelRatio: 2.625);
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
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(MaterialPageRoute<void>(builder: (_) => const ReviewScreen()));
    await shot('review');
    nav.pop();
    await tester.pump(const Duration(seconds: 1));
    services.tab.value = 1;
    await shot('games');
    services.tab.value = 2;
    await shot('insights');
    services.tab.value = 3;
    await shot('settings');
    dir.deleteSync(recursive: true);
  }, skip: skip != null);
}
