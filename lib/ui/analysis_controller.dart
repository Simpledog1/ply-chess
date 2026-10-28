import 'dart:async';

import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

import '../analysis/eval.dart';
import '../analysis/openings.dart';
import '../analysis/review.dart';
import '../analysis/review_runner.dart';
import '../chess/chess_game.dart';
import '../engine/engine_service.dart';
import '../engine/uci.dart';
import '../online/online_games.dart';
import '../storage/game_store.dart';
import '../storage/settings.dart';

/// State of the Analyze screen: the game, the shown ply, live engine output
/// and the game review.
class AnalysisController extends ChangeNotifier {
  AnalysisController({
    required this.engine,
    required this.store,
    required this.settings,
  }) {
    settings.addListener(_onSettings);
  }

  final EngineService engine;
  final GameStore store;
  final Settings settings;

  ChessGame game = ChessGame.standard();
  int ply = 0;
  Side orientation = Side.white;

  /// Id of the saved game this board belongs to, if any.
  String? savedId;
  bool dirty = false;

  GameReview? review;
  List<MoveReview?> moveReviews = const [];

  bool engineOn = false;
  SearchResult? live;
  int? _liveForPly;
  String? engineError;
  int _liveToken = 0;
  Timer? _throttle;
  Timer? _debounce;

  bool reviewing = false;
  int reviewingDepth = 0;
  bool _cancelReview = false;

  /// Profile key of the site account the game was loaded for, if any.
  String? gameProfile;

  /// Opening book, loaded in the background at startup.
  OpeningBook? get book => bookLoaded.value;

  /// Notifies once the opening book is available.
  final bookLoaded = ValueNotifier<OpeningBook?>(null);

  bool get autoplaying => _autoplay != null;
  Timer? _autoplay;

  /// Engine line being previewed on the board: positions after each PV move.
  List<Position>? preview;
  List<String>? previewSans;
  List<String>? previewUcis;
  int previewIndex = 0;

  Thresholds get _t => settings.thresholds;
  Position get position => game.positionAt(ply);
  Position get shownPosition => preview?[previewIndex] ?? position;
  SavedGame? get saved => savedId == null ? null : store.byId(savedId!);

  /// Live result for the current ply only (never a stale one).
  SearchResult? get liveHere => _liveForPly == ply ? live : null;

  /// Best evaluation available for the shown position: live engine, then the
  /// stored review, then the rules (mate/stalemate).
  Eval? get currentEval {
    if (preview != null) return null;
    final l = liveHere?.best?.eval;
    if (l != null) return l;
    final r = reviewHere;
    if (r != null) return r.eval;
    return terminalEval(position);
  }

  PositionAnalysis? get reviewHere =>
      review != null && ply < review!.positions.length
      ? review!.positions[ply]
      : null;

  /// Review of the move that led to the current position.
  MoveReview? get lastMoveReview =>
      ply > 0 && ply - 1 < moveReviews.length ? moveReviews[ply - 1] : null;

  /// Opening name from the book, else the PGN header.
  String? get openingName {
    final o = book?.openingOf(game);
    if (o != null) return '${o.$1} ${o.$2}';
    final h = game.headers['Opening'];
    return h == null || h == '?' ? null : h;
  }

  void setBook(OpeningBook b) {
    bookLoaded.value = b;
    _refreshReview();
    notifyListeners();
  }

  List<MoveReview?> _review(GameReview r) =>
      reviewMoves(game, r, _t, options: settings.classOptions, book: book);

  // --- navigation & editing ------------------------------------------------

  /// Steps through the game one move per second.
  void toggleAutoplay() {
    if (_autoplay != null) {
      _stopAutoplay();
      notifyListeners();
      return;
    }
    if (ply >= game.length) goTo(0);
    _autoplay = Timer.periodic(const Duration(seconds: 1), (_) {
      if (ply >= game.length) {
        _stopAutoplay();
        notifyListeners();
      } else {
        _go(ply + 1);
      }
    });
    notifyListeners();
  }

  void _stopAutoplay() {
    _autoplay?.cancel();
    _autoplay = null;
  }

  void goTo(int p) {
    _stopAutoplay();
    _go(p);
  }

  void _go(int p) {
    p = p.clamp(0, game.length);
    if (p == ply && preview == null) return;
    ply = p;
    _clearPreview();
    notifyListeners();
    _scheduleLive();
  }

  void flip() {
    orientation = orientation.opposite;
    notifyListeners();
  }

  /// Plays a move from the board. Returns the previous game if later moves
  /// were discarded, so the UI can offer an undo.
  ChessGame? userMove(Move move) {
    final next = game.play(ply, move);
    if (next == null) return null;
    final truncated = next != game && ply < game.length ? game : null;
    _setGame(next, ply + 1);
    return truncated;
  }

  void restore(ChessGame previous, int atPly) => _setGame(previous, atPly);

  void _setGame(ChessGame next, int atPly) {
    if (!identical(next, game)) dirty = true;
    game = next;
    ply = atPly.clamp(0, game.length);
    _refreshReview();
    _clearPreview();
    notifyListeners();
    _scheduleLive();
  }

  void load(
    ChessGame g, {
    SavedGame? from,
    int atPly = 0,
    Side? orientation,
    String? profile,
  }) {
    cancelReview();
    _stopAutoplay();
    game = g;
    ply = atPly.clamp(0, g.length);
    savedId = from?.id;
    gameProfile = profile ?? from?.profile;
    dirty = false;
    review = from?.review;
    this.orientation = orientation ?? from?.myColor ?? Side.white;
    _refreshReview();
    _clearPreview();
    live = null;
    notifyListeners();
    _scheduleLive();
  }

  void loadSaved(SavedGame s, {int atPly = 0}) =>
      load(s.game, from: s, atPly: atPly);

  /// Opens a game fetched for [profile]. A copy kept in local history (same
  /// game URL) is reopened with its saved analysis.
  void openOnline(OnlineGame g, {required String profile}) {
    final stored = _findStored(g.game);
    if (stored != null) return loadSaved(stored);
    load(
      g.game,
      profile: profile,
      orientation: GameStore.detectColor(g.game, settings.myNames),
    );
  }

  /// The saved copy of [g], matched by its game URL.
  SavedGame? _findStored(ChessGame g) {
    final link = _link(g);
    if (link == null) return null;
    for (final s in store.games) {
      if (_link(s.game) == link) return s;
    }
    return null;
  }

  static String? _link(ChessGame g) {
    final l = g.headers['Link'] ?? g.headers['Site'];
    return l != null && l.startsWith('http') ? l : null;
  }

  void newGame() => load(ChessGame.standard());

  void _refreshReview() {
    if (review != null && !review!.matches(game)) {
      // Moves changed: keep the analysed positions that still apply.
      review = _realign(review!, game);
    }
    moveReviews = review == null ? const [] : _review(review!);
  }

  static GameReview? _realign(GameReview r, ChessGame g) {
    var common = 0;
    while (common < r.moves.length &&
        common < g.length &&
        r.moves[common] == g.plies[common].uci) {
      common++;
    }
    if (common == 0 && r.positions.first == null) return null;
    return GameReview(
      depth: r.depth,
      engine: r.engine,
      moves: [for (final p in g.plies) p.uci],
      positions: [
        for (var i = 0; i <= g.length; i++) i <= common ? r.positions[i] : null,
      ],
      createdAt: r.createdAt,
    );
  }

  void _onSettings() {
    _refreshReview();
    notifyListeners();
  }

  // --- saving ----------------------------------------------------------------

  /// Writes the game (and its analysis) to local history.
  Future<SavedGame> save({bool asNew = false}) async {
    final existing = asNew ? null : saved ?? _findStored(game);
    final s = existing == null
        ? SavedGame(
            id: newId(),
            pgn: game.toPgn(),
            addedAt: DateTime.now(),
            myColor: GameStore.detectColor(game, settings.myNames),
            review: review,
            profile: gameProfile,
          )
        : existing.copyWith(
            pgn: game.toPgn(),
            review: review,
            clearReview: review == null,
          );
    await store.upsert(s);
    savedId = s.id;
    dirty = false;
    notifyListeners();
    return s;
  }

  String exportPgn() {
    final comments = <int, String>{};
    final nags = <int, int>{};
    for (final m in moveReviews) {
      if (m == null) continue;
      final nag = switch (m.cls) {
        MoveClass.inaccuracy => 6,
        MoveClass.mistake => 2,
        MoveClass.blunder => 4,
        _ => null,
      };
      if (nag != null) {
        nags[m.ply] = nag;
        comments[m.ply] =
            '${m.cls.label}. ${m.explanation} [Stockfish depth ${m.depth}]';
      }
    }
    return game.toPgn(comments: comments, nags: nags);
  }

  // --- live engine -----------------------------------------------------------

  void toggleEngine() {
    engineOn = !engineOn;
    if (!engineOn) {
      _liveToken++;
      engine.stop();
    }
    notifyListeners();
    _scheduleLive();
  }

  void _scheduleLive() {
    _debounce?.cancel();
    if (!engineOn || reviewing) return;
    _liveToken++;
    engine.stop();
    _debounce = Timer(const Duration(milliseconds: 120), _runLive);
  }

  Future<void> _runLive() async {
    final token = ++_liveToken;
    final atPly = ply;
    final pos = position;
    if (pos.isGameOver) {
      live = null;
      _liveForPly = null;
      notifyListeners();
      return;
    }
    try {
      final e = await engine.engine;
      if (token != _liveToken) return;
      engineError = null;
      final r = await e.search(
        fen: game.initialFen,
        moves: game.ucisBefore(atPly),
        turn: pos.turn,
        depth: settings.timeLimitOn ? null : settings.liveDepth,
        movetime: settings.timeLimitOn
            ? Duration(seconds: settings.timeLimitSec)
            : null,
        multiPv: settings.multiPv,
        onUpdate: (p) {
          if (token != _liveToken) return;
          live = p;
          _liveForPly = atPly;
          _throttle ??= Timer(const Duration(milliseconds: 150), () {
            _throttle = null;
            notifyListeners();
          });
        },
      );
      if (token != _liveToken) return;
      if (r.best != null) {
        live = r;
        _liveForPly = atPly;
      }
      notifyListeners();
    } on EngineException catch (e) {
      engineError = e.message;
      engineOn = false;
      notifyListeners();
    } catch (e) {
      engineError = engine.error ?? '$e';
      engineOn = false;
      notifyListeners();
    }
  }

  // --- review ----------------------------------------------------------------

  /// Analyses the whole game at the review depth (or [depth] for a deeper
  /// review). Results stay in memory; with local history on, the game and
  /// its analysis are also saved.
  Future<void> startReview({int? depth}) async {
    if (reviewing || game.length == 0) return;
    reviewing = true;
    reviewingDepth = depth ?? settings.reviewDepth;
    _cancelReview = false;
    _liveToken++;
    engine.stop();
    engineError = null;
    notifyListeners();
    try {
      if (settings.saveHistory) await save();
      final e = await engine.engine;
      final reviewedGame = game;
      final result = await runReview(
        engine: e,
        game: reviewedGame,
        depth: reviewingDepth,
        resume: review,
        isCancelled: () => _cancelReview || !identical(game, reviewedGame),
        onProgress: (partial) {
          if (!identical(game, reviewedGame)) return;
          review = partial;
          moveReviews = _review(partial);
          notifyListeners();
        },
      );
      if (identical(game, reviewedGame)) {
        review = result;
        _refreshReview();
        final s = saved;
        if (s != null && settings.saveHistory) {
          await store.upsert(s.copyWith(review: result));
        }
      }
    } on EngineException catch (e) {
      engineError = e.message;
    } catch (e) {
      engineError = engine.error ?? '$e';
    } finally {
      reviewing = false;
      notifyListeners();
      _scheduleLive();
    }
  }

  void cancelReview() {
    if (!reviewing) return;
    _cancelReview = true;
    engine.stop();
  }

  double get reviewProgress =>
      review == null ? 0 : review!.analysedCount / review!.positions.length;

  // --- engine line preview -------------------------------------------------

  void previewLine(List<String> ucis, int index) {
    final positions = <Position>[];
    final sans = <String>[];
    var p = position;
    for (final u in ucis) {
      final m = Move.parse(u);
      if (m == null || !p.isLegal(m)) break;
      final (next, san) = p.makeSan(m);
      positions.add(next);
      sans.add(san);
      p = next;
    }
    if (positions.isEmpty) return;
    preview = positions;
    previewSans = sans;
    previewUcis = ucis.take(positions.length).toList();
    previewIndex = index.clamp(0, positions.length - 1);
    notifyListeners();
  }

  void previewStep(int delta) {
    if (preview == null) return;
    previewIndex = (previewIndex + delta).clamp(0, preview!.length - 1);
    notifyListeners();
  }

  void closePreview() {
    _clearPreview();
    notifyListeners();
  }

  /// Adds the previewed engine moves (up to the shown one) to the game.
  void playPreview() {
    final ucis = previewUcis;
    if (ucis == null) return;
    var g = game;
    var p = ply;
    for (final u in ucis.take(previewIndex + 1)) {
      final next = g.playUci(p, u);
      if (next == null) break;
      g = next;
      p++;
    }
    _setGame(g, p);
  }

  void _clearPreview() {
    preview = null;
    previewSans = null;
    previewUcis = null;
    previewIndex = 0;
  }

  @override
  void dispose() {
    settings.removeListener(_onSettings);
    _stopAutoplay();
    _throttle?.cancel();
    _debounce?.cancel();
    super.dispose();
  }
}
