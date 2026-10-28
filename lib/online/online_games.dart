import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../chess/chess_game.dart';

/// The sites Ply can load public games from.
enum ChessSite {
  lichess('Lichess'),
  chessCom('Chess.com');

  const ChessSite(this.label);
  final String label;
}

/// Accepted username characters on both sites (letters, digits, _ and -).
final _validName = RegExp(r'^[A-Za-z0-9_-]{2,30}$');

/// Trims and checks a username. Throws [OnlineException] when it cannot be
/// a valid name on either site.
String checkUsername(String username) {
  final u = username.trim();
  if (!_validName.hasMatch(u)) {
    throw const OnlineException(
      'Usernames use 2–30 letters, digits, "_" or "-"',
    );
  }
  return u;
}

/// Profile identity: the site plus the case-insensitive username. The same
/// name on Lichess and Chess.com is two different profiles.
String profileKey(ChessSite site, String username) =>
    '${site.name}:${username.trim().toLowerCase()}';

class HttpReply {
  const HttpReply(this.status, this.body);
  final int status;
  final String body;
}

/// Minimal GET used for all API calls, swappable in tests.
typedef HttpGet = Future<HttpReply> Function(Uri uri, String accept);

const _agent = 'Ply/1.1 (personal chess analysis app)';
const _timeout = Duration(seconds: 20);

Future<HttpReply> _ioGet(Uri uri, String accept) async {
  final client = HttpClient()..connectionTimeout = _timeout;
  try {
    final req = await client.getUrl(uri).timeout(_timeout);
    req.headers
      ..set(HttpHeaders.userAgentHeader, _agent)
      ..set(HttpHeaders.acceptHeader, accept);
    final res = await req.close().timeout(_timeout);
    final body = await res.transform(utf8.decoder).join().timeout(_timeout);
    return HttpReply(res.statusCode, body);
  } finally {
    client.close(force: true);
  }
}

class OnlineException implements Exception {
  const OnlineException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A public game fetched from a site.
class OnlineGame {
  OnlineGame(this.game);
  final ChessGame game;

  Map<String, String> get headers => game.headers;

  /// Stable id: the game's URL on the site.
  String get id => headers['Link'] ?? headers['Site'] ?? game.toPgn();

  /// Start time from the UTC headers, else the date.
  DateTime? get playedAt {
    final d = headers['UTCDate'] ?? headers['Date'];
    final m = d == null
        ? null
        : RegExp(r'^(\d{4})\.(\d{2})\.(\d{2})$').firstMatch(d);
    if (m == null) return null;
    final t = RegExp(r'^(\d{2}):(\d{2}):(\d{2})$')
        .firstMatch(headers['UTCTime'] ?? headers['StartTime'] ?? '');
    return DateTime.utc(
      int.parse(m[1]!),
      int.parse(m[2]!),
      int.parse(m[3]!),
      t == null ? 0 : int.parse(t[1]!),
      t == null ? 0 : int.parse(t[2]!),
      t == null ? 0 : int.parse(t[3]!),
    );
  }
}

/// Recent public games of one profile, fetched page by page (newest first)
/// so whole account histories are never downloaded.
class GameFeed {
  GameFeed(this.site, String username, {HttpGet? get, this.pageSize = 20})
    : username = checkUsername(username),
      _get = get ?? _ioGet;

  final ChessSite site;
  final String username;
  final int pageSize;
  final HttpGet _get;

  final List<OnlineGame> games = [];
  final _seen = <String>{};

  /// Games the PGN parser could not read (e.g. variants); not shown.
  int skipped = 0;
  bool hasMore = true;
  bool _validated = false;
  String? displayName;

  // Chess.com paging state: monthly archive URLs, newest first.
  List<String>? _archives;
  int _nextArchive = 0;
  final List<String> _pending = [];

  // Lichess paging state: fetch games started before this time (ms).
  int? _until;

  String get key => profileKey(site, username);

  /// Confirms the account exists and is reachable.
  Future<void> validate() async {
    if (_validated) return;
    if (site == ChessSite.lichess) {
      final j = await _json(
        Uri.https('lichess.org', '/api/user/${username.toLowerCase()}'),
      );
      if (j['disabled'] == true || j['closed'] == true) {
        throw OnlineException('The Lichess account "$username" is closed');
      }
      displayName = j['username'] as String? ?? username;
    } else {
      final j = await _json(
        Uri.https('api.chess.com', '/pub/player/${username.toLowerCase()}'),
      );
      // Chess.com reports the name in lower case; keep the user's spelling.
      displayName = (j['username'] as String?) == username.toLowerCase()
          ? username
          : j['username'] as String? ?? username;
    }
    _validated = true;
  }

  /// Fetches the next page of games. Returns how many were added.
  Future<int> loadMore() async {
    if (!hasMore) return 0;
    await validate();
    final pgns = site == ChessSite.lichess
        ? await _lichessPage()
        : await _chessComPage();
    var added = 0;
    for (final p in pgns) {
      try {
        final g = OnlineGame(ChessGame.fromPgn(p));
        if (_seen.add(g.id)) {
          games.add(g);
          added++;
        }
      } on FormatException {
        skipped++;
      }
    }
    return added;
  }

  Future<List<String>> _lichessPage() async {
    final text = await _text(
      Uri.https('lichess.org', '/api/games/user/${username.toLowerCase()}', {
        'max': '$pageSize',
        'perfType': 'ultraBullet,bullet,blitz,rapid,classical,correspondence',
        'opening': 'true',
        'clocks': 'false',
        'evals': 'false',
        'until': ?_until?.toString(),
      }),
      'application/x-chess-pgn',
    );
    final pgns = splitPgn(text!);
    if (pgns.length < pageSize) hasMore = false;
    if (pgns.isNotEmpty) {
      try {
        final last = OnlineGame(ChessGame.fromPgn(pgns.last)).playedAt;
        if (last != null) _until = last.millisecondsSinceEpoch - 1;
      } on FormatException {
        hasMore = false;
      }
    }
    return pgns;
  }

  Future<List<String>> _chessComPage() async {
    final archives = _archives ??= [
      ...(((await _json(
                    Uri.https(
                      'api.chess.com',
                      '/pub/player/${username.toLowerCase()}/games/archives',
                    ),
                  ))['archives']
                  as List?) ??
              const [])
          .cast<String>()
          .reversed,
    ];
    while (_pending.length < pageSize && _nextArchive < archives.length) {
      // The index can list a month whose archive is not available yet
      // (seen live: the current month answers 404); treat it as empty.
      final month =
          await _jsonOrNull(
            Uri.parse(archives[_nextArchive++]),
            missingOk: true,
          ) ??
          const <String, dynamic>{};
      _pending.addAll(
        ((month['games'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .where((g) => g['rules'] == 'chess' && g['pgn'] is String)
            .map((g) => g['pgn'] as String)
            .toList()
            .reversed,
      );
    }
    final page = _pending.take(pageSize).toList();
    _pending.removeRange(0, page.length);
    hasMore = _pending.isNotEmpty || _nextArchive < archives.length;
    return page;
  }

  Future<Map<String, dynamic>> _json(Uri uri) async =>
      (await _jsonOrNull(uri))!;

  Future<Map<String, dynamic>?> _jsonOrNull(
    Uri uri, {
    bool missingOk = false,
  }) async {
    final body = await _text(uri, 'application/json', missingOk: missingOk);
    if (body == null) return null;
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } on Object {
      throw const OnlineException('Unexpected response from the server');
    }
  }

  Future<String?> _text(
    Uri uri,
    String accept, {
    bool missingOk = false,
  }) async {
    final HttpReply r;
    try {
      r = await _get(uri, accept);
    } on TimeoutException {
      throw const OnlineException('The server took too long to answer');
    } on SocketException {
      throw const OnlineException('No internet connection');
    } on HandshakeException {
      throw const OnlineException('Secure connection failed');
    } on HttpException {
      throw const OnlineException('The connection was interrupted');
    }
    switch (r.status) {
      case 200:
        return r.body;
      case 404 || 410 when missingOk:
        return null;
      case 404 || 410:
        throw OnlineException('No ${site.label} player named "$username"');
      case 429:
        throw OnlineException(
          '${site.label} is rate-limiting requests; wait a minute and try again',
        );
      case >= 500:
        throw OnlineException('${site.label} is having problems right now');
      default:
        throw OnlineException('${site.label} returned an error (${r.status})');
    }
  }
}

/// Splits a multi-game PGN export at the blank line before each `[Event`.
List<String> splitPgn(String text) => text
    .replaceAll('\r\n', '\n')
    .split(RegExp(r'\n\s*\n(?=\[Event )'))
    .map((g) => g.trim())
    .where((g) => g.isNotEmpty)
    .toList();
