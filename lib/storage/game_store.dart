import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/foundation.dart';

import '../analysis/review.dart';
import '../chess/chess_game.dart';

String newId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
    '${Random().nextInt(1 << 20).toRadixString(36)}';

class SavedGame {
  SavedGame({
    required this.id,
    required this.pgn,
    required this.addedAt,
    this.myColor,
    this.review,
  });

  final String id;
  final String pgn;
  final DateTime addedAt;

  /// Which side the user played, when known. Insights only use these games.
  final Side? myColor;
  final GameReview? review;

  late final ChessGame game = ChessGame.fromPgn(pgn);

  Map<String, String> get headers => game.headers;

  String get title {
    final w = headers['White'], b = headers['Black'];
    if (w != null && w != '?' && b != null && b != '?') return '$w vs $b';
    final e = headers['Event'];
    if (e != null && e != '?') return e;
    return 'Game ${addedAt.toLocal().toString().substring(0, 16)}';
  }

  /// Game date from the PGN `Date`/`UTCDate` header, else when it was added.
  DateTime get date {
    final d = headers['UTCDate'] ?? headers['Date'];
    final m = d == null
        ? null
        : RegExp(r'^(\d{4})\.(\d{2})\.(\d{2})$').firstMatch(d);
    if (m != null) {
      return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    }
    return addedAt;
  }

  /// Result from the user's point of view: 'win', 'loss', 'draw' or null.
  String? get myResult {
    final r = game.result;
    if (myColor == null || r == '*') return null;
    if (r == '1/2-1/2') return 'draw';
    final whiteWon = r == '1-0';
    return whiteWon == (myColor == Side.white) ? 'win' : 'loss';
  }

  /// Lichess-style speed bucket from the `TimeControl` header
  /// (estimated duration = base + 40 × increment).
  String? get speed {
    final tc = headers['TimeControl'];
    final m = tc == null ? null : RegExp(r'^(\d+)(?:\+(\d+))?$').firstMatch(tc);
    if (m == null) return null;
    final secs = int.parse(m[1]!) + 40 * int.parse(m[2] ?? '0');
    if (secs < 180) return 'Bullet';
    if (secs < 480) return 'Blitz';
    if (secs < 1500) return 'Rapid';
    return 'Classical';
  }

  SavedGame copyWith({
    String? pgn,
    Side? myColor,
    bool clearMyColor = false,
    GameReview? review,
    bool clearReview = false,
  }) => SavedGame(
    id: id,
    pgn: pgn ?? this.pgn,
    addedAt: addedAt,
    myColor: clearMyColor ? null : (myColor ?? this.myColor),
    review: clearReview ? null : (review ?? this.review),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'pgn': pgn,
    'addedAt': addedAt.toIso8601String(),
    if (myColor != null) 'myColor': myColor!.name,
    if (review != null) 'review': review!.toJson(),
  };

  factory SavedGame.fromJson(Map<String, dynamic> j) => SavedGame(
    id: j['id'] as String,
    pgn: j['pgn'] as String,
    addedAt: DateTime.parse(j['addedAt'] as String),
    myColor: switch (j['myColor']) {
      'white' => Side.white,
      'black' => Side.black,
      _ => null,
    },
    review: j['review'] == null
        ? null
        : GameReview.fromJson(j['review'] as Map<String, dynamic>),
  );
}

/// A position the user wants to come back to.
class SavedPosition {
  SavedPosition({
    required this.id,
    required this.fen,
    required this.note,
    required this.addedAt,
    this.gameId,
    this.ply,
  });

  final String id;
  final String fen;
  final String note;
  final DateTime addedAt;
  final String? gameId;
  final int? ply;

  Map<String, dynamic> toJson() => {
    'id': id,
    'fen': fen,
    'note': note,
    'addedAt': addedAt.toIso8601String(),
    if (gameId != null) 'gameId': gameId,
    if (ply != null) 'ply': ply,
  };

  factory SavedPosition.fromJson(Map<String, dynamic> j) => SavedPosition(
    id: j['id'] as String,
    fen: j['fen'] as String,
    note: j['note'] as String? ?? '',
    addedAt: DateTime.parse(j['addedAt'] as String),
    gameId: j['gameId'] as String?,
    ply: j['ply'] as int?,
  );
}

/// Saved games and positions, kept in one JSON file in the app's documents
/// directory. Writes go to a temp file first and are renamed into place so a
/// crash mid-write cannot corrupt existing data.
class GameStore extends ChangeNotifier {
  GameStore(this.dir);

  final Directory dir;
  final List<SavedGame> _games = [];
  final List<SavedPosition> _positions = [];
  String? loadError;

  List<SavedGame> get games => List.unmodifiable(_games);
  List<SavedPosition> get positions => List.unmodifiable(_positions);

  File get _file => File('${dir.path}/ply_data.json');

  Future<void> load() async {
    if (!await _file.exists()) return;
    try {
      final j = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      _games
        ..clear()
        ..addAll([
          for (final g in j['games'] as List)
            SavedGame.fromJson(g as Map<String, dynamic>),
        ]);
      _positions
        ..clear()
        ..addAll([
          for (final p in j['positions'] as List? ?? const [])
            SavedPosition.fromJson(p as Map<String, dynamic>),
        ]);
    } catch (e) {
      // Keep the unreadable file instead of overwriting it on the next save.
      final backup =
          '${_file.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}';
      await _file.rename(backup);
      loadError = 'Saved data could not be read and was moved to $backup';
    }
    notifyListeners();
  }

  Future<void> _save() async {
    await dir.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({
        'version': 1,
        'games': [for (final g in _games) g.toJson()],
        'positions': [for (final p in _positions) p.toJson()],
      }),
      flush: true,
    );
    await tmp.rename(_file.path);
  }

  SavedGame? byId(String id) {
    for (final g in _games) {
      if (g.id == id) return g;
    }
    return null;
  }

  Future<void> upsert(SavedGame game) async {
    final i = _games.indexWhere((g) => g.id == game.id);
    if (i >= 0) {
      _games[i] = game;
    } else {
      _games.add(game);
    }
    notifyListeners();
    await _save();
  }

  Future<void> addAll(Iterable<SavedGame> games) async {
    _games.addAll(games);
    notifyListeners();
    await _save();
  }

  Future<void> delete(String id) async {
    _games.removeWhere((g) => g.id == id);
    notifyListeners();
    await _save();
  }

  Future<void> addPosition(SavedPosition p) async {
    _positions.add(p);
    notifyListeners();
    await _save();
  }

  Future<void> removePosition(String id) async {
    _positions.removeWhere((p) => p.id == id);
    notifyListeners();
    await _save();
  }

  /// Guesses which side the user played from the PGN player names.
  static Side? detectColor(ChessGame g, List<String> usernames) {
    final names = usernames
        .map((u) => u.trim().toLowerCase())
        .where((u) => u.isNotEmpty);
    final w = g.headers['White']?.toLowerCase();
    final b = g.headers['Black']?.toLowerCase();
    if (names.contains(w)) return Side.white;
    if (names.contains(b)) return Side.black;
    return null;
  }
}
