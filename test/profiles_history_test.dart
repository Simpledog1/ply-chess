import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ply/chess/chess_game.dart';
import 'package:ply/engine/engine_service.dart';
import 'package:ply/online/online_games.dart';
import 'package:ply/storage/game_store.dart';
import 'package:ply/storage/settings.dart';
import 'package:ply/ui/analysis_controller.dart';

import 'uci_test.dart' show FakeEngine;

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('ply_profiles'));
  tearDown(() => dir.deleteSync(recursive: true));

  test(
    'profiles are remembered most-recent-first and survive restart',
    () async {
      final s = Settings(dir);
      await s.useProfile(ChessSite.lichess, 'Alice');
      await s.useProfile(ChessSite.chessCom, 'alice');
      await s.useProfile(ChessSite.lichess, 'ALICE'); // same profile again
      expect(s.profiles.map((p) => p.key), ['lichess:alice', 'chessCom:alice']);
      expect(s.loadSource, LoadSource.lichess);

      final again = Settings(dir);
      await again.load();
      expect(again.profiles.length, 2);
      expect(again.profile!.key, 'lichess:alice');
      expect(again.myNames, contains('alice'));
      expect(again.saveHistory, isFalse); // off by default

      await again.forgetProfile('lichess:alice');
      expect(again.profile, isNull);
      expect(again.profiles.single.key, 'chessCom:alice');
    },
  );

  test('settings and game records live in separate files', () async {
    final s = Settings(dir);
    await s.useProfile(ChessSite.lichess, 'alice');
    final store = GameStore(dir);
    await store.upsert(
      SavedGame(
        id: 'g',
        pgn: '1. e4 *',
        addedAt: DateTime(2026),
        profile: 'lichess:alice',
      ),
    );
    final settingsText = File('${dir.path}/settings.json').readAsStringSync();
    expect(settingsText, isNot(contains('1. e4')));
    expect(
      File('${dir.path}/ply_data.json').readAsStringSync(),
      contains('lichess:alice'),
    );
  });

  test(
    'deleting a profile removes only its games and pinned positions',
    () async {
      final store = GameStore(dir);
      SavedGame g(String id, String? profile) => SavedGame(
        id: id,
        pgn: '1. d4 *',
        addedAt: DateTime(2026),
        profile: profile,
      );
      await store.addAll([
        g('a1', 'lichess:alice'),
        g('a2', 'lichess:alice'),
        g('c1', 'chessCom:alice'),
        g('imp', null),
      ]);
      await store.addPosition(
        SavedPosition(
          id: 'p1',
          fen: ChessGame.standard().last.fen,
          note: '',
          addedAt: DateTime(2026),
          gameId: 'a1',
        ),
      );
      expect(store.countsByProfile(), {
        'lichess:alice': 2,
        'chessCom:alice': 1,
        null: 1,
      });
      expect(await store.deleteProfile('lichess:alice'), 2);

      final reopened = GameStore(dir);
      await reopened.load();
      expect(reopened.games.map((x) => x.id), ['c1', 'imp']);
      expect(reopened.positions, isEmpty);

      await reopened.deleteAll();
      final empty = GameStore(dir);
      await empty.load();
      expect(empty.games, isEmpty);
    },
  );

  test('with history off, analysing a game writes nothing to disk', () async {
    final settings = Settings(dir);
    final store = GameStore(dir);
    final t = FakeEngine()..searchOutput = ['info depth 8 score cp 20 pv e2e4'];
    final engine = EngineService(connect: () async => t);
    final a = AnalysisController(
      engine: engine,
      store: store,
      settings: settings,
    );
    a.load(ChessGame.fromPgn('1. e4 e5'), profile: 'lichess:alice');
    await a.startReview();
    expect(a.review!.complete, isTrue);
    expect(store.games, isEmpty);
    expect(File('${dir.path}/ply_data.json').existsSync(), isFalse);

    // Turning history on saves the game with its profile and analysis.
    await settings.update((s) => s.saveHistory = true);
    a.load(ChessGame.fromPgn('1. d4 d5'), profile: 'lichess:alice');
    await a.startReview();
    expect(store.games.single.profile, 'lichess:alice');
    expect(store.games.single.review!.complete, isTrue);
  });
}
