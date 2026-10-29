// Runs against a real Stockfish binary. Skipped unless STOCKFISH_PATH is set:
//   STOCKFISH_PATH=/path/to/stockfish flutter test test/stockfish_integration_test.dart
import 'dart:io';

import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ply/analysis/review.dart';
import 'package:ply/analysis/review_runner.dart';
import 'package:ply/chess/chess_game.dart';
import 'package:ply/engine/engine_service.dart';
import 'package:ply/engine/uci.dart';
import 'package:ply/storage/game_store.dart';
import 'package:ply/storage/settings.dart';
import 'package:ply/ui/analysis_controller.dart';

void main() {
  final path = Platform.environment['STOCKFISH_PATH'];
  final skip = path == null ? 'STOCKFISH_PATH not set' : null;
  late UciEngine engine;

  setUpAll(() async {
    if (path == null) return;
    engine = UciEngine(await ProcessTransport.start(path));
    await engine.init(threads: 2, hashMb: 32);
  });
  tearDownAll(() async {
    if (path != null) await engine.dispose();
  });

  test('identifies itself', () {
    expect(engine.name, startsWith('Stockfish'));
  }, skip: skip);

  test('finds mate in one for White', () async {
    final g = ChessGame.fromPgn('1. e4 e5 2. Qh5 Nc6 3. Bc4 Nf6');
    final r = await engine.search(
      fen: g.last.fen,
      turn: g.last.turn,
      depth: 10,
    );
    expect(r.complete, isTrue);
    expect(r.bestMove, 'h5f7');
    expect(r.best!.eval.isMate, isTrue);
    expect(r.best!.eval.mateIn, 1);
    expect(r.best!.eval.whiteMates, isTrue);
  }, skip: skip);

  test('mate for Black is reported from White\'s perspective', () async {
    final g = ChessGame.fromPgn('1. f3 e5 2. g4');
    final r = await engine.search(
      fen: g.initialFen,
      moves: g.ucisBefore(g.length),
      turn: Side.black,
      depth: 10,
    );
    expect(r.bestMove, 'd8h4');
    expect(r.best!.eval.whiteMates, isFalse);
    expect(r.best!.eval.label, '#-1');
  }, skip: skip);

  test('White a queen up with Black to move is a positive score', () async {
    const fen = 'rnb1kbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 3';
    final r = await engine.search(fen: fen, turn: Side.black, depth: 12);
    expect(r.best!.eval.cp!, greaterThan(500));
  }, skip: skip);

  test('stopping an infinite search returns a partial result', () async {
    final f = engine.search(fen: Chess.initial.fen, turn: Side.white);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    engine.stop();
    final r = await f.timeout(const Duration(seconds: 5));
    expect(r.stopped, isTrue);
    expect(r.complete, isFalse);
    expect(r.depth, greaterThan(0));
    expect(r.bestMove, isNotNull);
  }, skip: skip);

  test('reviews a game and flags the blunder', () async {
    final g = ChessGame.fromPgn('1. e4 e5 2. Qh5 Nc6 3. Bc4 Nf6 4. Qxf7#');
    final data = await runReview(engine: engine, game: g, depth: 12);
    expect(data.complete, isTrue);
    final moves = reviewMoves(g, data, const Thresholds());
    expect(moves[5]!.cls, MoveClass.blunder);
    expect(moves[5]!.tags, contains(MoveTag.allowedMate));
    // Mate in one: every other move is far worse, so it is the only move that holds.
    expect(moves[6]!.cls, MoveClass.critical);
    expect(summarize(moves, Side.black).counts[MoveClass.blunder], 1);
  }, skip: skip);

  test(
    'rates a what-if move in the background without changing the game',
    () async {
      final dir = Directory.systemTemp.createTempSync('ply_sf_whatif');
      addTearDown(() => dir.deleteSync(recursive: true));
      final service = EngineService(
        connect: () => ProcessTransport.start(path!),
      );
      final a = AnalysisController(
        engine: service,
        store: GameStore(dir),
        settings: Settings(dir),
      );
      addTearDown(() async {
        a.dispose();
        await (await service.engine).dispose();
      });
      a.load(ChessGame.fromPgn('1. e4 e5 2. Nf3 Nc6 3. Bc4 Nf6'));
      a.goTo(6);
      a.userMove(Move.parse('c4f7')!); // 4. Bxf7+?: a bishop for a pawn
      expect(a.onWhatIf, isTrue);
      expect(a.checking, isTrue);
      // A position change while thinking must not leak results.
      a.goTo(5);
      a.goTo(7);
      for (var i = 0; i < 100 && a.lastMoveReview == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      final m = a.lastMoveReview!;
      expect(m.san, 'Bxf7+');
      expect(m.mover, Side.white);
      expect(m.cls.isError, isTrue);
      expect(m.bestSan, isNotNull);
      expect(a.game.length, 6);
      expect(a.review, isNull);
      a.backToGame();
      expect(a.position.fen, a.game.last.fen);
    },
    skip: skip,
  );
}
