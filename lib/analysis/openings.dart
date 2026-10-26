import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../chess/chess_game.dart';
import 'review.dart';

/// Named openings from the Lichess chess-openings list (CC0).
class OpeningBook implements OpeningLookup {
  OpeningBook._(this._positions, this._names);

  /// Every position reached along any listed line.
  final Set<String> _positions;

  /// Positions at the end of a listed line, with ECO code and name.
  final Map<String, (String, String)> _names;

  int get size => _names.length;

  @override
  bool contains(Position pos) => _positions.contains(bookKey(pos));

  (String eco, String name)? nameOf(Position pos) => _names[bookKey(pos)];

  /// The deepest named opening reached in [game]'s mainline.
  (String eco, String name)? openingOf(ChessGame game) {
    if (!game.startsFromStandard) return null;
    (String, String)? found;
    for (final p in game.plies) {
      if (!contains(p.after)) break;
      found = nameOf(p.after) ?? found;
    }
    return found;
  }

  /// Builds the book from TSV files with `eco<TAB>name<TAB>pgn` rows.
  static OpeningBook parse(List<String> tsvs) {
    final positions = <String>{};
    final names = <String, (String, String)>{};
    for (final tsv in tsvs) {
      for (final line in tsv.split('\n').skip(1)) {
        final cols = line.split('\t');
        if (cols.length < 3) continue;
        Position pos = Chess.initial;
        var ok = true;
        for (final tok in cols[2].trim().split(' ')) {
          if (tok.isEmpty || tok.endsWith('.')) continue;
          final m = pos.parseSan(tok);
          if (m == null) {
            ok = false;
            break;
          }
          pos = pos.play(m);
          positions.add(bookKey(pos));
        }
        if (ok) names.putIfAbsent(bookKey(pos), () => (cols[0], cols[1]));
      }
    }
    return OpeningBook._(positions, names);
  }

  static Future<OpeningBook> load() async {
    final texts = [
      for (final f in 'abcde'.split(''))
        await rootBundle.loadString('assets/openings/$f.tsv'),
    ];
    return compute(parse, texts);
  }
}
