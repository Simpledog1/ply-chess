import 'dart:async';

import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ply/analysis/eval.dart';
import 'package:ply/engine/uci.dart';

/// Scripted engine: replies to commands like a UCI engine would.
class FakeEngine implements EngineTransport {
  FakeEngine({this.respond = true});
  final bool respond;
  final _out = StreamController<String>.broadcast(sync: true);
  final sent = <String>[];
  List<String> searchOutput = [];
  bool holdSearch = false;

  @override
  Stream<String> get lines => _out.stream;

  void emit(String l) => _out.add(l);

  @override
  void send(String c) {
    sent.add(c);
    if (!respond) return;
    scheduleMicrotask(() {
      if (c == 'uci') {
        emit('id name FakeFish 1');
        emit('uciok');
      } else if (c == 'isready') {
        emit('readyok');
      } else if (c.startsWith('go')) {
        searchOutput.forEach(emit);
        if (!holdSearch) emit('bestmove e2e4 ponder e7e5');
      } else if (c == 'stop' && holdSearch) {
        emit('bestmove d2d4');
      }
    });
  }

  @override
  Future<void> close() => _out.close();
}

void main() {
  group('SearchInfo.parse', () {
    test('cp score from white to move', () {
      final i = SearchInfo.parse(
        'info depth 20 seldepth 28 multipv 1 score cp 34 nodes 1000 nps 500 pv e2e4 e7e5',
        Side.white,
      )!;
      expect(i.depth, 20);
      expect(i.selDepth, 28);
      expect(i.eval, const Eval.cp(34));
      expect(i.pv, ['e2e4', 'e7e5']);
    });

    test('scores are converted to White perspective when Black moves', () {
      final i = SearchInfo.parse(
        'info depth 10 score cp 50 pv e7e5',
        Side.black,
      )!;
      expect(i.eval.cp, -50);
      final m = SearchInfo.parse(
        'info depth 10 score mate 2 pv d8h4',
        Side.black,
      )!;
      expect(m.eval.isMate, isTrue);
      expect(m.eval.whiteMates, isFalse);
      expect(m.eval.label, '#-2');
      final mated = SearchInfo.parse(
        'info depth 10 score mate -3 pv a2a3',
        Side.black,
      )!;
      expect(mated.eval.whiteMates, isTrue);
    });

    test('ignores bound scores, currmove and strings', () {
      expect(
        SearchInfo.parse(
          'info depth 5 score cp 20 lowerbound pv e2e4',
          Side.white,
        ),
        isNull,
      );
      expect(
        SearchInfo.parse(
          'info depth 5 currmove e2e4 currmovenumber 1',
          Side.white,
        ),
        isNull,
      );
      expect(
        SearchInfo.parse(
          'info string NNUE evaluation using nn.nnue',
          Side.white,
        ),
        isNull,
      );
    });
  });

  group('UciEngine', () {
    test('init handshake sets options and reads name', () async {
      final t = FakeEngine();
      final e = UciEngine(t);
      await e.init(threads: 3, hashMb: 16);
      expect(e.name, 'FakeFish 1');
      expect(
        t.sent,
        containsAllInOrder([
          'uci',
          'setoption name Threads value 3',
          'setoption name Hash value 16',
          'isready',
        ]),
      );
    });

    test('search returns final line and best move', () async {
      final t = FakeEngine()
        ..searchOutput = [
          'info depth 1 score cp 10 pv d2d4',
          'info depth 2 score cp 30 pv e2e4 e7e5',
        ];
      final e = UciEngine(t);
      await e.init();
      final updates = <int>[];
      final r = await e.search(
        fen: Chess.initial.fen,
        turn: Side.white,
        depth: 2,
        onUpdate: (p) => updates.add(p.depth),
      );
      expect(r.complete, isTrue);
      expect(r.bestMove, 'e2e4');
      expect(r.best!.eval.cp, 30);
      expect(updates, [1, 2]);
      expect(t.sent, contains('go depth 2'));
      expect(
        t.sent.where((s) => s.startsWith('position fen')).single,
        'position fen ${Chess.initial.fen}',
      );
    });

    test('moves are appended to the position command', () async {
      final t = FakeEngine()
        ..searchOutput = ['info depth 1 score cp 0 pv g1f3'];
      final e = UciEngine(t);
      await e.init();
      await e.search(
        fen: Chess.initial.fen,
        moves: ['e2e4', 'e7e5'],
        turn: Side.white,
        depth: 1,
      );
      expect(
        t.sent,
        contains('position fen ${Chess.initial.fen} moves e2e4 e7e5'),
      );
    });

    test('stop gives a partial, stopped result', () async {
      final t = FakeEngine()
        ..holdSearch = true
        ..searchOutput = ['info depth 7 score cp 12 pv d2d4'];
      final e = UciEngine(t);
      await e.init();
      final f = e.search(fen: Chess.initial.fen, turn: Side.white);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      e.stop();
      final r = await f;
      expect(r.stopped, isTrue);
      expect(r.complete, isFalse);
      expect(r.depth, 7);
    });

    test('a newer search supersedes a queued one', () async {
      final t = FakeEngine()
        ..searchOutput = ['info depth 1 score cp 5 pv e2e4'];
      final e = UciEngine(t);
      await e.init();
      final first = e.search(
        fen: Chess.initial.fen,
        turn: Side.white,
        depth: 1,
      );
      final second = e.search(
        fen: Chess.initial.fen,
        turn: Side.white,
        depth: 1,
      );
      final r1 = await first;
      final r2 = await second;
      expect(r1.stopped, isTrue);
      expect(r2.complete, isTrue);
      expect(t.sent.where((s) => s.startsWith('go')).length, 1);
    });

    test('engine crash fails pending work with EngineException', () async {
      final t = FakeEngine()..holdSearch = true;
      final e = UciEngine(t);
      await e.init();
      final f = e.search(fen: Chess.initial.fen, turn: Side.white);
      await Future<void>.delayed(Duration.zero);
      await t.close();
      await expectLater(f, throwsA(isA<EngineException>()));
      expect(e.isAlive, isFalse);
      await expectLater(
        e.search(fen: Chess.initial.fen, turn: Side.white, depth: 1),
        throwsA(isA<EngineException>()),
      );
    });

    test('unresponsive engine times out', () async {
      final e = UciEngine(FakeEngine(respond: false));
      await expectLater(
        e.init(timeout: const Duration(milliseconds: 50)),
        throwsA(isA<EngineException>()),
      );
    });
  });

  group('Eval', () {
    test('win percent is symmetric and bounded', () {
      expect(const Eval.cp(0).whiteWinPercent, closeTo(50, 1e-9));
      final w = const Eval.cp(300).whiteWinPercent;
      expect(w, greaterThan(70));
      expect(const Eval.cp(-300).whiteWinPercent, closeTo(100 - w, 1e-9));
      expect(
        const Eval.cp(300).winPercentFor(Side.black),
        closeTo(100 - w, 1e-9),
      );
      expect(const Eval.mate(3, whiteMates: true).whiteWinPercent, 100);
      expect(
        const Eval.mate(3, whiteMates: false).winPercentFor(Side.black),
        100,
      );
    });

    test('labels', () {
      expect(const Eval.cp(34).label, '+0.34');
      expect(const Eval.cp(-120).label, '-1.20');
      expect(const Eval.mate(0, whiteMates: true).label, '1-0');
    });

    test('json round trip', () {
      for (final e in [
        const Eval.cp(-7),
        const Eval.mate(4, whiteMates: false),
      ]) {
        expect(Eval.fromJson(e.toJson()), e);
      }
    });
  });
}
