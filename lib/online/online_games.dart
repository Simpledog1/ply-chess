import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Fetches a player's recent public games as PGN text. Optional: the rest of
/// Ply works offline. Uses only the public, no-login APIs.
class OnlineGames {
  OnlineGames({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;
  static const _agent = 'Ply/1.0 (personal chess analysis app)';
  static const _timeout = Duration(seconds: 20);

  static final _validName = RegExp(r'^[A-Za-z0-9_-]{2,30}$');

  /// Recent standard games from Chess.com (newest first), as PGN strings.
  Future<List<String>> chessCom(String username, {int max = 40}) async {
    final user = _check(username).toLowerCase();
    final archives = await _getJson(
      Uri.https('api.chess.com', '/pub/player/$user/games/archives'),
    );
    final months = ((archives['archives'] as List?) ?? const []).cast<String>();
    final out = <String>[];
    for (final url in months.reversed) {
      final month = await _getJson(Uri.parse(url));
      final games = ((month['games'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .where((g) => g['rules'] == 'chess' && g['pgn'] is String)
          .toList()
          .reversed;
      for (final g in games) {
        out.add(g['pgn'] as String);
        if (out.length >= max) return out;
      }
      if (months.length - months.indexOf(url) >= 6) break; // ~6 months back
    }
    return out;
  }

  /// Recent standard games from Lichess (newest first), as PGN strings.
  Future<List<String>> lichess(String username, {int max = 40}) async {
    final user = _check(username);
    final text = await _get(
      Uri.https('lichess.org', '/api/games/user/$user', {
        'max': '$max',
        'perfType': 'ultraBullet,bullet,blitz,rapid,classical,correspondence',
        'opening': 'true',
        'clocks': 'false',
        'evals': 'false',
      }),
      accept: 'application/x-chess-pgn',
    );
    return splitPgn(text);
  }

  /// Splits a multi-game PGN export at the blank line before each `[Event`.
  static List<String> splitPgn(String text) => text
      .replaceAll('\r\n', '\n')
      .split(RegExp(r'\n\s*\n(?=\[Event )'))
      .map((g) => g.trim())
      .where((g) => g.isNotEmpty)
      .toList();

  String _check(String username) {
    final u = username.trim();
    if (!_validName.hasMatch(u)) {
      throw const OnlineException('Enter a valid username');
    }
    return u;
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final body = await _get(uri, accept: 'application/json');
    return jsonDecode(body) as Map<String, dynamic>;
  }

  Future<String> _get(Uri uri, {required String accept}) async {
    try {
      final req = await _client.getUrl(uri).timeout(_timeout);
      req.headers
        ..set(HttpHeaders.userAgentHeader, _agent)
        ..set(HttpHeaders.acceptHeader, accept);
      final res = await req.close().timeout(_timeout);
      final body = await res.transform(utf8.decoder).join().timeout(_timeout);
      if (res.statusCode == 404) throw const OnlineException('User not found');
      if (res.statusCode == 429) {
        throw const OnlineException('Too many requests, try again in a minute');
      }
      if (res.statusCode != 200) {
        throw OnlineException('Server returned ${res.statusCode}');
      }
      return body;
    } on OnlineException {
      rethrow;
    } on TimeoutException {
      throw const OnlineException('The server took too long to answer');
    } on SocketException {
      throw const OnlineException('No internet connection');
    } on HandshakeException {
      throw const OnlineException('Secure connection failed');
    } on FormatException {
      throw const OnlineException('Unexpected response from the server');
    }
  }
}

class OnlineException implements Exception {
  const OnlineException(this.message);
  final String message;
  @override
  String toString() => message;
}
