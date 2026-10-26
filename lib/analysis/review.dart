import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';

import '../chess/chess_game.dart';
import 'eval.dart';

enum MoveClass {
  brilliant('Brilliant'),
  critical('Critical'),
  best('Best'),
  excellent('Excellent'),
  good('Good'),
  theory('Theory'),
  inaccuracy('Inaccuracy'),
  mistake('Mistake'),
  blunder('Blunder'),
  forced('Forced');

  const MoveClass(this.label);
  final String label;

  bool get isError => this == inaccuracy || this == mistake || this == blunder;
  bool get isSerious => this == mistake || this == blunder;

  /// Moves that were not a real decision (book or only legal move).
  bool get isRoutine => this == theory || this == forced;
}

/// Which of the optional classifications are shown. Hidden ones fall back
/// to the class the move would otherwise get (e.g. Brilliant -> Best).
class ClassOptions {
  const ClassOptions({
    this.brilliant = true,
    this.critical = true,
    this.theory = true,
  });

  final bool brilliant;
  final bool critical;
  final bool theory;

  /// Win% gap between Stockfish's best and second-best move needed for a
  /// best move to count as Critical (the only move that holds).
  static const criticalGap = 10.0;

  Map<String, dynamic> toJson() => {
    'brilliant': brilliant,
    'critical': critical,
    'theory': theory,
  };

  factory ClassOptions.fromJson(Map<String, dynamic> j) => ClassOptions(
    brilliant: j['brilliant'] as bool? ?? true,
    critical: j['critical'] as bool? ?? true,
    theory: j['theory'] as bool? ?? true,
  );
}

/// Positions known to opening theory.
abstract interface class OpeningLookup {
  bool contains(Position pos);
}

/// Position identity for book lookups: FEN without the move counters.
String bookKey(Position pos) => pos.fen.split(' ').take(4).join(' ');

enum MoveTag {
  missedMate('Missed forced mate'),
  allowedMate('Allowed forced mate'),
  missedWin('Missed a winning position'),
  tacticalMiss('Missed tactic');

  const MoveTag(this.label);
  final String label;
}

enum Phase { opening, middlegame, endgame }

/// Win-percentage loss thresholds (0–100 scale, mover's perspective).
/// Defaults match Lichess: inaccuracy 5, mistake 10, blunder 15
/// (Lichess states these as 0.1 / 0.2 / 0.3 on its −1..1 winning-chances scale).
class Thresholds {
  const Thresholds({
    this.excellent = 2,
    this.inaccuracy = 5,
    this.mistake = 10,
    this.blunder = 15,
  });

  final double excellent;
  final double inaccuracy;
  final double mistake;
  final double blunder;

  Map<String, dynamic> toJson() => {
    'excellent': excellent,
    'inaccuracy': inaccuracy,
    'mistake': mistake,
    'blunder': blunder,
  };

  factory Thresholds.fromJson(Map<String, dynamic> j) => Thresholds(
    excellent: (j['excellent'] as num?)?.toDouble() ?? 2,
    inaccuracy: (j['inaccuracy'] as num?)?.toDouble() ?? 5,
    mistake: (j['mistake'] as num?)?.toDouble() ?? 10,
    blunder: (j['blunder'] as num?)?.toDouble() ?? 15,
  );

  MoveClass classify(double loss) {
    if (loss >= blunder) return MoveClass.blunder;
    if (loss >= mistake) return MoveClass.mistake;
    if (loss >= inaccuracy) return MoveClass.inaccuracy;
    if (loss >= excellent) return MoveClass.good;
    return MoveClass.excellent;
  }
}

/// Engine result for one position of a game.
class PositionAnalysis {
  const PositionAnalysis({
    required this.eval,
    required this.depth,
    this.bestMove,
    this.pv = const [],
    this.second,
  });

  final Eval eval;
  final int depth;
  final String? bestMove;
  final List<String> pv;

  /// Evaluation of Stockfish's second-best move (MultiPV 2), if any.
  final Eval? second;

  Map<String, dynamic> toJson() => {
    'e': eval.toJson(),
    'd': depth,
    if (bestMove != null) 'b': bestMove,
    if (pv.isNotEmpty) 'pv': pv,
    if (second != null) 'e2': second!.toJson(),
  };

  factory PositionAnalysis.fromJson(Map<String, dynamic> j) => PositionAnalysis(
    eval: Eval.fromJson(j['e'] as Map<String, dynamic>),
    depth: j['d'] as int,
    bestMove: j['b'] as String?,
    pv: (j['pv'] as List?)?.cast<String>() ?? const [],
    second: j['e2'] == null
        ? null
        : Eval.fromJson(j['e2'] as Map<String, dynamic>),
  );
}

/// Stored engine data for a whole game. `positions[i]` is the position after
/// `i` plies; null entries were not analysed (e.g. the review was stopped).
class GameReview {
  GameReview({
    required this.depth,
    required this.engine,
    required this.moves,
    required this.positions,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final int depth;
  final String engine;
  final List<String> moves;
  final List<PositionAnalysis?> positions;
  final DateTime createdAt;

  bool get complete => positions.every((p) => p != null);
  int get analysedCount => positions.where((p) => p != null).length;

  /// The review belongs to [game] only if the move sequence is identical.
  bool matches(ChessGame game) =>
      moves.length == game.length &&
      positions.length == game.length + 1 &&
      List.generate(
        moves.length,
        (i) => moves[i] == game.plies[i].uci,
      ).every((x) => x);

  Map<String, dynamic> toJson() => {
    'depth': depth,
    'engine': engine,
    'moves': moves,
    'createdAt': createdAt.toIso8601String(),
    'positions': [for (final p in positions) p?.toJson()],
  };

  factory GameReview.fromJson(Map<String, dynamic> j) => GameReview(
    depth: j['depth'] as int,
    engine: j['engine'] as String,
    moves: (j['moves'] as List).cast<String>(),
    createdAt: DateTime.parse(j['createdAt'] as String),
    positions: [
      for (final p in j['positions'] as List)
        p == null ? null : PositionAnalysis.fromJson(p as Map<String, dynamic>),
    ],
  );
}

/// The evaluation of a finished position, decided by the rules, not the engine.
Eval? terminalEval(Position pos) {
  if (pos.isCheckmate) {
    return Eval.mate(0, whiteMates: pos.turn == Side.black);
  }
  if (pos.isStalemate || pos.isInsufficientMaterial) return const Eval.cp(0);
  return null;
}

/// Lichess's per-move accuracy formula from the mover's win% before/after.
double moveAccuracy(double winBefore, double winAfter) {
  if (winAfter >= winBefore) return 100;
  final raw =
      103.1668100711649 *
          math.exp(-0.04354415386753951 * (winBefore - winAfter)) -
      3.166924740191411;
  return (raw + 1).clamp(0, 100).toDouble();
}

/// Rough game phase: endgame when at most 6 non-pawn, non-king pieces remain;
/// opening for the first 10 full moves; otherwise middlegame.
Phase phaseOf(Position pos) {
  final b = pos.board;
  final pieces = (b.knights | b.bishops | b.rooks | b.queens).size;
  if (pieces <= 6) return Phase.endgame;
  if (pos.fullmoves <= 10) return Phase.opening;
  return Phase.middlegame;
}

/// Converts UCI moves to SAN starting from [pos], stopping at the first
/// illegal move.
List<String> uciLineToSan(Position pos, List<String> ucis, {int max = 8}) {
  final out = <String>[];
  var p = pos;
  for (final u in ucis.take(max)) {
    final m = Move.parse(u);
    if (m == null || !p.isLegal(m)) break;
    final (next, san) = p.makeSan(m);
    out.add(san);
    p = next;
  }
  return out;
}

/// Formats a SAN line with move numbers, e.g. `12. Nf3 Nc6 13. Bb5`.
String formatLine(Position start, List<String> sans) {
  final sb = StringBuffer();
  var n = start.fullmoves;
  var white = start.turn == Side.white;
  for (var i = 0; i < sans.length; i++) {
    if (white) {
      sb.write('$n. ');
    } else if (i == 0) {
      sb.write('$n… ');
    }
    sb.write(sans[i]);
    if (i < sans.length - 1) sb.write(' ');
    if (!white) n++;
    white = !white;
  }
  return sb.toString();
}

class MoveReview {
  MoveReview({
    required this.ply,
    required this.mover,
    required this.san,
    required this.cls,
    required this.loss,
    required this.accuracy,
    required this.before,
    required this.after,
    required this.winBefore,
    required this.winAfter,
    required this.phase,
    required this.tags,
    required this.bestSan,
    required this.bestLine,
    required this.replyLine,
    required this.depth,
    required this.bestIsForcing,
    this.secondWin,
  });

  /// Index of the move in the game (0 = first move).
  final int ply;
  final Side mover;
  final String san;
  final MoveClass cls;

  /// Drop in the mover's win percentage (0–100), never negative.
  final double loss;
  final double accuracy;
  final Eval before;
  final Eval after;
  final double winBefore;
  final double winAfter;
  final Phase phase;
  final Set<MoveTag> tags;
  final String? bestSan;

  /// Engine's preferred continuation from the position before the move.
  final String bestLine;

  /// Engine's continuation after the move actually played.
  final String replyLine;
  final int depth;

  /// The engine's preferred move was a capture, check or promotion.
  final bool bestIsForcing;

  /// Mover's win% after Stockfish's second-best move, when known.
  final double? secondWin;

  /// A factual summary built only from engine output.
  String get explanation {
    final parts = <String>[];
    if (cls == MoveClass.forced) return 'Only legal move.';
    if (cls == MoveClass.theory) {
      return 'Known opening theory: the position after it is in the opening book.';
    }
    if (cls == MoveClass.brilliant) {
      parts.add(
        'Stockfish\'s top choice at depth $depth, and it gives up material: '
        'the piece can be taken for less than it is worth.',
      );
    } else if (cls == MoveClass.critical) {
      final gap = (winBefore - (secondWin ?? winBefore)).round();
      parts.add(
        'Stockfish\'s top choice at depth $depth and the only move that holds: '
        'its second choice was $gap percentage points worse.',
      );
    } else if (cls == MoveClass.best) {
      parts.add('Stockfish\'s top choice at depth $depth.');
    } else if (bestSan != null) {
      parts.add('Stockfish preferred $bestSan (${before.label}).');
      if (replyLine.isNotEmpty) {
        parts.add('After $san its line is $replyLine (${after.label}).');
      }
    }
    if (tags.contains(MoveTag.allowedMate)) {
      parts.add('This allows a forced mate in ${after.mateIn}.');
    }
    if (tags.contains(MoveTag.missedMate)) {
      parts.add('There was a forced mate in ${before.mateIn}.');
    }
    if (loss >= 1) {
      final who = mover == Side.white ? 'White' : 'Black';
      parts.add(
        '$who\'s winning chances: '
        '${winBefore.round()}% to ${winAfter.round()}%.',
      );
    }
    return parts.join(' ');
  }
}

/// Computes per-move reviews. Entries are null where either surrounding
/// position has not been analysed.
List<MoveReview?> reviewMoves(
  ChessGame game,
  GameReview data,
  Thresholds t, {
  ClassOptions options = const ClassOptions(),
  OpeningLookup? book,
}) {
  final out = <MoveReview?>[];
  // A move is theory only while every position since the start is in the book.
  var inBook = book != null && options.theory && game.startsFromStandard;
  for (var i = 0; i < game.length; i++) {
    inBook = inBook && book!.contains(game.plies[i].after);
    final a = data.positions[i];
    final b = data.positions[i + 1];
    if (a == null || b == null) {
      out.add(null);
      continue;
    }
    final pos = game.positionAt(i);
    final mover = pos.turn;
    final ply = game.plies[i];
    final wb = a.eval.winPercentFor(mover);
    final wa = b.eval.winPercentFor(mover);
    final forced = pos.legalMoves.values.fold(0, (n, s) => n + s.size) == 1;
    final isBest = a.bestMove != null && a.bestMove == ply.uci;
    final theory = inBook && !forced;
    final loss = (forced || isBest || theory) ? 0.0 : math.max(0.0, wb - wa);
    final secondWin = a.second?.winPercentFor(mover);
    final critical =
        isBest &&
        options.critical &&
        secondWin != null &&
        wb - secondWin >= ClassOptions.criticalGap;
    final brilliant =
        isBest &&
        options.brilliant &&
        wa >= 45 &&
        wb <= 95 &&
        isSacrifice(pos, ply.uci);
    final cls = forced
        ? MoveClass.forced
        : theory
        ? MoveClass.theory
        : brilliant
        ? MoveClass.brilliant
        : critical
        ? MoveClass.critical
        : isBest
        ? MoveClass.best
        : t.classify(loss);

    final forcing = a.bestMove != null && _isForcing(pos, a.bestMove!);
    final tags = <MoveTag>{};
    final moverMatesBefore =
        a.eval.isMate && a.eval.whiteMates == (mover == Side.white);
    final moverMatesAfter =
        b.eval.isMate && b.eval.whiteMates == (mover == Side.white);
    final matedBefore = a.eval.isMate && !moverMatesBefore;
    final matedAfter = b.eval.isMate && !moverMatesAfter;
    if (!forced && !isBest && !theory) {
      if (moverMatesBefore && !moverMatesAfter) tags.add(MoveTag.missedMate);
      if (!matedBefore && matedAfter && b.eval.mateIn! > 0) {
        tags.add(MoveTag.allowedMate);
      }
      if (wb >= 70 && wa <= 55) tags.add(MoveTag.missedWin);
      if (cls.isSerious && forcing) {
        tags.add(MoveTag.tacticalMiss);
      }
    }

    final bestSans = uciLineToSan(pos, a.pv.isNotEmpty ? a.pv : [?a.bestMove]);
    final replySans = uciLineToSan(ply.after, b.pv);
    out.add(
      MoveReview(
        ply: i,
        mover: mover,
        san: ply.san,
        cls: cls,
        loss: loss,
        accuracy: loss == 0 ? 100 : moveAccuracy(wb, wa),
        before: a.eval,
        after: b.eval,
        winBefore: wb,
        winAfter: wa,
        phase: phaseOf(pos),
        tags: tags,
        bestSan: bestSans.isEmpty ? null : bestSans.first,
        bestLine: formatLine(pos, bestSans),
        replyLine: formatLine(ply.after, replySans),
        depth: a.depth,
        bestIsForcing: forcing,
        secondWin: secondWin,
      ),
    );
  }
  return out;
}

/// A capture, check or promotion: the kind of move a tactic starts with.
bool _isForcing(Position pos, String uci) {
  final m = Move.parse(uci);
  if (m is! NormalMove || !pos.isLegal(m)) return false;
  if (m.promotion != null) return true;
  final target = pos.board.pieceAt(m.to);
  if (target != null && target.color != pos.turn) return true;
  if (pos.board.pieceAt(m.from)?.role == Role.pawn &&
      m.from.file != m.to.file) {
    return true; // en passant
  }
  return pos.play(m).isCheck;
}

/// A non-pawn piece moves where the opponent can legally take it and come
/// out ahead in material (it is undefended, or attacked by a cheaper piece).
/// A simple static check, not a full exchange evaluation.
bool isSacrifice(Position pos, String uci) {
  const value = {
    Role.pawn: 1,
    Role.knight: 3,
    Role.bishop: 3,
    Role.rook: 5,
    Role.queen: 9,
    Role.king: 0,
  };
  final m = Move.parse(uci);
  if (m is! NormalMove || !pos.isLegal(m)) return false;
  final piece = pos.board.pieceAt(m.from);
  if (piece == null || piece.role == Role.pawn || piece.role == Role.king) {
    return false;
  }
  final captured = pos.board.pieceAt(m.to);
  final gain = captured != null && captured.color != pos.turn
      ? value[captured.role]!
      : 0;
  final moved = value[piece.role]!;
  if (moved - gain < 2) return false;
  final after = pos.play(m);
  final takers = <int>[];
  for (final (s, p) in after.board.pieces) {
    if (p.color == after.turn && after.legalMovesOf(s).has(m.to)) {
      takers.add(value[p.role]!);
    }
  }
  if (takers.isEmpty) return false;
  final defended = after.kingAttackers(m.to, pos.turn).isNotEmpty;
  return !defended || takers.reduce(math.min) < moved;
}

class SideSummary {
  SideSummary(this.accuracy, this.counts, this.moves);
  final double? accuracy;
  final Map<MoveClass, int> counts;
  final int moves;
}

/// Counts every class; accuracy averages only real decisions (book moves and
/// forced moves are left out).
SideSummary summarize(List<MoveReview?> moves, Side side) {
  final mine = [
    for (final m in moves)
      if (m != null && m.mover == side) m,
  ];
  final counts = {for (final c in MoveClass.values) c: 0};
  for (final m in mine) {
    counts[m.cls] = counts[m.cls]! + 1;
  }
  final decisions = mine.where((m) => !m.cls.isRoutine).toList();
  final acc = decisions.isEmpty
      ? null
      : decisions.map((m) => m.accuracy).reduce((a, b) => a + b) /
            decisions.length;
  return SideSummary(acc, counts, decisions.length);
}

/// Biggest swings in the game: errors ordered by win% lost.
List<MoveReview> criticalMoments(List<MoveReview?> moves, {int limit = 5}) {
  final errs = [
    for (final m in moves)
      if (m != null && m.cls.isError) m,
  ]..sort((a, b) => b.loss.compareTo(a.loss));
  return errs.take(limit).toList();
}

/// Missed mates, missed wins and missed tactics, most costly first.
List<MoveReview> missedOpportunities(List<MoveReview?> moves, {int limit = 5}) {
  final out = [
    for (final m in moves)
      if (m != null &&
          (m.tags.contains(MoveTag.missedMate) ||
              m.tags.contains(MoveTag.missedWin) ||
              m.tags.contains(MoveTag.tacticalMiss)))
        m,
  ]..sort((a, b) => b.loss.compareTo(a.loss));
  return out.take(limit).toList();
}
