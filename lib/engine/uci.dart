import 'dart:async';

import 'package:dartchess/dartchess.dart';

import '../analysis/eval.dart';

/// Line-based connection to a UCI engine (a process in the app, a fake in tests).
abstract class EngineTransport {
  Stream<String> get lines;
  void send(String command);
  Future<void> close();
}

class EngineException implements Exception {
  final String message;
  EngineException(this.message);
  @override
  String toString() => 'EngineException: $message';
}

/// One `info ... score ... pv ...` line from the engine.
class SearchInfo {
  final int depth;
  final int? selDepth;
  final int multiPv;
  final Eval eval;
  final List<String> pv;
  final int? nodes;
  final int? nps;

  const SearchInfo({
    required this.depth,
    this.selDepth,
    this.multiPv = 1,
    required this.eval,
    required this.pv,
    this.nodes,
    this.nps,
  });

  /// Parses a UCI info line. Returns null for lines without an exact score
  /// and PV (e.g. `currmove` updates or aspiration-window bound scores).
  /// [turn] is the side to move in the searched position, used to convert the
  /// side-relative UCI score to White's perspective.
  static SearchInfo? parse(String line, Side turn) {
    if (!line.startsWith('info ')) return null;
    final t = line.split(RegExp(r'\s+'));
    int? depth, selDepth, nodes, nps, cp, mate;
    var multiPv = 1;
    var bound = false;
    List<String>? pv;
    for (var i = 1; i < t.length; i++) {
      switch (t[i]) {
        case 'depth':
          depth = int.tryParse(t[++i]);
        case 'seldepth':
          selDepth = int.tryParse(t[++i]);
        case 'multipv':
          multiPv = int.tryParse(t[++i]) ?? 1;
        case 'nodes':
          nodes = int.tryParse(t[++i]);
        case 'nps':
          nps = int.tryParse(t[++i]);
        case 'score':
          final kind = t[++i];
          final v = int.tryParse(t[++i]);
          if (kind == 'cp') cp = v;
          if (kind == 'mate') mate = v;
        case 'lowerbound' || 'upperbound':
          bound = true;
        case 'string':
          return null;
        case 'pv':
          pv = t.sublist(i + 1);
          i = t.length;
      }
    }
    if (depth == null || bound || (cp == null && mate == null)) return null;
    return SearchInfo(
      depth: depth,
      selDepth: selDepth,
      multiPv: multiPv,
      eval: Eval.fromUci(cp: cp, mate: mate, turn: turn),
      pv: pv ?? const [],
      nodes: nodes,
      nps: nps,
    );
  }
}

/// The state of a search: the latest line per MultiPV slot and, once the
/// engine replied with `bestmove`, the final best move.
class SearchResult {
  final List<SearchInfo> lines;
  final String? bestMove;
  final bool finished;
  final bool stopped;
  final int? targetDepth;

  const SearchResult({
    required this.lines,
    this.bestMove,
    this.finished = false,
    this.stopped = false,
    this.targetDepth,
  });

  SearchInfo? get best => lines.isEmpty ? null : lines.first;
  int get depth => best?.depth ?? 0;

  /// True only when the engine ended the search on its own (depth or time
  /// limit reached). A stopped or still-running search is partial and must be
  /// shown as such.
  bool get complete => finished && !stopped && best != null;
}

/// A minimal UCI client. One search runs at a time; starting a new search
/// stops the current one first.
class UciEngine {
  UciEngine(this._transport) {
    _sub = _transport.lines.listen(_onLine, onDone: _onDone);
  }

  final EngineTransport _transport;
  late final StreamSubscription<String> _sub;
  final _waiters = <(bool Function(String), Completer<String>)>[];
  Future<void> _queue = Future.value();
  _ActiveSearch? _active;
  int? _multiPv;
  int _generation = 0;
  bool _dead = false;

  String? name;
  bool get isAlive => !_dead;

  Future<void> init({
    int threads = 1,
    int hashMb = 32,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    _transport.send('uci');
    await _waitFor((l) => l == 'uciok', timeout);
    _transport.send('setoption name Threads value $threads');
    _transport.send('setoption name Hash value $hashMb');
    await isReady(timeout: timeout);
  }

  Future<void> isReady({Duration timeout = const Duration(seconds: 15)}) {
    _transport.send('isready');
    return _waitFor((l) => l == 'readyok', timeout);
  }

  /// Tells the engine a new, unrelated game starts (clears its hash).
  Future<void> newGame() => _enqueue(() async {
    _transport.send('ucinewgame');
    await isReady();
  });

  /// Searches [fen] (optionally followed by [moves] in UCI notation).
  /// [turn] is the side to move in the final position. Give [depth],
  /// [movetime], or neither for an infinite search that runs until [stop].
  Future<SearchResult> search({
    required String fen,
    List<String> moves = const [],
    required Side turn,
    int? depth,
    Duration? movetime,
    int multiPv = 1,
    void Function(SearchResult partial)? onUpdate,
  }) {
    stop();
    final gen = ++_generation;
    // A newer search() call supersedes this one before it starts.
    SearchResult skipped() => SearchResult(
      lines: const [],
      finished: true,
      stopped: true,
      targetDepth: depth,
    );
    return _enqueue(() async {
      if (_dead) throw EngineException('Engine is not running');
      if (gen != _generation) return skipped();
      if (_multiPv != multiPv) {
        _transport.send('setoption name MultiPV value $multiPv');
        _multiPv = multiPv;
      }
      _transport.send(
        'position fen $fen${moves.isEmpty ? '' : ' moves ${moves.join(' ')}'}',
      );
      await isReady();
      if (gen != _generation) return skipped();
      final s = _ActiveSearch(turn, depth, onUpdate);
      _active = s;
      _transport.send(
        depth != null
            ? 'go depth $depth'
            : movetime != null
            ? 'go movetime ${movetime.inMilliseconds}'
            : 'go infinite',
      );
      return s.done.future;
    });
  }

  /// Stops the running search, if any. Its future completes with a partial
  /// result marked `stopped`.
  void stop() {
    final s = _active;
    if (s != null && !s.stopRequested) {
      s.stopRequested = true;
      _transport.send('stop');
    }
  }

  Future<void> dispose() async {
    stop();
    _transport.send('quit');
    await _sub.cancel();
    await _transport.close();
    _fail('Engine closed');
  }

  Future<T> _enqueue<T>(Future<T> Function() task) {
    final result = _queue.then((_) => task());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<String> _waitFor(bool Function(String) test, Duration timeout) {
    if (_dead) return Future.error(EngineException('Engine is not running'));
    final c = Completer<String>();
    final entry = (test, c);
    _waiters.add(entry);
    return c.future.timeout(
      timeout,
      onTimeout: () {
        _waiters.remove(entry);
        throw EngineException('Engine did not respond in time');
      },
    );
  }

  void _onLine(String raw) {
    final line = raw.trim();
    if (line.isEmpty) return;
    if (line.startsWith('id name ')) name = line.substring(8);
    for (final w in List.of(_waiters)) {
      if (w.$1(line)) {
        _waiters.remove(w);
        w.$2.complete(line);
      }
    }
    final s = _active;
    if (s == null) return;
    if (line.startsWith('info ')) {
      final info = SearchInfo.parse(line, s.turn);
      if (info == null) return;
      s.lines[info.multiPv] = info;
      s.onUpdate?.call(s.result());
    } else if (line.startsWith('bestmove')) {
      final parts = line.split(' ');
      // "(none)" and the null move "0000" both mean there is no move.
      final move =
          parts.length > 1 && parts[1] != '(none)' && parts[1] != '0000'
          ? parts[1]
          : null;
      _active = null;
      s.done.complete(s.result(bestMove: move, finished: true));
    }
  }

  void _onDone() => _fail('Engine process exited');

  void _fail(String why) {
    if (_dead) return;
    _dead = true;
    for (final w in _waiters) {
      w.$2.completeError(EngineException(why));
    }
    _waiters.clear();
    final s = _active;
    _active = null;
    if (s != null && !s.done.isCompleted) {
      s.done.completeError(EngineException(why));
    }
  }
}

class _ActiveSearch {
  _ActiveSearch(this.turn, this.targetDepth, this.onUpdate);
  final Side turn;
  final int? targetDepth;
  final void Function(SearchResult)? onUpdate;
  final lines = <int, SearchInfo>{};
  final done = Completer<SearchResult>();
  bool stopRequested = false;

  SearchResult result({String? bestMove, bool finished = false}) {
    final sorted = lines.keys.toList()..sort();
    return SearchResult(
      lines: [for (final k in sorted) lines[k]!],
      bestMove: bestMove,
      finished: finished,
      stopped: stopRequested,
      targetDepth: targetDepth,
    );
  }
}
