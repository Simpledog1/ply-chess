import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ply/online/games_browser.dart';
import 'package:ply/online/online_games.dart';
import 'package:ply/storage/settings.dart';

String lichessGame(String id, String time, {String opp = 'opp'}) =>
    '''
[Event "Rated Blitz game"]
[Site "https://lichess.org/$id"]
[Date "2026.10.20"]
[White "Ply_Tester"]
[Black "$opp"]
[Result "1-0"]
[UTCDate "2026.10.20"]
[UTCTime "$time"]
[WhiteElo "1500"]
[BlackElo "1480"]
[TimeControl "180+2"]
[Opening "Italian Game"]

1. e4 e5 2. Nf3 Nc6 3. Bc4 Nf6 1-0''';

Map<String, dynamic> chessComGame(String id, {String rules = 'chess'}) => {
  'url': 'https://www.chess.com/game/live/$id',
  'rules': rules,
  'time_class': 'blitz',
  'pgn':
      '[Event "Live Chess"]\n[Site "Chess.com"]\n[Date "2026.10.01"]\n'
      '[White "Ply_Tester"]\n[Black "opp$id"]\n[Result "0-1"]\n'
      '[Link "https://www.chess.com/game/live/$id"]\n[TimeControl "300"]\n\n'
      '1. f3 e5 2. g4 Qh4# 0-1',
};

/// Routes requests by path; records every call.
class FakeApi {
  FakeApi(this.routes);
  final Map<String, HttpReply Function(Uri)> routes;
  final calls = <Uri>[];

  Future<HttpReply> call(Uri uri, String accept) async {
    calls.add(uri);
    final r = routes[uri.path];
    return r == null ? const HttpReply(404, '{}') : r(uri);
  }
}

HttpReply json(Object o) => HttpReply(200, jsonEncode(o));

void main() {
  group('usernames and profile keys', () {
    test('valid names are trimmed, invalid ones rejected', () {
      expect(checkUsername('  Ply_Tester '), 'Ply_Tester');
      for (final bad in ['', 'a', 'has space', 'semi;colon', 'x' * 31]) {
        expect(() => checkUsername(bad), throwsA(isA<OnlineException>()));
      }
    });

    test('keys combine site and case-insensitive name', () {
      expect(
        profileKey(ChessSite.lichess, 'Magnus'),
        profileKey(ChessSite.lichess, 'magnus '),
      );
      expect(
        profileKey(ChessSite.lichess, 'magnus'),
        isNot(profileKey(ChessSite.chessCom, 'magnus')),
      );
    });
  });

  group('Lichess feed', () {
    FakeApi api({Map<String, dynamic>? user}) {
      final games = [
        lichessGame('g3', '18:00:00'),
        lichessGame('g2', '17:00:00'),
        lichessGame('g1', '16:00:00'),
      ];
      return FakeApi({
        '/api/user/ply_tester': (_) =>
            json(user ?? {'id': 'ply_tester', 'username': 'Ply_Tester'}),
        '/api/games/user/ply_tester': (u) {
          final until = int.tryParse(u.queryParameters['until'] ?? '');
          final max = int.parse(u.queryParameters['max']!);
          final older = [
            for (final (i, g) in games.indexed)
              if (until == null ||
                  DateTime.utc(2026, 10, 20, 18 - i).millisecondsSinceEpoch <=
                      until)
                g,
          ];
          return HttpReply(200, older.take(max).join('\n\n\n'));
        },
      });
    }

    test('pages newest first using the until cursor', () async {
      final a = api();
      final f = GameFeed(
        ChessSite.lichess,
        'ply_tester',
        get: a.call,
        pageSize: 2,
      );
      expect(await f.loadMore(), 2);
      expect(f.displayName, 'Ply_Tester');
      expect(f.games.map((g) => g.id), [
        'https://lichess.org/g3',
        'https://lichess.org/g2',
      ]);
      expect(f.hasMore, isTrue);
      expect(await f.loadMore(), 1);
      expect(f.games.last.id, 'https://lichess.org/g1');
      expect(f.hasMore, isFalse);
      final until = a.calls.last.queryParameters['until'];
      expect(
        int.parse(until!),
        DateTime.utc(2026, 10, 20, 17).millisecondsSinceEpoch - 1,
      );
      expect(await f.loadMore(), 0); // nothing more is requested
      expect(a.calls.where((c) => c.path.startsWith('/api/games')).length, 2);
    });

    test('unknown and closed accounts are reported', () async {
      await expectLater(
        GameFeed(ChessSite.lichess, 'nobody', get: FakeApi({}).call).loadMore(),
        throwsA(
          isA<OnlineException>().having(
            (e) => e.message,
            'message',
            'No Lichess player named "nobody"',
          ),
        ),
      );
      final closed = api(user: {'id': 'ply_tester', 'closed': true});
      await expectLater(
        GameFeed(ChessSite.lichess, 'ply_tester', get: closed.call).loadMore(),
        throwsA(isA<OnlineException>()),
      );
    });

    test('unreadable games are skipped, not shown', () async {
      final a = FakeApi({
        '/api/user/ply_tester': (_) => json({'username': 'Ply_Tester'}),
        '/api/games/user/ply_tester': (_) => HttpReply(
          200,
          '${lichessGame('ok', '10:00:00')}\n\n[Event "Bad"]\n\n1. e4 e4 *',
        ),
      });
      final f = GameFeed(ChessSite.lichess, 'ply_tester', get: a.call);
      expect(await f.loadMore(), 1);
      expect(f.skipped, 1);
    });
  });

  group('Chess.com feed', () {
    test('reads only the months it needs and skips variants', () async {
      final a = FakeApi({
        '/pub/player/ply_tester': (_) => json({'username': 'ply_tester'}),
        '/pub/player/ply_tester/games/archives': (_) => json({
          'archives': [
            'https://api.chess.com/pub/player/ply_tester/games/2026/09',
            'https://api.chess.com/pub/player/ply_tester/games/2026/10',
          ],
        }),
        '/pub/player/ply_tester/games/2026/10': (_) => json({
          'games': [
            chessComGame('10a'),
            chessComGame('960', rules: 'chess960'),
            chessComGame('10b'),
          ],
        }),
        '/pub/player/ply_tester/games/2026/09': (_) => json({
          'games': [chessComGame('09a'), chessComGame('09b')],
        }),
      });
      final f = GameFeed(
        ChessSite.chessCom,
        'Ply_Tester',
        get: a.call,
        pageSize: 2,
      );
      expect(await f.loadMore(), 2);
      expect(f.displayName, 'Ply_Tester'); // keeps the typed spelling
      expect(f.games.map((g) => g.id.split('/').last), ['10b', '10a']);
      expect(a.calls.any((c) => c.path.endsWith('2026/09')), isFalse);
      expect(f.hasMore, isTrue);
      await f.loadMore();
      expect(f.games.map((g) => g.id.split('/').last), [
        '10b',
        '10a',
        '09b',
        '09a',
      ]);
      expect(f.hasMore, isFalse);
    });

    test('a listed month that answers 404 is skipped, not an error', () async {
      final a = FakeApi({
        '/pub/player/ply_tester': (_) => json({'username': 'ply_tester'}),
        '/pub/player/ply_tester/games/archives': (_) => json({
          'archives': [
            'https://api.chess.com/pub/player/ply_tester/games/2026/09',
            'https://api.chess.com/pub/player/ply_tester/games/2026/10',
          ],
        }),
        '/pub/player/ply_tester/games/2026/09': (_) => json({
          'games': [chessComGame('09a')],
        }),
      });
      final f = GameFeed(ChessSite.chessCom, 'ply_tester', get: a.call);
      expect(await f.loadMore(), 1);
      expect(f.games.single.id, endsWith('09a'));
    });

    test('a player without games gives an empty, finished feed', () async {
      final a = FakeApi({
        '/pub/player/newbie': (_) => json({'username': 'newbie'}),
        '/pub/player/newbie/games/archives': (_) => json({'archives': []}),
      });
      final f = GameFeed(ChessSite.chessCom, 'newbie', get: a.call);
      expect(await f.loadMore(), 0);
      expect(f.hasMore, isFalse);
    });
  });

  group('errors', () {
    Future<String> errorFor(Future<HttpReply> Function(Uri, String) get) async {
      try {
        await GameFeed(ChessSite.chessCom, 'someone', get: get).loadMore();
      } on OnlineException catch (e) {
        return e.message;
      }
      fail('expected an OnlineException');
    }

    test('rate limits, server errors, network and bad JSON', () async {
      expect(
        await errorFor((_, _) async => const HttpReply(429, '')),
        contains('rate-limiting'),
      );
      expect(
        await errorFor((_, _) async => const HttpReply(503, '')),
        contains('having problems'),
      );
      expect(
        await errorFor((_, _) => Future.error(const SocketException('down'))),
        'No internet connection',
      );
      expect(
        await errorFor((_, _) => Future.error(TimeoutException('slow'))),
        contains('too long'),
      );
      expect(
        await errorFor((_, _) async => const HttpReply(200, '<html>')),
        'Unexpected response from the server',
      );
    });
  });

  group('GamesBrowser', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('ply_browser'));
    tearDown(() => dir.deleteSync(recursive: true));

    FakeApi api() => FakeApi({
      '/api/user/ply_tester': (_) => json({'username': 'Ply_Tester'}),
      '/api/games/user/ply_tester': (_) =>
          HttpReply(200, lichessGame('only', '12:00:00')),
    });

    test('remembers a profile only after the site confirms it', () async {
      final settings = Settings(dir);
      final b = GamesBrowser(settings: settings, httpGet: api().call);
      await b.open(ChessSite.lichess, 'nobody');
      expect(b.error, contains('No Lichess player'));
      expect(settings.profiles, isEmpty);

      await b.open(ChessSite.lichess, 'ply_tester');
      expect(b.error, isNull);
      expect(b.feed!.games.length, 1);
      expect(settings.profile!.username, 'Ply_Tester');
      expect(settings.profile!.key, 'lichess:ply_tester');
    });

    test('reopening a recent profile uses the cache', () async {
      final a = api();
      final b = GamesBrowser(settings: Settings(dir), httpGet: a.call);
      await b.open(ChessSite.lichess, 'ply_tester');
      final n = a.calls.length;
      await b.open(ChessSite.lichess, 'PLY_TESTER');
      expect(a.calls.length, n);
      b.forget('lichess:ply_tester');
      await b.open(ChessSite.lichess, 'ply_tester');
      expect(a.calls.length, greaterThan(n));
    });

    test('a cancelled request does not overwrite newer state', () async {
      final gate = Completer<HttpReply>();
      final b = GamesBrowser(
        settings: Settings(dir),
        httpGet: (_, _) => gate.future,
      );
      final pending = b.open(ChessSite.lichess, 'ply_tester');
      expect(b.loading, isTrue);
      b.cancel();
      expect(b.loading, isFalse);
      gate.complete(const HttpReply(500, ''));
      await pending;
      expect(b.error, isNull); // the late failure is ignored
    });
  });
}
