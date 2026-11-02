import 'package:dartchess/dartchess.dart';

import '../chess/chess_game.dart';

/// A tactics puzzle in the Lichess puzzle-database convention:
/// [fen] is the position *before* the opponent's move, [moves] are UCI
/// moves starting with that opponent move, then alternating player /
/// opponent. The player's moves are at odd indices.
class Puzzle {
  const Puzzle({
    required this.id,
    required this.source,
    required this.fen,
    required this.moves,
    required this.rating,
    this.ratingDeviation,
    this.popularity,
    this.plays,
    this.themes = const [],
    this.gameUrl,
    this.importedAt,
  });

  /// Ply's id: `source:sourceId`, e.g. `lichess:00sHx`.
  final String id;
  final String source;
  final String fen;
  final List<String> moves;
  final int rating;
  final int? ratingDeviation;
  final int? popularity;
  final int? plays;
  final List<String> themes;
  final String? gameUrl;
  final DateTime? importedAt;

  String get sourceId => id.substring(id.indexOf(':') + 1);

  /// Number of moves the player has to find.
  int get playerMoves => moves.length ~/ 2;

  /// The side solving the puzzle (the side to move after the first move).
  Side get solver => Setup.parseFen(fen).turn.opposite;

  /// Tactical motif themes (no phase, length or evaluation tags).
  List<String> get motifs => [
    for (final t in themes)
      if (!nonMotifThemes.contains(t)) t,
  ];

  /// The theme used to spread puzzles out when ordering a collection.
  String get primaryTheme => primaryThemeOf(themes);

  Map<String, dynamic> toJson() => {
    'id': id,
    'src': source,
    'fen': fen,
    'moves': moves.join(' '),
    'r': rating,
    if (ratingDeviation != null) 'rd': ratingDeviation,
    if (popularity != null) 'pop': popularity,
    if (plays != null) 'n': plays,
    'th': themes.join(' '),
    if (gameUrl != null) 'url': gameUrl,
    if (importedAt != null) 'at': importedAt!.toIso8601String(),
  };

  factory Puzzle.fromJson(Map<String, dynamic> j) => Puzzle(
    id: j['id'] as String,
    source: j['src'] as String? ?? 'lichess',
    fen: j['fen'] as String,
    moves: (j['moves'] as String).split(' '),
    rating: j['r'] as int,
    ratingDeviation: j['rd'] as int?,
    popularity: j['pop'] as int?,
    plays: j['n'] as int?,
    themes: _split(j['th'] as String? ?? ''),
    gameUrl: j['url'] as String?,
    importedAt: j['at'] == null ? null : DateTime.parse(j['at'] as String),
  );

  /// Parses one line of the Lichess puzzle CSV
  /// (`PuzzleId,FEN,Moves,Rating,RatingDeviation,Popularity,NbPlays,Themes,
  /// GameUrl,OpeningTags[,DailyDate]`). Throws [FormatException]; the
  /// result still needs [validatePuzzle].
  factory Puzzle.fromLichessCsv(String line, {DateTime? importedAt}) {
    final f = line.trim().split(',');
    if (f.length < 9) throw const FormatException('Too few columns');
    int? n(String s) => s.isEmpty ? null : int.tryParse(s);
    final rating = n(f[3]);
    if (f[0].isEmpty || rating == null) {
      throw const FormatException('Missing id or rating');
    }
    return Puzzle(
      id: 'lichess:${f[0]}',
      source: 'lichess',
      fen: f[1],
      moves: _split(f[2]),
      rating: rating,
      ratingDeviation: n(f[4]),
      popularity: n(f[5]),
      plays: n(f[6]),
      themes: _split(f[7]),
      gameUrl: f[8].isEmpty ? null : f[8],
      importedAt: importedAt,
    );
  }

  /// Converts a puzzle from the Lichess API (`/api/puzzle/batch`), which
  /// gives the game's SAN moves up to the puzzle and the player's solution,
  /// into the database convention (FEN before the opponent's last move).
  factory Puzzle.fromLichessApi(
    Map<String, dynamic> j, {
    DateTime? importedAt,
  }) {
    final game = j['game'] as Map<String, dynamic>;
    final p = j['puzzle'] as Map<String, dynamic>;
    final sans = _split(game['pgn'] as String? ?? '');
    if (sans.isEmpty) throw const FormatException('Game has no moves');
    Position pos = Chess.initial;
    Position? before;
    String? last;
    for (final san in sans) {
      final m = pos.parseSan(san);
      if (m == null) throw FormatException('Illegal game move $san');
      before = pos;
      last = standardUci(pos, m);
      pos = pos.play(m);
    }
    final id = p['id'] as String;
    return Puzzle(
      id: 'lichess:$id',
      source: 'lichess',
      fen: before!.fen,
      moves: [last!, ...(p['solution'] as List).cast<String>()],
      rating: p['rating'] as int,
      plays: p['plays'] as int?,
      themes: (p['themes'] as List? ?? const []).cast<String>(),
      gameUrl: game['id'] == null ? null : 'https://lichess.org/${game['id']}',
      importedAt: importedAt,
    );
  }

  static List<String> _split(String s) =>
      s.trim().isEmpty ? const [] : s.trim().split(RegExp(r'\s+'));
}

/// The theme used to spread puzzles out: the first tactical motif, else
/// 'mate' for mating puzzles, else 'other'.
String primaryThemeOf(List<String> themes) {
  for (final t in themes) {
    if (!nonMotifThemes.contains(t)) return t;
  }
  return themes.contains('mate') ? 'mate' : 'other';
}

/// Lichess theme tags that describe the game phase, the length or the
/// evaluation rather than a tactical motif.
const nonMotifThemes = {
  'opening',
  'middlegame',
  'endgame',
  'short',
  'long',
  'veryLong',
  'oneMove',
  'advantage',
  'crushing',
  'equality',
  'mate',
  'master',
  'masterVsMaster',
  'superGM',
  'mateIn1',
  'mateIn2',
  'mateIn3',
  'mateIn4',
  'mateIn5',
};

/// Readable names for common Lichess theme tags.
const _themeNames = {
  'fork': 'Fork',
  'pin': 'Pin',
  'skewer': 'Skewer',
  'discoveredAttack': 'Discovered attack',
  'doubleCheck': 'Double check',
  'defensiveMove': 'Defensive move',
  'quietMove': 'Quiet move',
  'backRankMate': 'Back-rank mate',
  'sacrifice': 'Sacrifice',
  'mate': 'Checkmate',
  'mateIn1': 'Mate in 1',
  'mateIn2': 'Mate in 2',
  'mateIn3': 'Mate in 3',
  'mateIn4': 'Mate in 4',
  'mateIn5': 'Mate in 5 or more',
  'hangingPiece': 'Hanging piece',
  'trappedPiece': 'Trapped piece',
  'deflection': 'Deflection',
  'attraction': 'Attraction',
  'clearance': 'Clearance',
  'interference': 'Interference',
  'intermezzo': 'Intermezzo',
  'xRayAttack': 'X-ray attack',
  'zugzwang': 'Zugzwang',
  'capturingDefender': 'Capturing the defender',
  'exposedKing': 'Exposed king',
  'kingsideAttack': 'Kingside attack',
  'queensideAttack': 'Queenside attack',
  'advancedPawn': 'Advanced pawn',
  'promotion': 'Promotion',
  'underPromotion': 'Underpromotion',
  'enPassant': 'En passant',
  'castling': 'Castling',
  'smotheredMate': 'Smothered mate',
  'anastasiaMate': 'Anastasia\'s mate',
  'arabianMate': 'Arabian mate',
  'bodenMate': 'Boden\'s mate',
  'doubleBishopMate': 'Double-bishop mate',
  'dovetailMate': 'Dovetail mate',
  'hookMate': 'Hook mate',
  'attackingF2F7': 'Attacking f2/f7',
  'rookEndgame': 'Rook endgame',
  'pawnEndgame': 'Pawn endgame',
  'queenEndgame': 'Queen endgame',
  'bishopEndgame': 'Bishop endgame',
  'knightEndgame': 'Knight endgame',
  'queenRookEndgame': 'Queen and rook endgame',
  'oneMove': 'One move',
  'short': 'Short',
  'long': 'Long',
  'veryLong': 'Very long',
  'opening': 'Opening',
  'middlegame': 'Middlegame',
  'endgame': 'Endgame',
  'advantage': 'Advantage',
  'crushing': 'Crushing',
  'equality': 'Equality',
  'other': 'Other',
};

/// A readable theme name: known names, else the tag split at capitals.
String themeName(String tag) =>
    _themeNames[tag] ??
    tag
        .replaceAllMapped(
          RegExp(r'([a-z])([A-Z0-9])'),
          (m) => '${m[1]} ${m[2]}',
        )
        .replaceFirstMapped(RegExp(r'^.'), (m) => m[0]!.toUpperCase());

/// Checks that [p] is usable: the FEN is a legal standard position, the
/// opponent's first move and every solution move are legal in turn, and
/// the player has at least one move to find. Returns a reason, or null.
String? validatePuzzle(Puzzle p) {
  if (p.id.isEmpty) return 'No id';
  if (p.rating < 100 || p.rating > 4000) return 'Implausible rating';
  if (p.moves.length < 2) return 'No solution';
  if (p.moves.length.isOdd) return 'Solution must end with the player\'s move';
  Position pos;
  try {
    pos = Chess.fromSetup(Setup.parseFen(p.fen));
  } on FenException {
    return 'Invalid FEN';
  } on PositionSetupException {
    return 'Illegal position';
  }
  for (var i = 0; i < p.moves.length; i++) {
    final m = Move.parse(p.moves[i]);
    if (m == null || !pos.isLegal(m)) {
      return 'Illegal move ${i + 1}: ${p.moves[i]}';
    }
    pos = pos.play(m);
  }
  return null;
}
