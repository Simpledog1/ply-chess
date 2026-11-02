import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'puzzle.dart';

/// The bundled starter pack (a sample of the CC0 Lichess puzzle database).
const starterPackAsset = 'assets/puzzles/lichess_starter.csv';

/// Result of adding puzzles to the catalogue.
class ImportReport {
  ImportReport({
    required this.added,
    required this.duplicates,
    required this.rejected,
    this.reasons = const {},
  });

  final int added;
  final int duplicates;
  final int rejected;

  /// Rejection reasons with their counts.
  final Map<String, int> reasons;

  String get summary =>
      '$added added, $duplicates already present, $rejected rejected';
}

/// One import, kept in the catalogue's log.
class ImportRecord {
  ImportRecord(
    this.at,
    this.source,
    this.added,
    this.duplicates,
    this.rejected,
  );
  final DateTime at;
  final String source;
  final int added, duplicates, rejected;

  Map<String, dynamic> toJson() => {
    'at': at.toIso8601String(),
    'source': source,
    'added': added,
    'dup': duplicates,
    'rej': rejected,
  };

  factory ImportRecord.fromJson(Map<String, dynamic> j) => ImportRecord(
    DateTime.parse(j['at'] as String),
    j['source'] as String,
    j['added'] as int,
    j['dup'] as int,
    j['rej'] as int,
  );
}

/// Parses and validates a Lichess-format CSV (header optional). Rejected
/// lines are counted, never thrown. Runs in an isolate for large inputs.
({List<Puzzle> puzzles, int rejected}) parsePuzzleCsv(String text) {
  final out = <Puzzle>[];
  var rejected = 0;
  for (final line in const LineSplitter().convert(text)) {
    if (line.isEmpty || line.startsWith('PuzzleId')) continue;
    try {
      final p = Puzzle.fromLichessCsv(line);
      if (validatePuzzle(p) == null) {
        out.add(p);
      } else {
        rejected++;
      }
    } on FormatException {
      rejected++;
    }
  }
  return (puzzles: out, rejected: rejected);
}

/// All puzzles Ply can train with: the bundled starter pack plus puzzles
/// the user downloaded or imported, stored in `puzzles.json` next to the
/// other Ply data. Writes are atomic (temp file, then rename).
class PuzzleCatalogue extends ChangeNotifier {
  PuzzleCatalogue(this.dir);

  static const schemaVersion = 1;

  final Directory dir;
  final _bundled = <String, Puzzle>{};
  final _user = <String, Puzzle>{};
  final imports = <ImportRecord>[];
  bool loaded = false;
  String? loadError;

  File get _file => File('${dir.path}/puzzles.json');

  int get size => _bundled.length + _user.length;
  int get userSize => _user.length;

  Iterable<Puzzle> get all sync* {
    yield* _bundled.values;
    yield* _user.values;
  }

  Puzzle? byId(String id) => _user[id] ?? _bundled[id];
  bool contains(String id) => _bundled.containsKey(id) || _user.containsKey(id);

  /// Loads the starter pack ([starterCsv], read from the asset bundle when
  /// null) and the user's puzzles.
  Future<void> load({String? starterCsv}) async {
    try {
      final text = starterCsv ?? await rootBundle.loadString(starterPackAsset);
      final parsed = await compute(parsePuzzleCsv, text);
      _bundled
        ..clear()
        ..addEntries(parsed.puzzles.map((p) => MapEntry(p.id, p)));
    } catch (e) {
      loadError = 'The built-in puzzles could not be loaded: $e';
    }
    if (await _file.exists()) {
      try {
        final j =
            jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
        _user
          ..clear()
          ..addEntries([
            for (final p in j['puzzles'] as List)
              MapEntry(
                (p as Map<String, dynamic>)['id'] as String,
                Puzzle.fromJson(p),
              ),
          ]);
        imports
          ..clear()
          ..addAll([
            for (final r in j['imports'] as List? ?? const [])
              ImportRecord.fromJson(r as Map<String, dynamic>),
          ]);
      } catch (e) {
        final backup =
            '${_file.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}';
        await _file.rename(backup);
        loadError = 'Downloaded puzzles could not be read; moved to $backup';
      }
    }
    loaded = true;
    notifyListeners();
  }

  /// Validates [candidates], skips ones already present, and saves the new
  /// ones in a single write. Nothing is saved if the write fails, and the
  /// existing catalogue stays as it was.
  Future<ImportReport> addAll(
    Iterable<Puzzle> candidates, {
    required String source,
  }) async {
    final fresh = <String, Puzzle>{};
    var dup = 0, rej = 0;
    final reasons = <String, int>{};
    for (final p in candidates) {
      if (contains(p.id) || fresh.containsKey(p.id)) {
        dup++;
        continue;
      }
      final why = validatePuzzle(p);
      if (why != null) {
        rej++;
        final key = why.startsWith('Illegal move') ? 'Illegal solution' : why;
        reasons[key] = (reasons[key] ?? 0) + 1;
        continue;
      }
      fresh[p.id] = p;
    }
    final report = ImportReport(
      added: fresh.length,
      duplicates: dup,
      rejected: rej,
      reasons: reasons,
    );
    if (fresh.isEmpty && rej == 0) return report;
    final record = ImportRecord(DateTime.now(), source, fresh.length, dup, rej);
    await _save({..._user, ...fresh}, [...imports, record]);
    _user.addAll(fresh);
    imports.add(record);
    notifyListeners();
    return report;
  }

  /// Removes every downloaded or imported puzzle (the starter pack stays).
  Future<void> clearUser() async {
    await _save({}, []);
    _user.clear();
    imports.clear();
    notifyListeners();
  }

  Future<void> _queue = Future.value();

  /// Saves run one at a time (overlapping writes would race on the temp
  /// file).
  Future<void> _save(Map<String, Puzzle> user, List<ImportRecord> log) {
    final next = _queue.then((_) => _write(user, log));
    _queue = next.catchError((Object _) {});
    return next;
  }

  Future<void> _write(Map<String, Puzzle> user, List<ImportRecord> log) async {
    await dir.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({
        'version': schemaVersion,
        'imports': [for (final r in log) r.toJson()],
        'puzzles': [for (final p in user.values) p.toJson()],
      }),
      flush: true,
    );
    await tmp.rename(_file.path);
  }
}
