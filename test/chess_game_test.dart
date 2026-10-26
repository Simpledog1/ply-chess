import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ply/chess/chess_game.dart';

ChessGame playAll(ChessGame g, List<String> ucis) {
  for (final u in ucis) {
    final next = g.playUci(g.length, u);
    if (next == null) throw StateError('illegal $u');
    g = next;
  }
  return g;
}

void main() {
  group('moves', () {
    test('start position has 20 legal moves', () {
      final pos = ChessGame.standard().last;
      final n = pos.legalMoves.values.fold(0, (a, s) => a + s.size);
      expect(n, 20);
    });

    test('illegal move is rejected', () {
      expect(ChessGame.standard().playUci(0, 'e2e5'), isNull);
      expect(ChessGame.standard().playUci(0, 'e7e5'), isNull);
    });

    test('castling both sides uses standard UCI and SAN', () {
      final g = playAll(
        ChessGame.fromFen('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1'),
        ['e1g1', 'e8c8'],
      );
      expect(g.plies.map((p) => p.san), ['O-O', 'O-O-O']);
      expect(g.plies.map((p) => p.uci), ['e1g1', 'e8c8']);
      expect(g.last.board.pieceAt(Square.f1)?.role, Role.rook);
      expect(g.last.board.pieceAt(Square.d8)?.role, Role.rook);
    });

    test('castling given as king-takes-rook is normalised', () {
      final g = ChessGame.fromFen('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1')
          .playUci(0, 'e1h1')!;
      expect(g.plies.single.uci, 'e1g1');
    });

    test('cannot castle through check', () {
      final g = ChessGame.fromFen('4k3/8/8/8/8/8/5r2/R3K2R w KQ - 0 1');
      expect(g.playUci(0, 'e1g1'), isNull);
    });

    test('en passant', () {
      final g = playAll(ChessGame.standard(), [
        'e2e4',
        'a7a6',
        'e4e5',
        'd7d5',
        'e5d6',
      ]);
      expect(g.plies.last.san, 'exd6');
      expect(g.last.board.pieceAt(Square.d5), isNull);
    });

    test('promotion with choice of piece', () {
      final base = ChessGame.fromFen('8/P7/8/8/8/8/8/k6K w - - 0 1');
      expect(base.playUci(0, 'a7a8n')!.plies.single.san, 'a8=N');
      expect(base.playUci(0, 'a7a8q')!.plies.single.san, 'a8=Q+');
    });

    test('checkmate and stalemate', () {
      final mate = playAll(ChessGame.standard(), [
        'f2f3',
        'e7e5',
        'g2g4',
        'd8h4',
      ]);
      expect(mate.last.isCheckmate, isTrue);
      expect(mate.plies.last.san, 'Qh4#');
      expect(mate.result, '0-1');

      final stale = ChessGame.fromFen('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1');
      expect(stale.last.isStalemate, isTrue);
      expect(stale.result, '1/2-1/2');
    });

    test('playing a different move mid-game truncates the rest', () {
      final g = playAll(ChessGame.standard(), ['e2e4', 'e7e5', 'g1f3']);
      final same = g.playUci(1, 'e7e5')!;
      expect(identical(same, g), isTrue);
      final other = g.playUci(1, 'c7c5')!;
      expect(other.plies.map((p) => p.san), ['e4', 'c5']);
    });
  });

  group('FEN', () {
    test('round trip', () {
      const fen =
          'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3';
      expect(ChessGame.fromFen(fen).initialFen, fen);
    });

    test('invalid FEN gives readable error', () {
      expect(() => ChessGame.fromFen('not a fen'), throwsFormatException);
      // Two white kings.
      expect(
        () => ChessGame.fromFen('4k3/8/8/8/8/8/8/K3K3 w - - 0 1'),
        throwsFormatException,
      );
    });
  });

  group('PGN', () {
    const pgn = '''
[Event "Casual"]
[White "alice"]
[Black "bob"]
[Result "1-0"]
[TimeControl "180+2"]

1. e4 {best by test} e5 2. Nf3 (2. f4 exf4) Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O 1-0
''';

    test('import keeps headers, mainline, drops variations', () {
      final g = ChessGame.fromPgn(pgn);
      expect(g.headers['White'], 'alice');
      expect(
        g.plies.map((p) => p.san).join(' '),
        'e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O',
      );
      expect(g.plies.last.uci, 'e1g1');
      expect(g.result, '1-0');
    });

    test('export then re-import is identical', () {
      final g = ChessGame.fromPgn(pgn);
      final again = ChessGame.fromPgn(g.toPgn());
      expect(again.plies.map((p) => p.uci), g.plies.map((p) => p.uci));
      expect(again.headers['Black'], 'bob');
    });

    test('export writes comments and NAGs', () {
      final g = ChessGame.fromPgn(pgn);
      final out = g.toPgn(comments: {0: 'Best'}, nags: {1: 4});
      expect(out, contains('{ Best }'));
      expect(out, contains(r'$4'));
    });

    test('game from a FEN exports SetUp/FEN headers', () {
      final g = ChessGame.fromFen('8/P7/8/8/8/8/8/k6K w - - 0 1')
          .playUci(0, 'a7a8q')!;
      final out = g.toPgn();
      expect(out, contains('[FEN "8/P7/8/8/8/8/8/k6K w - - 0 1"]'));
      expect(ChessGame.fromPgn(out).plies.single.san, 'a8=Q+');
    });

    test('illegal move is reported with its move number', () {
      expect(
        () => ChessGame.fromPgn('1. e4 e5 2. Ke3'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('2. Ke3'),
          ),
        ),
      );
    });

    test('multi-game import keeps good games and reports bad ones', () {
      final r = ChessGame.parseMany(
        '$pgn\n\n[Event "Bad"]\n\n1. e4 e4 *\n\n'
        '[Event "Third"]\n\n1. d4 d5 *',
      );
      expect(r.games.length, 2);
      expect(r.errors.single, startsWith('Game 2'));
    });

    test('empty or garbage input reports an error', () {
      final r = ChessGame.parseMany('   ');
      expect(r.games, isEmpty);
      expect(r.errors, isNotEmpty);
    });
  });

  test('material edge', () {
    final g = ChessGame.fromFen('4k3/8/8/8/8/8/PP6/R3K3 w - - 0 1');
    final e = materialEdge(g.last.board, Side.white);
    expect(e.points, 7);
    expect(e.extra[Role.rook], 1);
    expect(materialEdge(g.last.board, Side.black).extra, isEmpty);
  });
}
