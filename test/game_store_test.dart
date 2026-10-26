import 'dart:io';

import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter_test/flutter_test.dart';
import 'package:ply/analysis/eval.dart';
import 'package:ply/analysis/review.dart';
import 'package:ply/chess/chess_game.dart';
import 'package:ply/storage/game_store.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('ply_store'));
  tearDown(() => dir.deleteSync(recursive: true));

  const pgn =
      '[White "me"]\n[Black "you"]\n[Result "1-0"]\n[Date "2026.03.04"]\n'
      '[TimeControl "300+0"]\n\n1. e4 e5 2. Qh5 Nc6 3. Bc4 Nf6 4. Qxf7# 1-0';

  test('games, reviews and positions survive a reload', () async {
    final store = GameStore(dir);
    final g = ChessGame.fromPgn(pgn);
    final review = GameReview(
      depth: 12,
      engine: 'Stockfish 19',
      moves: [for (final p in g.plies) p.uci],
      positions: List.generate(
        g.length + 1,
        (i) => i == 3
            ? null
            : const PositionAnalysis(
                eval: Eval.cp(25),
                depth: 12,
                bestMove: 'e2e4',
              ),
      ),
    );
    await store.upsert(
      SavedGame(
        id: 'a',
        pgn: g.toPgn(),
        addedAt: DateTime(2026),
        myColor: Side.white,
        review: review,
      ),
    );
    await store.addPosition(
      SavedPosition(
        id: 'p',
        fen: g.positionAt(5).fen,
        note: 'Nf6??',
        addedAt: DateTime(2026),
        gameId: 'a',
        ply: 5,
      ),
    );

    final again = GameStore(dir);
    await again.load();
    final s = again.byId('a')!;
    expect(s.myColor, Side.white);
    expect(s.game.length, 7);
    expect(s.review!.matches(s.game), isTrue);
    expect(s.review!.positions[3], isNull);
    expect(s.review!.positions[4]!.eval.cp, 25);
    expect(again.positions.single.note, 'Nf6??');
    expect(s.myResult, 'win');
    expect(s.speed, 'Blitz');
    expect(s.date, DateTime(2026, 3, 4));
    expect(s.title, 'me vs you');
  });

  test('delete and update', () async {
    final store = GameStore(dir);
    await store.upsert(SavedGame(id: 'a', pgn: pgn, addedAt: DateTime(2026)));
    await store.upsert(store.byId('a')!.copyWith(myColor: Side.black));
    expect(store.byId('a')!.myResult, 'loss');
    await store.delete('a');
    final again = GameStore(dir);
    await again.load();
    expect(again.games, isEmpty);
  });

  test('a corrupt data file is kept aside, not overwritten', () async {
    File('${dir.path}/ply_data.json').writeAsStringSync('{not json');
    final store = GameStore(dir);
    await store.load();
    expect(store.loadError, isNotNull);
    expect(store.games, isEmpty);
    final backups = dir.listSync().where((f) => f.path.contains('.corrupt-'));
    expect(backups.length, 1);
  });

  test('colour detection from usernames', () {
    final g = ChessGame.fromPgn(pgn);
    expect(GameStore.detectColor(g, ['ME']), Side.white);
    expect(GameStore.detectColor(g, ['you ']), Side.black);
    expect(GameStore.detectColor(g, ['other']), isNull);
  });
}
