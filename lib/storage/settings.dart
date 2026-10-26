import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../analysis/review.dart';

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
}

class Settings extends ChangeNotifier {
  Settings(this.dir);

  final Directory dir;

  ThemeMode themeMode = ThemeMode.dark;
  List<String> usernames = [];
  int liveDepth = 22;
  bool timeLimitOn = false;
  int timeLimitSec = 3;
  int reviewDepth = 14;
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
  String onlineUsername = '';

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
      multiPv = pick('multiPv', multiPv);
      threads = pick('threads', threads);
      hashMb = pick('hashMb', hashMb);
      showCoordinates = pick('showCoordinates', showCoordinates);
      arrows = byName(ArrowMode.values, 'arrows', arrows);
      hideClassifications = pick('hideClassifications', hideClassifications);
      simpleNotation = pick('simpleNotation', simpleNotation);
      loadSource = byName(LoadSource.values, 'loadSource', loadSource);
      onlineUsername = pick('onlineUsername', onlineUsername);
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
        'multiPv': multiPv,
        'threads': threads,
        'hashMb': hashMb,
        'showCoordinates': showCoordinates,
        'arrows': arrows.name,
        'hideClassifications': hideClassifications,
        'simpleNotation': simpleNotation,
        'loadSource': loadSource.name,
        'onlineUsername': onlineUsername,
        'classOptions': classOptions.toJson(),
        'thresholds': thresholds.toJson(),
      }),
    );
  }
}
