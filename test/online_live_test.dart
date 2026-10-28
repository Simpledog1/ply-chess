// Hits the real Chess.com and Lichess public APIs. Skipped unless PLY_ONLINE=1.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ply/online/online_games.dart';

void main() {
  final skip = Platform.environment['PLY_ONLINE'] != '1';
  const timeout = Timeout(Duration(minutes: 2));

  test(
    'Chess.com: validate, first page, next page',
    () async {
      final f = GameFeed(ChessSite.chessCom, 'Hikaru', pageSize: 5);
      expect(await f.loadMore(), 5);
      expect(f.displayName, isNotNull);
      final first = f.games.first.game;
      expect(
        [
          first.headers['White'],
          first.headers['Black'],
        ].map((n) => n?.toLowerCase()),
        contains('hikaru'),
      );
      expect(f.hasMore, isTrue);
      await f.loadMore();
      expect(f.games.length, 10);
      expect(f.games.map((g) => g.id).toSet().length, 10); // no duplicates
    },
    skip: skip,
    timeout: timeout,
  );

  test(
    'Lichess: validate, first page, older page',
    () async {
      final f = GameFeed(ChessSite.lichess, 'DrNykterstein', pageSize: 3);
      await f.loadMore();
      expect(f.displayName, 'DrNykterstein');
      expect(f.games.length, 3);
      final newest = f.games.first.playedAt!;
      await f.loadMore();
      expect(f.games.length, 6);
      expect(f.games.last.playedAt!.isBefore(newest), isTrue);
      for (final g in f.games) {
        expect(g.id, startsWith('https://lichess.org/'));
      }
    },
    skip: skip,
    timeout: timeout,
  );

  test(
    'unknown users give readable errors',
    () async {
      await expectLater(
        GameFeed(ChessSite.lichess, 'zz-ply-no-such-user-xq9').loadMore(),
        throwsA(
          isA<OnlineException>().having(
            (e) => e.message,
            'message',
            contains('No Lichess player'),
          ),
        ),
      );
      await expectLater(
        GameFeed(ChessSite.chessCom, 'zz-ply-no-such-user-xq9').loadMore(),
        throwsA(isA<OnlineException>()),
      );
    },
    skip: skip,
    timeout: timeout,
  );
}
