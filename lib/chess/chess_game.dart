import 'package:dartchess/dartchess.dart';

/// One half-move of a game.
class GamePly {
  const GamePly({required this.san, required this.uci, required this.after});

  final String san;

  /// Standard UCI notation (castling as king two squares, e.g. `e1g1`).
  final String uci;

  /// The position after this move.
  final Position after;
}

/// A game as a start position plus a mainline of moves.
///
/// Immutable: editing operations return a new [ChessGame]. PGN side lines are
/// not kept; Ply works on the mainline.
class ChessGame {
  ChessGame({
    required this.initial,
    required List<GamePly> plies,
    Map<String, String>? headers,
  }) : plies = List.unmodifiable(plies),
       headers = Map.unmodifiable(headers ?? _defaultHeaders());

  factory ChessGame.standard() => ChessGame(initial: Chess.initial, plies: []);

  final Position initial;
  final List<GamePly> plies;
  final Map<String, String> headers;

  static Map<String, String> _defaultHeaders() => {
    'Event': '?',
    'Site': '?',
    'Date': '????.??.??',
    'Round': '?',
    'White': '?',
    'Black': '?',
    'Result': '*',
  };

  int get length => plies.length;
  String get initialFen => initial.fen;
  bool get startsFromStandard => initial.fen == Chess.initial.fen;

  Position positionAt(int ply) => ply == 0 ? initial : plies[ply - 1].after;
  Position get last => positionAt(length);

  /// UCI moves from the start position up to (not including) [ply].
  List<String> ucisBefore(int ply) => [for (final p in plies.take(ply)) p.uci];

  /// Plays [move] after [ply] moves. Moves after [ply] are discarded unless
  /// [move] equals the existing next move. Returns null if illegal.
  ChessGame? play(int ply, Move move) {
    final pos = positionAt(ply);
    if (!pos.isLegal(move)) return null;
    final uci = standardUci(pos, move);
    if (ply < length && plies[ply].uci == uci) return this;
    final (after, san) = pos.makeSan(move);
    return ChessGame(
      initial: initial,
      plies: [
        ...plies.take(ply),
        GamePly(san: san, uci: uci, after: after),
      ],
      headers: headers,
    );
  }

  /// Plays a UCI move string; null if it is not legal.
  ChessGame? playUci(int ply, String uci) {
    final m = Move.parse(uci);
    return m == null ? null : play(ply, m);
  }

  ChessGame withHeaders(Map<String, String> h) =>
      ChessGame(initial: initial, plies: plies, headers: h);

  /// Result as stored in the headers, or derived from a finished final position.
  String get result {
    final r = headers['Result'];
    if (r != null && r != '*') return r;
    return Outcome.toPgnString(last.outcome);
  }

  // --- FEN -----------------------------------------------------------------

  /// Throws [FormatException] with a readable message for invalid FEN.
  factory ChessGame.fromFen(String fen) {
    final Position pos;
    try {
      pos = Chess.fromSetup(Setup.parseFen(fen.trim()));
    } on FenException catch (e) {
      throw FormatException('Invalid FEN: ${e.cause.name}');
    } on PositionSetupException catch (e) {
      throw FormatException('Illegal position: ${e.cause.name}');
    }
    return ChessGame(
      initial: pos,
      plies: [],
      headers: {..._defaultHeaders(), 'SetUp': '1', 'FEN': pos.fen},
    );
  }

  // --- PGN -----------------------------------------------------------------

  /// Parses a single PGN game. Throws [FormatException] on errors.
  factory ChessGame.fromPgn(String pgn) {
    final games = PgnGame.parseMultiGamePgn(pgn);
    if (games.isEmpty) throw const FormatException('No game found');
    return _fromPgnGame(games.first);
  }

  /// Parses every game in [text]. Games that fail to load are reported in
  /// `errors` instead of aborting the whole import.
  static ({List<ChessGame> games, List<String> errors}) parseMany(String text) {
    final games = <ChessGame>[];
    final errors = <String>[];
    final parsed = PgnGame.parseMultiGamePgn(text);
    for (var i = 0; i < parsed.length; i++) {
      try {
        final g = _fromPgnGame(parsed[i]);
        if (g.length == 0 && !g.headers.containsKey('FEN')) {
          throw const FormatException('no moves');
        }
        games.add(g);
      } on FormatException catch (e) {
        errors.add('Game ${i + 1}: ${e.message}');
      }
    }
    if (parsed.isEmpty) errors.add('No PGN games found');
    return (games: games, errors: errors);
  }

  static ChessGame _fromPgnGame(PgnGame<PgnNodeData> g) {
    final variant = g.headers['Variant'];
    if (variant != null &&
        !const [
          'standard',
          'chess',
          'from position',
        ].contains(variant.toLowerCase())) {
      throw FormatException('Unsupported variant "$variant"');
    }
    Position pos;
    try {
      final fen = g.headers['FEN'];
      pos = fen == null ? Chess.initial : Chess.fromSetup(Setup.parseFen(fen));
    } catch (_) {
      throw const FormatException('Invalid FEN header');
    }
    final initial = pos;
    final plies = <GamePly>[];
    for (final node in g.moves.mainline()) {
      final move = pos.parseSan(node.san);
      if (move == null) {
        final n = pos.fullmoves;
        final dots = pos.turn == Side.white ? '.' : '...';
        throw FormatException('Illegal move $n$dots ${node.san}');
      }
      final (after, san) = pos.makeSan(move);
      plies.add(GamePly(san: san, uci: standardUci(pos, move), after: after));
      pos = after;
    }
    return ChessGame(initial: initial, plies: plies, headers: g.headers);
  }

  /// Exports PGN. Optional [comments] and [nags] are keyed by ply index
  /// (0 = first move).
  String toPgn({Map<int, String>? comments, Map<int, int>? nags}) {
    final h = {...headers};
    h['Result'] = result;
    if (!startsFromStandard) {
      h['SetUp'] = '1';
      h['FEN'] = initialFen;
    }
    final root = PgnNode<PgnNodeData>();
    PgnNode<PgnNodeData> node = root;
    for (var i = 0; i < plies.length; i++) {
      final c = comments?[i];
      final n = nags?[i];
      final child = PgnChildNode(
        PgnNodeData(
          san: plies[i].san,
          comments: c == null ? null : [c],
          nags: n == null ? null : [n],
        ),
      );
      node.children.add(child);
      node = child;
    }
    return PgnGame(headers: h, moves: root, comments: const []).makePgn();
  }
}

/// UCI string for [move] in [pos], writing castling the standard way
/// (`e1g1`) rather than dartchess's internal king-takes-rook form (`e1h1`).
String standardUci(Position pos, Move move) {
  if (move is NormalMove) {
    final piece = pos.board.pieceAt(move.from);
    final target = pos.board.pieceAt(move.to);
    if (piece?.role == Role.king &&
        target?.role == Role.rook &&
        target?.color == piece?.color) {
      final kingSide = move.to.file > move.from.file;
      final to = Square.fromCoords(kingSide ? File.g : File.c, move.from.rank);
      return move.from.name + to.name;
    }
  }
  return move.uci;
}

/// Material difference: for each role, how many more pieces [side] has than
/// the opponent (only positive entries), plus the point balance.
({Map<Role, int> extra, int points}) materialEdge(Board board, Side side) {
  const values = {
    Role.pawn: 1,
    Role.knight: 3,
    Role.bishop: 3,
    Role.rook: 5,
    Role.queen: 9,
  };
  final extra = <Role, int>{};
  var points = 0;
  for (final r in values.keys) {
    final mine = board.piecesOf(side, r).size;
    final theirs = board.piecesOf(side.opposite, r).size;
    if (mine > theirs) extra[r] = mine - theirs;
    points += (mine - theirs) * values[r]!;
  }
  return (extra: extra, points: points);
}
