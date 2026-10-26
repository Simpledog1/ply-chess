// Hits the real Chess.com and Lichess public APIs. Skipped unless PLY_ONLINE=1.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ply/chess/chess_game.dart';
import 'package:ply/online/online_games.dart';

void main() {
  final skip = Platform.environment['PLY_ONLINE'] != '1';

  test(
    'Chess.com recent games parse',
    () async {
      final pgns = await OnlineGames().chessCom('hikaru', max: 5);
      expect(pgns, isNotEmpty);
      final g = ChessGame.fromPgn(pgns.first);
      expect(g.length, greaterThan(0));
      expect(
        [g.headers['White'], g.headers['Black']].map((n) => n?.toLowerCase()),
        contains('hikaru'),
      );
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 1)),
  );

  test(
    'Lichess recent games parse',
    () async {
      final pgns = await OnlineGames().lichess('DrNykterstein', max: 5);
      expect(pgns.length, greaterThan(1));
      for (final p in pgns) {
        expect(
          ChessGame.fromPgn(p).headers['Site'],
          startsWith('https://lichess.org/'),
        );
      }
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 1)),
  );

  test(
    'unknown user and bad names give readable errors',
    () async {
      await expectLater(
        OnlineGames().chessCom('no such user!'),
        throwsA(isA<OnlineException>()),
      );
      await expectLater(
        OnlineGames().lichess('zz-ply-no-such-user-xq9'),
        throwsA(
          isA<OnlineException>().having(
            (e) => e.message,
            'message',
            'User not found',
          ),
        ),
      );
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
