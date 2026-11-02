// Puzzle parsing, validation, the catalogue and the solver.
import 'dart:convert';
import 'dart:io';

import 'package:dartchess/dartchess.dart' hide File;
import 'package:flutter_test/flutter_test.dart';
import 'package:ply/training/puzzle.dart';
import 'package:ply/training/puzzle_catalogue.dart';
import 'package:ply/training/puzzle_solver.dart';

/// A real response of `GET /api/puzzle/batch/fork?nb=1` (trimmed).
const apiPuzzle = '''
{"game":{"id":"FgPEuVAG","pgn":"e4 g6 d4 Bg7 e5 e6 Nf3 h6 Bc4 c6 Nc3 Ne7 b3 a6 Ba3 b5 Bd3 O-O Ne4 d5 Nd6"},
 "puzzle":{"id":"RxHce","rating":1389,"plays":26917,"solution":["d8a5","c2c3","a5a3"],
 "themes":["middlegame","short","advantage","fork"],"initialPly":20}}''';

const csvRow =
    '00sHx,q3k1nr/1pp1nQpp/3p4/1P2p3/4P3/B1PP1b2/B5PP/5K2 b k - 0 17,'
    'e8d7 a2e6 d7d8 f7f8,1760,80,83,72,mate mateIn2 middlegame short,'
    'https://lichess.org/yyznGmXs/black#34,Italian_Game Italian_Game_Classical_Variation,';

Puzzle make(String fen, List<String> moves, {List<String> themes = const []}) =>
    Puzzle(
      id: 'test:${moves.join()}',
      source: 'test',
      fen: fen,
      moves: moves,
      rating: 1500,
      themes: themes,
    );

NormalMove mv(String uci) => Move.parse(uci)! as NormalMove;

void main() {
  group('parsing and validation', () {
    test('Lichess CSV row', () {
      final p = Puzzle.fromLichessCsv(csvRow);
      expect(p.id, 'lichess:00sHx');
      expect(p.moves, ['e8d7', 'a2e6', 'd7d8', 'f7f8']);
      expect(p.rating, 1760);
      expect(p.ratingDeviation, 80);
      expect(p.popularity, 83);
      expect(p.plays, 72);
      expect(p.themes, ['mate', 'mateIn2', 'middlegame', 'short']);
      expect(p.motifs, isEmpty);
      expect(p.primaryTheme, 'mate');
      expect(p.solver, Side.white);
      expect(p.playerMoves, 2);
      expect(validatePuzzle(p), isNull);
    });

    test('Lichess API puzzle becomes the database convention', () {
      final p = Puzzle.fromLichessApi(
        jsonDecode(apiPuzzle) as Map<String, dynamic>,
      );
      expect(p.id, 'lichess:RxHce');
      // The opponent's last game move (Nd6) comes first.
      expect(p.moves, ['e4d6', 'd8a5', 'c2c3', 'a5a3']);
      expect(p.solver, Side.black);
      expect(validatePuzzle(p), isNull);
    });

    test('malformed records are rejected', () {
      expect(
        validatePuzzle(make('not a fen', ['e2e4', 'e7e5'])),
        'Invalid FEN',
      );
      expect(
        validatePuzzle(make(Chess.initial.fen, ['e2e4', 'e7e4'])),
        startsWith('Illegal move 2'),
      );
      expect(validatePuzzle(make(Chess.initial.fen, ['e2e4'])), 'No solution');
      expect(
        validatePuzzle(make(Chess.initial.fen, ['e2e4', 'e7e5', 'g1f3'])),
        contains('end with the player'),
      );
      expect(
        () => Puzzle.fromLichessCsv('abc,only,three'),
        throwsFormatException,
      );
    });

    test('the bundled starter pack is complete and valid', () {
      final text = File('assets/puzzles/lichess_starter.csv')
          .readAsStringSync();
      final r = parsePuzzleCsv(text);
      expect(r.rejected, 0);
      expect(r.puzzles.length, greaterThan(7000));
      expect(r.puzzles.map((p) => p.id).toSet().length, r.puzzles.length);
      final ratings = r.puzzles.map((p) => p.rating);
      expect(ratings.reduce((a, b) => a < b ? a : b), lessThan(800));
      expect(ratings.reduce((a, b) => a > b ? a : b), greaterThan(2600));
      final motifs = {for (final p in r.puzzles) ...p.motifs};
      for (final t in ['fork', 'pin', 'skewer', 'discoveredAttack']) {
        expect(motifs, contains(t));
      }
    });
  });

  group('catalogue', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('ply_cat'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('imports validate, skip duplicates and survive a restart', () async {
      final c = PuzzleCatalogue(dir);
      await c.load(starterCsv: 'PuzzleId,FEN\n$csvRow\n');
      expect(c.size, 1);
      final api = Puzzle.fromLichessApi(
        jsonDecode(apiPuzzle) as Map<String, dynamic>,
      );
      final r = await c.addAll([
        api,
        api,
        Puzzle.fromLichessCsv(csvRow), // already in the starter pack
        make('bad fen', ['a', 'b']),
      ], source: 'test');
      expect(r.added, 1);
      expect(r.duplicates, 2);
      expect(r.rejected, 1);
      expect(r.reasons, {'Invalid FEN': 1});
      final again = PuzzleCatalogue(dir);
      await again.load(starterCsv: '');
      expect(again.byId('lichess:RxHce')!.moves, api.moves);
      expect(again.imports.single.added, 1);
    });

    test('an unreadable file is kept aside, not overwritten', () async {
      File('${dir.path}/puzzles.json').writeAsStringSync('{broken');
      final c = PuzzleCatalogue(dir);
      await c.load(starterCsv: '');
      expect(c.loadError, contains('corrupt'));
      expect(
        dir.listSync().where((f) => f.path.contains('.corrupt-')),
        hasLength(1),
      );
    });
  });

  group('solver', () {
    test('multi-move solution with opponent replies', () {
      final p = Puzzle.fromLichessApi(
        jsonDecode(apiPuzzle) as Map<String, dynamic>,
      );
      final s = PuzzleSolver(p);
      expect(s.position.turn, Side.black);
      expect(s.lastMove, 'e4d6');
      expect(s.play(mv('d8a5')), MoveVerdict.correct);
      expect(s.replyPending, isTrue);
      s.reply();
      expect(s.lastMove, 'c2c3');
      expect(s.play(mv('a5a3')), MoveVerdict.solved);
      expect(s.firstTryCorrect, isTrue);
      expect(s.tried, ['d8a5', 'a5a3']);
    });

    test('Retry: a wrong move is counted and can be corrected', () {
      final p = Puzzle.fromLichessCsv(csvRow);
      final s = PuzzleSolver(p);
      expect(s.play(mv('a3b4')), MoveVerdict.wrong);
      expect(s.wrongMoves, 1);
      expect(s.position.fen, s.start.fen); // taken back
      expect(s.play(mv('a2e6')), MoveVerdict.correct);
      s.reply();
      expect(s.play(mv('f7f8')), MoveVerdict.solved);
      expect(s.solved, isTrue);
      expect(s.firstTryCorrect, isFalse); // no first-try credit
    });

    test('Reveal: a wrong move shows the solution and fails', () {
      final p = Puzzle.fromLichessCsv(csvRow);
      final s = PuzzleSolver(p, behavior: WrongMoveBehavior.reveal);
      expect(s.play(mv('a3b4')), MoveVerdict.revealed);
      expect(s.failed, isTrue);
      expect(s.solved, isFalse);
      expect(s.lastMove, 'f7f8');
      expect(s.play(mv('a3b4')), MoveVerdict.ignored);
    });

    test('any checkmate is accepted', () {
      final p = make(
        '6k1/5ppp/n7/8/8/8/5PPP/RR4K1 b - - 0 1',
        ['a6c5', 'a1a8'],
        themes: ['mate', 'mateIn1', 'backRankMate'],
      );
      expect(validatePuzzle(p), isNull);
      expect(PuzzleSolver(p).play(mv('b1b8')), MoveVerdict.solved);
      expect(PuzzleSolver(p).play(mv('g1f1')), MoveVerdict.wrong);
    });

    test('castling matches whichever way the board writes it', () {
      final p = make('4k3/8/8/8/8/8/5PPP/4K2R b K - 0 1', ['e8d8', 'e1g1']);
      expect(validatePuzzle(p), isNull);
      expect(PuzzleSolver(p).play(mv('e1g1')), MoveVerdict.solved);
      expect(PuzzleSolver(p).play(mv('e1h1')), MoveVerdict.solved);
    });

    test('en passant', () {
      final p = make('4k3/8/8/8/1p6/8/P7/4K3 w - - 0 1', ['a2a4', 'b4a3']);
      expect(validatePuzzle(p), isNull);
      final s = PuzzleSolver(p);
      expect(s.play(mv('b4a3')), MoveVerdict.solved);
      expect(s.position.board.pieceAt(Square.fromName('a4')), isNull);
    });

    test('promotion must be the right piece', () {
      final p = make('8/P7/8/8/8/8/8/k1K5 b - - 0 1', ['a1a2', 'a7a8q']);
      expect(validatePuzzle(p), isNull);
      expect(PuzzleSolver(p).play(mv('a7a8n')), MoveVerdict.wrong);
      expect(PuzzleSolver(p).play(mv('a7a8q')), MoveVerdict.solved);
    });

    test('hints go from theme to piece to move, and cost first-try credit', () {
      final p = Puzzle.fromLichessApi(
        jsonDecode(apiPuzzle) as Map<String, dynamic>,
      );
      final s = PuzzleSolver(p);
      expect(s.hint().text, 'Theme: Fork.');
      final h2 = s.hint();
      expect(h2.from, Square.fromName('d8'));
      expect(h2.text, contains('queen on d8'));
      final h3 = s.hint();
      expect(h3.move, 'd8a5');
      expect(h3.text, 'The move is Qa5+.');
      s.play(mv('d8a5'));
      s.reply();
      s.play(mv('a5a3'));
      expect(s.solved, isTrue);
      expect(s.firstTryCorrect, isFalse);
      expect(s.hintLevel, 3);
    });

    test('reset returns to the start and keeps the counts', () {
      final p = Puzzle.fromLichessApi(
        jsonDecode(apiPuzzle) as Map<String, dynamic>,
      );
      final s = PuzzleSolver(p);
      s.play(mv('g8h7')); // legal but wrong
      s.play(mv('d8a5'));
      s.reply();
      s.reset();
      expect(s.position.fen, s.start.fen);
      expect(s.index, 1);
      expect(s.wrongMoves, 1);
    });

    test('solution text is numbered SAN', () {
      expect(
        formatSolution(Puzzle.fromLichessCsv(csvRow)),
        '18. Be6+ Kd8 19. Qf8#',
      );
    });
  });
}
