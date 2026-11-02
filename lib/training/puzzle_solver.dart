import 'package:dartchess/dartchess.dart';

import '../chess/chess_game.dart';
import 'puzzle.dart';

/// What to do after a wrong move.
enum WrongMoveBehavior {
  /// Say it was wrong, take it back, let the player try again.
  retry('Let me try again'),

  /// Show the correct continuation; the puzzle counts as failed.
  reveal('Show the solution');

  const WrongMoveBehavior(this.label);
  final String label;
}

enum MoveVerdict {
  /// Correct, and the opponent's reply is pending ([PuzzleSolver.reply]).
  correct,

  /// Correct, and that was the last move: solved.
  solved,

  /// Wrong; the move was taken back (Retry).
  wrong,

  /// Wrong; the solution is now shown (Reveal). The puzzle is failed.
  revealed,

  /// Not the player's turn, or the puzzle is over.
  ignored,
}

/// A hint, from vague to explicit.
class PuzzleHint {
  const PuzzleHint(this.level, this.text, {this.from, this.move});

  /// 1 = theme, 2 = which piece, 3 = the move.
  final int level;
  final String text;
  final Square? from;
  final String? move;
}

/// Runs one puzzle: shows the position after the opponent's first move,
/// checks each player move against the solution (any checkmate is accepted
/// too, as on Lichess), plays the opponent's replies, and keeps the
/// counts an attempt needs. Moves are compared as normalized UCI, so
/// castling written either way and promotions compare correctly.
class PuzzleSolver {
  PuzzleSolver(this.puzzle, {this.behavior = WrongMoveBehavior.retry}) {
    _restart();
  }

  final Puzzle puzzle;
  final WrongMoveBehavior behavior;

  late Position position;

  /// Index into [Puzzle.moves] of the next move to be played.
  int index = 1;

  /// The last move on the board (UCI), for highlighting.
  String? lastMove;

  /// Moves the player tried that were wrong.
  int wrongMoves = 0;

  /// Highest hint level used (0 = none).
  int hintLevel = 0;

  bool solved = false;
  bool failed = false;

  /// UCI moves the player tried, right or wrong, in order.
  final tried = <String>[];

  bool get finished => solved || failed;

  /// The player solved it with no wrong move and no hint.
  bool get firstTryCorrect => solved && wrongMoves == 0 && hintLevel == 0;

  /// Waiting for the opponent's reply to be played.
  bool get replyPending =>
      !finished && index < puzzle.moves.length && index.isEven;

  Side get solver => puzzle.solver;
  Position get start => _afterSetup;
  late Position _afterSetup;

  void _restart() {
    Position p = Chess.fromSetup(Setup.parseFen(puzzle.fen));
    final first = Move.parse(puzzle.moves.first)!;
    p = p.play(first);
    _afterSetup = p;
    position = p;
    index = 1;
    lastMove = puzzle.moves.first;
  }

  /// Plays the player's [move].
  MoveVerdict play(Move move) {
    if (finished || replyPending || !position.isLegal(move)) {
      return MoveVerdict.ignored;
    }
    final uci = standardUci(position, move);
    tried.add(uci);
    final expected = puzzle.moves[index];
    final after = position.play(move);
    if (uci == expected || after.isCheckmate) {
      position = after;
      lastMove = uci;
      index++;
      if (index >= puzzle.moves.length || after.isCheckmate) {
        solved = true;
        return MoveVerdict.solved;
      }
      return MoveVerdict.correct;
    }
    wrongMoves++;
    if (behavior == WrongMoveBehavior.reveal) {
      showSolution();
      return MoveVerdict.revealed;
    }
    return MoveVerdict.wrong;
  }

  /// Plays the opponent's reply after a correct move.
  void reply() {
    if (!replyPending) return;
    final m = Move.parse(puzzle.moves[index])!;
    lastMove = puzzle.moves[index];
    position = position.play(m);
    index++;
  }

  /// The next hint. Level 3 names the move; asking again reveals it.
  PuzzleHint hint() {
    if (finished || replyPending) {
      return const PuzzleHint(0, '');
    }
    hintLevel = (hintLevel + 1).clamp(1, 3);
    final move = puzzle.moves[index];
    final from = Square.fromName(move.substring(0, 2));
    switch (hintLevel) {
      case 1:
        final motifs = puzzle.motifs;
        return PuzzleHint(
          1,
          motifs.isEmpty
              ? (puzzle.themes.contains('mate')
                    ? 'Look for a checkmate.'
                    : 'Look for the most forcing move: checks, captures, '
                          'threats.')
              : 'Theme: ${motifs.take(2).map(themeName).join(', ')}.',
        );
      case 2:
        final piece = position.board.pieceAt(from)!;
        return PuzzleHint(
          2,
          'Move your ${piece.role.name} on ${from.name}.',
          from: from,
        );
      default:
        final san = position.makeSan(Move.parse(move)!).$2;
        return PuzzleHint(3, 'The move is $san.', from: from, move: move);
    }
  }

  /// Plays out the rest of the solution; the puzzle counts as failed.
  void showSolution() {
    while (index < puzzle.moves.length) {
      final m = Move.parse(puzzle.moves[index])!;
      lastMove = puzzle.moves[index];
      position = position.play(m);
      index++;
    }
    failed = true;
  }

  /// Back to the starting position (counts are kept).
  void reset() {
    if (finished) return;
    _restart();
  }

  /// The full solution in SAN with move numbers, from the shown position.
  String solutionText() => formatSolution(puzzle);
}

/// The solution in SAN with move numbers, e.g. `23. Qxf7+ Kh8 24. Qf8#`.
String formatSolution(Puzzle p) {
  var pos = Chess.fromSetup(Setup.parseFen(p.fen))
      .play(Move.parse(p.moves.first)!);
  final sb = StringBuffer();
  for (var i = 1; i < p.moves.length; i++) {
    final m = Move.parse(p.moves[i])!;
    final white = pos.turn == Side.white;
    if (white) {
      sb.write('${pos.fullmoves}. ');
    } else if (i == 1) {
      sb.write('${pos.fullmoves}… ');
    }
    final (next, san) = pos.makeSan(m);
    sb.write(san);
    if (i < p.moves.length - 1) sb.write(' ');
    pos = next;
  }
  return sb.toString();
}
