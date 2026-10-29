// Move feedback while navigating and trying moves: what-if lines, background
// checks, perspective, mate and forced moves, and stale engine results.
import 'dart:async';
import 'dart:io';

import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ply/analysis/eval.dart';
import 'package:ply/analysis/review.dart';
import 'package:ply/chess/chess_game.dart';
import 'package:ply/engine/engine_service.dart';
import 'package:ply/engine/uci.dart';
import 'package:ply/storage/game_store.dart';
import 'package:ply/storage/settings.dart';
import 'package:ply/ui/analysis_controller.dart';

/// A UCI engine that answers each position from a script keyed by the moves
/// played from the start (scores relative to the side to move, as UCI
/// engines report them). With [hold] set, searches wait for [release] or a
/// `stop`, like a real engine thinking.
class FakeEngine implements EngineTransport {
  FakeEngine(this.script);
  final Map<String, (String, String)> script;
  final _out = StreamController<String>.broadcast(sync: true);
  final searched = <String>[];
  bool hold = false;
  String _moves = '';
  String? _pending;

  @override
  Stream<String> get lines => _out.stream;

  void release() {
    final m = _pending;
    _pending = null;
    if (m != null) _answer(m);
  }

  void _answer(String moves) {
    final (score, best) = script[moves] ?? ('cp 0', '0000');
    _out
      ..add('info depth 14 multipv 1 score $score pv $best')
      ..add('bestmove $best');
  }

  @override
  void send(String c) {
    scheduleMicrotask(() {
      if (c == 'uci') {
        _out
          ..add('id name FakeFish')
          ..add('uciok');
      } else if (c == 'isready') {
        _out.add('readyok');
      } else if (c.startsWith('position')) {
        final m = c.split(' moves ');
        _moves = m.length > 1 ? m[1].trim() : '';
      } else if (c.startsWith('go')) {
        searched.add(_moves);
        if (hold) {
          _pending = _moves;
        } else {
          _answer(_moves);
        }
      } else if (c == 'stop' && _pending != null) {
        // A stopped search reports what it has; Ply must not keep it.
        _pending = null;
        _out
          ..add('info depth 3 multipv 1 score cp 999 pv 0000')
          ..add('bestmove 0000');
      }
    });
  }

  @override
  Future<void> close() async {}
}

PositionAnalysis pa(Eval e, String? best) =>
    PositionAnalysis(eval: e, depth: 14, bestMove: best);

Move mv(String uci) => Move.parse(uci)!;

void main() {
  late Directory dir;
  late FakeEngine fake;
  late AnalysisController a;

  /// Lets the debounce timer and the scripted engine run.
  Future<void> settle() async {
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('ply_feedback');
    final f = fake = FakeEngine({
      'e2e4 e7e5': ('cp 30', 'g1f3'),
      'e2e4 e7e5 f2f3': ('cp 250', 'd8h4'), // Black to move, Black better
      'e2e4 e7e5 g1f3': ('cp -40', 'b8c6'), // Black to move: White +0.40
      'e2e4 e7e5 g1f3 f7f6': ('cp 120', 'f3e5'), // White to move: +1.20
    });
    final settings = Settings(dir);
    a = AnalysisController(
      engine: EngineService(connect: () async => f),
      store: GameStore(dir),
      settings: settings,
    );
  });
  tearDown(() {
    a.dispose();
    dir.deleteSync(recursive: true);
  });

  group('what-if moves on a loaded game', () {
    setUp(() => a.load(ChessGame.fromPgn('1. e4 e5 2. Nf3 Nc6')));

    test('a new move starts a what-if line and leaves the game alone', () {
      final before = a.game;
      a.goTo(2);
      a.userMove(mv('f2f3'));
      expect(a.game, same(before));
      expect(a.game.length, 4);
      expect(a.variation!.plies.map((p) => p.san), ['e4', 'e5', 'f3']);
      expect(a.branch, 2);
      expect(a.onWhatIf, isTrue);
      expect(a.ply, 3);
      expect(a.position.fen, a.variation!.last.fen);
    });

    test('the move is checked in the background and rated', () async {
      a.goTo(2);
      a.userMove(mv('f2f3'));
      expect(a.checking, isTrue); // pending state shows at once
      expect(a.lastMoveReview, isNull); // no rating before the engine says so
      await settle();
      expect(a.checking, isFalse);
      final m = a.lastMoveReview!;
      expect(m.cls, MoveClass.blunder);
      expect(m.bestSan, 'Nf3');
      expect(m.before.label, '+0.30');
      expect(m.after.label, '-2.50');
      // Both positions were searched at the review depth, nothing else.
      expect(fake.searched, ['e2e4 e7e5', 'e2e4 e7e5 f2f3']);
    });

    test('undo and back to game restore the original game', () async {
      a.goTo(2);
      a.userMove(mv('f2f3'));
      a.userMove(mv('d8h4'));
      expect(a.variation!.length, 4);
      a.undoWhatIf();
      expect(a.variation!.length, 3);
      expect(a.ply, 3);
      a.backToGame();
      expect(a.variation, isNull);
      expect(a.ply, 2);
      expect(a.game.plies.map((p) => p.san), ['e4', 'e5', 'Nf3', 'Nc6']);
      a.goTo(4);
      expect(a.position.fen, a.game.last.fen);
    });

    test('playing the game\'s own move rejoins the game', () {
      a.goTo(2);
      a.userMove(mv('g1f3'));
      expect(a.variation, isNull);
      expect(a.onWhatIf, isFalse);
      expect(a.ply, 3);
    });

    test('Black\'s move is judged from Black\'s side', () async {
      a.goTo(3);
      a.userMove(mv('f7f6'));
      await settle();
      final m = a.lastMoveReview!;
      expect(m.mover, Side.black);
      // White +0.40 -> +1.20 is worse for Black: about 7 points of chances.
      expect(m.loss, closeTo(7.1, 0.3));
      expect(m.cls, MoveClass.inaccuracy);
    });

    test('an unanalysed game move gets no made-up rating', () async {
      a.goTo(3);
      await settle();
      expect(a.lastMoveReview, isNull);
      expect(a.checking, isFalse);
      expect(fake.searched, isEmpty); // only what-if moves are auto-checked
    });

    test('a stale result never lands on a newer position', () async {
      fake.hold = true;
      a.goTo(2);
      a.userMove(mv('f2f3'));
      await settle(); // check is thinking about the position before f3
      a.goTo(1); // leave before it finishes: the search is stopped
      await settle();
      fake.hold = false;
      fake.release();
      await settle();
      // The stopped search (score 999) was thrown away.
      a.goTo(3);
      await settle();
      expect(a.lastMoveReview!.before.label, '+0.30');
      expect(a.lastMoveReview!.cls, MoveClass.blunder);
    });

    test('the stored review is reused and never changed', () async {
      final ps = [
        pa(const Eval.cp(20), 'e2e4'),
        pa(const Eval.cp(-30), 'e7e5'),
        pa(const Eval.cp(30), 'g1f3'),
        pa(const Eval.cp(-40), 'b8c6'),
        pa(const Eval.cp(35), 'f1c4'),
      ];
      a.review = GameReview(
        depth: 14,
        engine: 't',
        moves: [for (final p in a.game.plies) p.uci],
        positions: ps,
      );
      a.goTo(2);
      a.userMove(mv('f2f3'));
      await settle();
      // Only the new position needed the engine.
      expect(fake.searched, ['e2e4 e7e5 f2f3']);
      expect(a.lastMoveReview!.cls, MoveClass.blunder);
      expect(a.review!.positions, ps);
      expect(a.review!.matches(a.game), isTrue);
    });
  });

  group('free play (new board or FEN)', () {
    test('moves edit the board game, and are checked too', () async {
      // White is in check and Kh2 is the only legal move.
      a.load(ChessGame.fromFen('7k/8/8/8/8/8/6P1/r6K w - - 0 1'));
      fake.script[''] = ('cp -900', '0000');
      fake.script['h1h2'] = ('cp 950', 'a1a2');
      a.userMove(mv('h1h2'));
      expect(a.variation, isNull);
      expect(a.game.length, 1);
      await settle();
      // A losing position is not the move's fault when it was forced.
      expect(a.lastMoveReview!.cls, MoveClass.forced);
      expect(a.lastMoveReview!.loss, 0);
    });
  });

  group('classification rules', () {
    final g = ChessGame.fromPgn('1. e4 e5 2. f3');
    const t = Thresholds();

    test('a move in a lost position is not a blunder by itself', () {
      // White is being mated either way: no winning chances lost.
      final m = reviewMove(
        g,
        2,
        pa(const Eval.mate(4, whiteMates: false), 'd2d4'),
        pa(const Eval.mate(3, whiteMates: false), 'd8h4'),
        t,
      );
      expect(m.loss, 0);
      expect(m.cls.isError, isFalse);
    });

    test('allowing a forced mate is a blunder and says so', () {
      final m = reviewMove(
        g,
        2,
        pa(const Eval.cp(20), 'g1f3'),
        pa(const Eval.mate(2, whiteMates: false), 'd8h4'),
        t,
      );
      expect(m.cls, MoveClass.blunder);
      expect(m.tags, contains(MoveTag.allowedMate));
    });

    test('a large edge that stays large is not an error', () {
      // +8 to +6 for White: still completely winning.
      final m = reviewMove(
        g,
        2,
        pa(const Eval.cp(800), 'g1f3'),
        pa(const Eval.cp(600), 'd8h4'),
        t,
      );
      expect(m.cls.isError, isFalse);
    });

    test('reviewMoves and reviewMove agree', () {
      final ps = [
        pa(const Eval.cp(20), 'e2e4'),
        pa(const Eval.cp(-30), 'e7e5'),
        pa(const Eval.cp(30), 'g1f3'),
        pa(const Eval.cp(-250), 'd8h4'),
      ];
      final data = GameReview(
        depth: 14,
        engine: 't',
        moves: [for (final p in g.plies) p.uci],
        positions: ps,
      );
      final all = reviewMoves(g, data, t);
      for (var i = 0; i < g.length; i++) {
        expect(all[i]!.cls, reviewMove(g, i, ps[i], ps[i + 1], t).cls);
      }
    });
  });
}
