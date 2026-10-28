import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../analysis/review.dart';
import '../online/online_games.dart';

enum ArrowMode {
  off('Disabled'),
  best('Best move'),
  all('All lines');

  const ArrowMode(this.label);
  final String label;
}

/// Where the "Load game from" box loads from.
enum LoadSource {
  pgn('PGN'),
  fen('FEN'),
  chessCom('Chess.com'),
  lichess('Lichess');

  const LoadSource(this.label);
  final String label;

  ChessSite? get site => switch (this) {
    LoadSource.chessCom => ChessSite.chessCom,
    LoadSource.lichess => ChessSite.lichess,
    _ => null,
  };
}

/// A remembered site + username. A username only identifies whose public
/// games to load; it does not prove the account belongs to you.
class Profile {
  Profile({required this.site, required this.username, DateTime? lastUsed})
    : lastUsed = lastUsed ?? DateTime.now();

  final ChessSite site;
  final String username;
  final DateTime lastUsed;

  String get key => profileKey(site, username);

  Map<String, dynamic> toJson() => {
    'site': site.name,
    'username': username,
    'lastUsed': lastUsed.toIso8601String(),
  };

  static Profile? fromJson(Map<String, dynamic> j) {
    final site = ChessSite.values.where((s) => s.name == j['site']).firstOrNull;
    final name = j['username'];
    if (site == null || name is! String) return null;
    return Profile(
      site: site,
      username: name,
      lastUsed: DateTime.tryParse(j['lastUsed'] as String? ?? ''),
    );
  }
}

/// Preferences and remembered profiles. Game records live elsewhere
/// (see GameStore), so settings never contain analysis data.
class Settings extends ChangeNotifier {
  Settings(this.dir);

  final Directory dir;

  ThemeMode themeMode = ThemeMode.dark;
  List<String> usernames = [];
  int liveDepth = 22;
  bool timeLimitOn = false;
  int timeLimitSec = 3;
  int reviewDepth = 14;
  int deepReviewDepth = 20;
  int multiPv = 2;
  int threads = max(1, min(4, Platform.numberOfProcessors - 1));
  int hashMb = 64;
  bool showCoordinates = true;
  ArrowMode arrows = ArrowMode.best;
  bool hideClassifications = false;
  ClassOptions classOptions = const ClassOptions();
  bool simpleNotation = false;
  Thresholds thresholds = const Thresholds();
  LoadSource loadSource = LoadSource.chessCom;

  /// Remembered profiles, most recently used first.
  List<Profile> profiles = [];
  String? currentProfile;

  /// Keep reviewed games on this computer. Off by default: games and
  /// analysis then live only in memory until the app closes.
  bool saveHistory = false;

  /// Games fetched per page from Lichess / Chess.com.
  int pageSize = 20;

  Profile? get profile =>
      profiles.where((p) => p.key == currentProfile).firstOrNull;

  /// Usernames that count as "me" when detecting which side was played.
  List<String> get myNames => [
    ...usernames,
    for (final p in profiles) p.username,
  ];

  File get _file => File('${dir.path}/settings.json');

  Future<void> load() async {
    try {
      if (!await _file.exists()) return;
      final j = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      T pick<T>(String k, T fallback) => j[k] is T ? j[k] as T : fallback;
      T byName<T extends Enum>(List<T> values, String k, T fallback) =>
          values.where((v) => v.name == j[k]).firstOrNull ?? fallback;
      themeMode = byName(ThemeMode.values, 'themeMode', themeMode);
      usernames = (j['usernames'] as List?)?.cast<String>() ?? [];
      liveDepth = pick('liveDepth', liveDepth);
      timeLimitOn = pick('timeLimitOn', timeLimitOn);
      timeLimitSec = pick('timeLimitSec', timeLimitSec);
      reviewDepth = pick('reviewDepth', reviewDepth);
      deepReviewDepth = pick('deepReviewDepth', deepReviewDepth);
      multiPv = pick('multiPv', multiPv);
      threads = pick('threads', threads);
      hashMb = pick('hashMb', hashMb);
      showCoordinates = pick('showCoordinates', showCoordinates);
      arrows = byName(ArrowMode.values, 'arrows', arrows);
      hideClassifications = pick('hideClassifications', hideClassifications);
      simpleNotation = pick('simpleNotation', simpleNotation);
      loadSource = byName(LoadSource.values, 'loadSource', loadSource);
      saveHistory = pick('saveHistory', saveHistory);
      pageSize = pick('pageSize', pageSize);
      profiles = [
        for (final p in (j['profiles'] as List?) ?? const [])
          if (p is Map<String, dynamic>) ?Profile.fromJson(p),
      ];
      currentProfile = pick<String?>('currentProfile', null);
      if (j['classOptions'] is Map) {
        classOptions = ClassOptions.fromJson(
          j['classOptions'] as Map<String, dynamic>,
        );
      }
      if (j['thresholds'] is Map) {
        thresholds = Thresholds.fromJson(
          j['thresholds'] as Map<String, dynamic>,
        );
      }
    } catch (_) {
      // Unreadable settings fall back to defaults; nothing of value is lost.
    }
  }

  /// Remembers (or refreshes) a profile and makes it the current one.
  Future<Profile> useProfile(ChessSite site, String username) {
    final p = Profile(site: site, username: username);
    return update((s) {
      s.profiles = [p, ...s.profiles.where((x) => x.key != p.key)];
      s.currentProfile = p.key;
      s.loadSource = site == ChessSite.lichess
          ? LoadSource.lichess
          : LoadSource.chessCom;
    }).then((_) => p);
  }

  Future<void> forgetProfile(String key) => update((s) {
    s.profiles = s.profiles.where((p) => p.key != key).toList();
    if (s.currentProfile == key) s.currentProfile = null;
  });

  Future<void> update(void Function(Settings s) change) async {
    change(this);
    notifyListeners();
    await dir.create(recursive: true);
    await _file.writeAsString(
      jsonEncode({
        'themeMode': themeMode.name,
        'usernames': usernames,
        'liveDepth': liveDepth,
        'timeLimitOn': timeLimitOn,
        'timeLimitSec': timeLimitSec,
        'reviewDepth': reviewDepth,
        'deepReviewDepth': deepReviewDepth,
        'multiPv': multiPv,
        'threads': threads,
        'hashMb': hashMb,
        'showCoordinates': showCoordinates,
        'arrows': arrows.name,
        'hideClassifications': hideClassifications,
        'simpleNotation': simpleNotation,
        'loadSource': loadSource.name,
        'saveHistory': saveHistory,
        'pageSize': pageSize,
        'profiles': [for (final p in profiles) p.toJson()],
        'currentProfile': currentProfile,
        'classOptions': classOptions.toJson(),
        'thresholds': thresholds.toJson(),
      }),
    );
  }
}
