import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';

import '../chess/chess_game.dart';
import 'eval.dart';

enum MoveClass {
  best('Best'),
  excellent('Excellent'),
  good('Good'),
  inaccuracy('Inaccuracy'),
  mistake('Mistake'),
  blunder('Blunder'),
  forced('Forced');

  const MoveClass(this.label);
  final String label;

  bool get isError => index >= inaccuracy.index && this != forced;
}

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
  });

  final Eval eval;
  final int depth;
  final String? bestMove;
  final List<String> pv;

  Map<String, dynamic> toJson() => {
    'e': eval.toJson(),
    'd': depth,
    if (bestMove != null) 'b': bestMove,
    if (pv.isNotEmpty) 'pv': pv,
  };

  factory PositionAnalysis.fromJson(Map<String, dynamic> j) => PositionAnalysis(
    eval: Eval.fromJson(j['e'] as Map<String, dynamic>),
    depth: j['d'] as int,
    bestMove: j['b'] as String?,
    pv: (j['pv'] as List?)?.cast<String>() ?? const [],
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

  /// A factual summary built only from engine output.
  String get explanation {
    final parts = <String>[];
    if (cls == MoveClass.forced) return 'Only legal move.';
    if (cls == MoveClass.best) {
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
    if (cls != MoveClass.best && loss >= 1) {
      final who = mover == Side.white ? 'White' : 'Black';
      parts.add(
        '$who\'s winning chances: '
        '${winBefore.round()}% → ${winAfter.round()}%.',
      );
    }
    return parts.join(' ');
  }
}

/// Computes per-move reviews. Entries are null where either surrounding
/// position has not been analysed.
List<MoveReview?> reviewMoves(ChessGame game, GameReview data, Thresholds t) {
  final out = <MoveReview?>[];
  for (var i = 0; i < game.length; i++) {
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
    final loss = (forced || isBest) ? 0.0 : math.max(0.0, wb - wa);
    final cls = forced
        ? MoveClass.forced
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
    if (!forced && !isBest) {
      if (moverMatesBefore && !moverMatesAfter) tags.add(MoveTag.missedMate);
      if (!matedBefore && matedAfter && b.eval.mateIn! > 0) {
        tags.add(MoveTag.allowedMate);
      }
      if (wb >= 70 && wa <= 55) tags.add(MoveTag.missedWin);
      if (cls.index >= MoveClass.mistake.index && forcing) {
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
        accuracy: (forced || isBest) ? 100 : moveAccuracy(wb, wa),
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

class SideSummary {
  SideSummary(this.accuracy, this.counts, this.moves);
  final double? accuracy;
  final Map<MoveClass, int> counts;
  final int moves;
}

SideSummary summarize(List<MoveReview?> moves, Side side) {
  final mine = [
    for (final m in moves)
      if (m != null && m.mover == side && m.cls != MoveClass.forced) m,
  ];
  final counts = {for (final c in MoveClass.values) c: 0};
  for (final m in mine) {
    counts[m.cls] = counts[m.cls]! + 1;
  }
  final acc = mine.isEmpty
      ? null
      : mine.map((m) => m.accuracy).reduce((a, b) => a + b) / mine.length;
  return SideSummary(acc, counts, mine.length);
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
