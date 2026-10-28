import 'package:dartchess/dartchess.dart';

import '../chess/chess_game.dart';
import 'review.dart';

/// Kinds of learning points Ply can back with concrete analysed positions.
enum LessonKind {
  missedMate('Missed a forced mate'),
  backRank('Back-rank weakness'),
  allowedMate('Allowed a forced mate'),
  hangingPiece('Left a piece hanging'),
  missedFork('Missed a fork'),
  missedTactic('Missed a tactic'),
  kingSafety('King safety'),
  missedDefence('Missed a defensive resource'),
  conversion('Let a winning position slip'),
  poorExchange('Poor exchange'),
  opening('Opening mistake');

  const LessonKind(this.label);
  final String label;
}

/// One learning point, tied to the move (ply index) it comes from.
class Lesson {
  const Lesson(this.kind, this.ply, this.text);
  final LessonKind kind;
  final int ply;
  final String text;
}

const _value = {
  Role.pawn: 1,
  Role.knight: 3,
  Role.bishop: 3,
  Role.rook: 5,
  Role.queen: 9,
  Role.king: 100,
};

/// Finds learning points in a reviewed game. Each move yields at most one
/// lesson (the most specific that applies), and only moves the engine
/// marked as errors or tagged (missed mate/win) are considered.
/// Pass [side] to look only at one player's moves.
List<Lesson> findLessons(
  ChessGame game,
  GameReview data,
  List<MoveReview?> moves, {
  Side? side,
}) {
  final out = <Lesson>[];
  for (final m in moves) {
    if (m == null || (side != null && m.mover != side)) continue;
    final relevant =
        m.cls.isError ||
        m.tags.contains(MoveTag.missedMate) ||
        m.tags.contains(MoveTag.missedWin);
    if (!relevant) continue;
    final lesson = _lessonFor(game, data, m);
    if (lesson != null) out.add(lesson);
  }
  return out;
}

Lesson? _lessonFor(ChessGame game, GameReview data, MoveReview m) {
  final before = game.positionAt(m.ply);
  final after = game.plies[m.ply].after;
  final a = data.positions[m.ply]!;
  final b = data.positions[m.ply + 1]!;
  final no = '${before.fullmoves}${m.mover == Side.white ? '.' : '…'}';
  final played = '$no ${m.san}';
  final best = m.bestSan;
  final reply = b.pv.isEmpty ? null : Move.parse(b.pv.first);

  if (m.tags.contains(MoveTag.missedMate)) {
    return Lesson(
      LessonKind.missedMate,
      m.ply,
      '$played missed mate in ${m.before.mateIn}: ${m.bestLine}.',
    );
  }
  if (m.tags.contains(MoveTag.allowedMate)) {
    final backRank = _isBackRankMate(after, b.pv, m.mover);
    return Lesson(
      backRank ? LessonKind.backRank : LessonKind.allowedMate,
      m.ply,
      backRank
          ? '$played allows a mate on your back rank: ${m.replyLine}.'
          : '$played allows mate in ${m.after.mateIn}: ${m.replyLine}.',
    );
  }
  if (!m.cls.isError) {
    // Only tagged moves remain (missed win without a large loss).
    return m.tags.contains(MoveTag.missedWin)
        ? Lesson(LessonKind.conversion, m.ply, _slip(played, m))
        : null;
  }
  final hanging = _hangingCapture(after, reply, m.mover);
  if (m.cls.isSerious && hanging != null) {
    return Lesson(
      LessonKind.hangingPiece,
      m.ply,
      '$played left the ${hanging.$1} on ${hanging.$2} unprotected; '
      'Stockfish answers ${m.replyLine}.',
    );
  }
  if (a.bestMove != null && _isFork(before, a.bestMove!)) {
    return Lesson(
      LessonKind.missedFork,
      m.ply,
      '$best was a fork, attacking two targets at once (${m.bestLine}).',
    );
  }
  if (m.tags.contains(MoveTag.tacticalMiss)) {
    return Lesson(
      LessonKind.missedTactic,
      m.ply,
      '$played missed $best (${m.bestLine}).',
    );
  }
  if (m.cls.isSerious && reply != null && after.isLegal(reply)) {
    if (after.play(reply).isCheck) {
      return Lesson(
        LessonKind.kingSafety,
        m.ply,
        '$played exposed your king: Stockfish continues ${m.replyLine}.',
      );
    }
  }
  if (m.tags.contains(MoveTag.missedWin)) {
    return Lesson(LessonKind.conversion, m.ply, _slip(played, m));
  }
  if (m.cls.isSerious &&
      m.winBefore >= 25 &&
      m.winBefore < 70 &&
      m.winAfter < 15) {
    final draw = m.winBefore < 60;
    return Lesson(
      LessonKind.missedDefence,
      m.ply,
      draw
          ? '$played turned a holdable position into a lost one; $best kept '
                'it balanced (${m.before.label}).'
          : '$played gave away the advantage; $best held (${m.before.label}).',
    );
  }
  final target = before.board.pieceAt(_to(game.plies[m.ply].uci));
  if (m.cls.isSerious && target != null && target.color != m.mover) {
    return Lesson(
      LessonKind.poorExchange,
      m.ply,
      'The capture $played cost ${m.loss.round()} percentage points; '
      '$best was better (${m.before.label} instead of ${m.after.label}).',
    );
  }
  if (m.phase == Phase.opening) {
    return Lesson(
      LessonKind.opening,
      m.ply,
      '$played: Stockfish preferred $best (${m.before.label} instead of '
      '${m.after.label}).',
    );
  }
  return null;
}

String _slip(String played, MoveReview m) =>
    '$played dropped your winning chances from ${m.winBefore.round()}% to '
    '${m.winAfter.round()}%; ${m.bestSan} kept the advantage.';

Square _to(String uci) => Square.fromName(uci.substring(2, 4));

/// The engine's reply captures a piece that was undefended or attacked by a
/// cheaper piece. Returns (piece name, square name).
(String, String)? _hangingCapture(Position after, Move? reply, Side mover) {
  if (reply is! NormalMove || !after.isLegal(reply)) return null;
  final target = after.board.pieceAt(reply.to);
  final attacker = after.board.pieceAt(reply.from);
  if (target == null || attacker == null || target.color != mover) return null;
  if (target.role == Role.pawn) return null;
  final defended = after.kingAttackers(reply.to, mover).isNotEmpty;
  if (defended && _value[attacker.role]! >= _value[target.role]!) return null;
  return (target.role.name, reply.to.name);
}

/// The move puts a piece where it attacks two or more valuable targets:
/// the king, or pieces worth more than it or left undefended.
bool _isFork(Position pos, String uci) {
  final m = Move.parse(uci);
  if (m is! NormalMove || !pos.isLegal(m)) return false;
  final after = pos.play(m);
  final piece = after.board.pieceAt(m.to);
  if (piece == null) return false;
  var targets = 0;
  final hits =
      attacks(piece, m.to, after.board.occupied) &
      after.board.bySide(piece.color.opposite);
  for (final s in hits.squares) {
    final t = after.board.pieceAt(s)!;
    if (t.role == Role.pawn) continue;
    final undefended = after.kingAttackers(s, t.color).isEmpty;
    if (t.role == Role.king ||
        _value[t.role]! > _value[piece.role]! ||
        undefended) {
      targets++;
    }
  }
  return targets >= 2;
}

/// Plays [pv] from [pos]; true if it ends in mate of [side] with the king on
/// its own back rank, delivered by a rook or queen on that rank.
bool _isBackRankMate(Position pos, List<String> pv, Side side) {
  var p = pos;
  NormalMove? last;
  for (final u in pv) {
    final m = Move.parse(u);
    if (m is! NormalMove || !p.isLegal(m)) return false;
    p = p.play(m);
    last = m;
  }
  if (!p.isCheckmate || p.turn != side || last == null) return false;
  final king = p.board.kingOf(side);
  final rank = side == Side.white ? Rank.first : Rank.eighth;
  final mater = p.board.pieceAt(last.to);
  return king != null &&
      king.rank == rank &&
      last.to.rank == rank &&
      (mater?.role == Role.rook || mater?.role == Role.queen);
}

/// Lessons grouped by kind, most frequent first.
List<(LessonKind, List<Lesson>)> groupLessons(List<Lesson> lessons) {
  final map = <LessonKind, List<Lesson>>{};
  for (final l in lessons) {
    (map[l.kind] ??= []).add(l);
  }
  final out = [for (final e in map.entries) (e.key, e.value)];
  out.sort((a, b) {
    final c = b.$2.length.compareTo(a.$2.length);
    return c != 0 ? c : a.$1.index.compareTo(b.$1.index);
  });
  return out;
}
