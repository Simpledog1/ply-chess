import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme.dart';

String pieceAsset(Piece p) =>
    'assets/pieces/cburnett/${p.color == Side.white ? 'w' : 'b'}${p.role.uppercaseLetter}.svg';

/// Loads all twelve piece SVGs into flutter_svg's cache so the first board
/// frame doesn't flicker.
Future<void> precachePieces() async {
  for (final side in Side.values) {
    for (final role in Role.values) {
      final loader = SvgAssetLoader(pieceAsset(Piece(color: side, role: role)));
      await svg.cache.putIfAbsent(
        loader.cacheKey(null),
        () => loader.loadBytes(null),
      );
    }
  }
}

class PieceImage extends StatelessWidget {
  const PieceImage(this.piece, {super.key, this.size});
  final Piece piece;
  final double? size;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    pieceAsset(piece),
    width: size,
    height: size,
    semanticsLabel: '${piece.color.name} ${piece.role.name}',
  );
}

class BoardArrow {
  const BoardArrow(this.from, this.to, [this.color = BoardColors.arrow]);
  final Square from;
  final Square to;
  final Color color;
}

/// An interactive chessboard. Tap a piece then a destination, or drag it.
/// Promotions ask which piece to promote to.
class ChessBoard extends StatefulWidget {
  const ChessBoard({
    super.key,
    required this.position,
    required this.orientation,
    this.onMove,
    this.lastMove,
    this.arrows = const [],
    this.showCoordinates = true,
    this.badge,
  });

  final Position position;
  final Side orientation;

  /// Null makes the board read-only.
  final void Function(NormalMove move)? onMove;
  final (Square, Square)? lastMove;
  final List<BoardArrow> arrows;
  final bool showCoordinates;

  /// Optional small marker drawn on a square (e.g. move classification).
  final (Square, Widget)? badge;

  @override
  State<ChessBoard> createState() => _ChessBoardState();
}

class _ChessBoardState extends State<ChessBoard> {
  Square? _selected;
  Square? _dragFrom;
  Offset? _dragPos;
  late Map<Square, Set<Square>> _dests;

  @override
  void initState() {
    super.initState();
    _dests = makeLegalMoves(widget.position);
  }

  @override
  void didUpdateWidget(ChessBoard old) {
    super.didUpdateWidget(old);
    if (old.position != widget.position) {
      _dests = makeLegalMoves(widget.position);
      _selected = null;
      _dragFrom = null;
    }
  }

  bool get _interactive => widget.onMove != null && !widget.position.isGameOver;

  Square _squareAt(Offset local, double sq) {
    var file = (local.dx / sq).floor().clamp(0, 7);
    var rank = 7 - (local.dy / sq).floor().clamp(0, 7);
    if (widget.orientation == Side.black) {
      file = 7 - file;
      rank = 7 - rank;
    }
    return Square.fromCoords(File(file), Rank(rank));
  }

  Offset _origin(Square s, double sq) {
    final f = widget.orientation == Side.white ? s.file : 7 - s.file;
    final r = widget.orientation == Side.white ? 7 - s.rank : s.rank;
    return Offset(f * sq, r * sq);
  }

  bool _ownPiece(Square s) =>
      widget.position.board.pieceAt(s)?.color == widget.position.turn;

  Future<void> _tryMove(Square from, Square to) async {
    if (!(_dests[from]?.contains(to) ?? false)) return;
    final piece = widget.position.board.pieceAt(from)!;
    Role? promotion;
    if (piece.role == Role.pawn &&
        (to.rank == Rank.first || to.rank == Rank.eighth)) {
      promotion = await _askPromotion(piece.color);
      if (promotion == null) return;
    }
    setState(() => _selected = null);
    widget.onMove!(NormalMove(from: from, to: to, promotion: promotion));
  }

  Future<Role?> _askPromotion(Side side) => showDialog<Role>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Promote to'),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final r in [Role.queen, Role.rook, Role.bishop, Role.knight])
                IconButton(
                  tooltip: r.name,
                  iconSize: 56,
                  onPressed: () => Navigator.pop(ctx, r),
                  icon: PieceImage(Piece(color: side, role: r), size: 56),
                ),
            ],
          ),
        ),
      ],
    ),
  );

  void _onTap(Square s) {
    if (!_interactive) return;
    final sel = _selected;
    if (sel != null && sel != s && (_dests[sel]?.contains(s) ?? false)) {
      _tryMove(sel, s);
    } else if (_ownPiece(s) && sel != s) {
      setState(() => _selected = s);
    } else {
      setState(() => _selected = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, c) {
          // Squares a whole number of physical pixels wide, so square edges
          // and pieces are not smeared across two pixels at any window size
          // or display scaling (the board may come out up to 8 px smaller).
          final size = math.max(8, (c.maxWidth * dpr / 8).floor() * 8) / dpr;
          final sq = size / 8;
          final pos = widget.position;
          final king = pos.isCheck ? pos.board.kingOf(pos.turn) : null;
          final shown = _selected ?? _dragFrom;
          final children = <Widget>[
            CustomPaint(
              size: Size.square(size),
              painter: _SquaresPainter(
                orientation: widget.orientation,
                lastMove: widget.lastMove,
                selected: shown,
                dests: shown == null ? const {} : (_dests[shown] ?? const {}),
                occupied: (s) => pos.board.pieceAt(s) != null,
                ownPiece: _ownPiece,
                check: king,
                coordinates: widget.showCoordinates,
                textStyle: Theme.of(context).textTheme.labelSmall!,
              ),
            ),
          ];
          for (final (s, p) in pos.board.pieces) {
            if (s == _dragFrom && _dragPos != null) continue;
            final o = _origin(s, sq);
            children.add(
              Positioned(
                left: o.dx,
                top: o.dy,
                width: sq,
                height: sq,
                child: IgnorePointer(child: PieceImage(p)),
              ),
            );
          }
          if (widget.arrows.isNotEmpty) {
            children.add(
              IgnorePointer(
                child: CustomPaint(
                  size: Size.square(size),
                  painter: _ArrowPainter([
                    for (final a in widget.arrows)
                      (_origin(a.from, sq), _origin(a.to, sq), a.color),
                  ], sq),
                ),
              ),
            );
          }
          final badge = widget.badge;
          if (badge != null) {
            final o = _origin(badge.$1, sq);
            final d = sq * 0.42;
            children.add(
              Positioned(
                left: math.min(o.dx + sq - d * 0.7, size - d),
                top: math.max(o.dy - d * 0.3, 0),
                width: d,
                height: d,
                child: IgnorePointer(child: badge.$2),
              ),
            );
          }
          final dragPiece = _dragFrom == null
              ? null
              : pos.board.pieceAt(_dragFrom!);
          if (dragPiece != null && _dragPos != null) {
            final d = sq * 1.3;
            children.add(
              Positioned(
                left: _dragPos!.dx - d / 2,
                top: _dragPos!.dy - d * 0.75,
                width: d,
                height: d,
                child: IgnorePointer(child: PieceImage(dragPiece)),
              ),
            );
          }
          final board = Semantics(
            label: 'Chessboard',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => _onTap(_squareAt(d.localPosition, sq)),
              onPanStart: (d) {
                if (!_interactive) return;
                final s = _squareAt(d.localPosition, sq);
                if (_ownPiece(s)) {
                  setState(() {
                    _dragFrom = s;
                    _selected = s;
                    _dragPos = d.localPosition;
                  });
                }
              },
              onPanUpdate: (d) {
                if (_dragFrom != null) {
                  setState(() => _dragPos = d.localPosition);
                }
              },
              onPanEnd: (_) {
                final from = _dragFrom, at = _dragPos;
                setState(() {
                  _dragFrom = null;
                  _dragPos = null;
                });
                if (from == null || at == null) return;
                final to = _squareAt(at, sq);
                if (to != from) _tryMove(from, to);
              },
              onPanCancel: () => setState(() {
                _dragFrom = null;
                _dragPos = null;
              }),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Stack(clipBehavior: Clip.none, children: children),
              ),
            ),
          );
          return Align(
            alignment: Alignment.topLeft,
            child: _PixelSnap(
              dpr: dpr,
              child: SizedBox.square(dimension: size, child: board),
            ),
          );
        },
      ),
    );
  }
}

/// Paints its child shifted by under one physical pixel so that the child's
/// top-left corner falls on a whole physical pixel.
/// shortcut: the shift is computed when painting; a board inside a scrolled
/// layer that moves without repainting could be off by a fraction of a pixel
/// until its next repaint. Fine for Ply's fixed board placements.
class _PixelSnap extends SingleChildRenderObjectWidget {
  const _PixelSnap({required this.dpr, super.child});
  final double dpr;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPixelSnap(dpr);

  @override
  void updateRenderObject(BuildContext context, _RenderPixelSnap r) =>
      r.dpr = dpr;
}

class _RenderPixelSnap extends RenderProxyBox {
  _RenderPixelSnap(this._dpr);

  double _dpr;
  set dpr(double v) {
    if (v == _dpr) return;
    _dpr = v;
    markNeedsPaint();
  }

  Offset _shift = Offset.zero;

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    final global = MatrixUtils.transformPoint(
      getTransformTo(null),
      Offset.zero,
    );
    double snap(double v) => (v * _dpr).roundToDouble() / _dpr;
    _shift = Offset(snap(global.dx), snap(global.dy)) - global;
    context.paintChild(child, offset + _shift);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      super.hitTestChildren(result, position: position - _shift);

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) =>
      transform.translateByDouble(_shift.dx, _shift.dy, 0, 1);
}

class _SquaresPainter extends CustomPainter {
  _SquaresPainter({
    required this.orientation,
    required this.lastMove,
    required this.selected,
    required this.dests,
    required this.occupied,
    required this.ownPiece,
    required this.check,
    required this.coordinates,
    required this.textStyle,
  });

  final Side orientation;
  final (Square, Square)? lastMove;
  final Square? selected;
  final Set<Square> dests;
  final bool Function(Square) occupied;
  final bool Function(Square) ownPiece;
  final Square? check;
  final bool coordinates;
  final TextStyle textStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final sq = size.width / 8;
    Rect rect(Square s) {
      final f = orientation == Side.white ? s.file : 7 - s.file;
      final r = orientation == Side.white ? 7 - s.rank : s.rank;
      return Rect.fromLTWH(f * sq, r * sq, sq, sq);
    }

    for (final s in Square.values) {
      final light = (s.file + s.rank).isOdd;
      canvas.drawRect(
        rect(s),
        Paint()..color = light ? BoardColors.light : BoardColors.dark,
      );
    }
    final lm = lastMove;
    if (lm != null) {
      for (final s in [lm.$1, lm.$2]) {
        canvas.drawRect(rect(s), Paint()..color = BoardColors.lastMove);
      }
    }
    if (selected != null) {
      canvas.drawRect(rect(selected!), Paint()..color = BoardColors.selected);
    }
    final k = check;
    if (k != null) {
      final r = rect(k);
      canvas.drawRect(
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              BoardColors.check,
              BoardColors.check.withValues(alpha: 0.6),
              BoardColors.check.withValues(alpha: 0),
            ],
            stops: const [0, 0.35, 0.9],
          ).createShader(r),
      );
    }
    for (final d in dests) {
      if (ownPiece(d)) continue; // castling written as king-takes-rook
      final r = rect(d);
      if (occupied(d)) {
        canvas.drawCircle(
          r.center,
          sq * 0.46,
          Paint()
            ..color = BoardColors.dot
            ..style = PaintingStyle.stroke
            ..strokeWidth = sq * 0.08,
        );
      } else {
        canvas.drawCircle(
          r.center,
          sq * 0.16,
          Paint()..color = BoardColors.dot,
        );
      }
    }
    if (coordinates) {
      for (var i = 0; i < 8; i++) {
        final file = orientation == Side.white ? i : 7 - i;
        final rank = orientation == Side.white ? 7 - i : i;
        final edgeRank = orientation == Side.white ? 0 : 7;
        final edgeFile = orientation == Side.white ? 0 : 7;
        // Files along the bottom edge, ranks along the left edge.
        _text(
          canvas,
          'abcdefgh'[file],
          Offset(i * sq + sq - 2, size.height - 2),
          (file + edgeRank).isOdd,
          sq,
          alignEnd: true,
        );
        _text(
          canvas,
          '${rank + 1}',
          Offset(2, i * sq + 1),
          (edgeFile + rank).isOdd,
          sq,
        );
      }
    }
  }

  void _text(
    Canvas c,
    String s,
    Offset at,
    bool onLight,
    double sq, {
    bool alignEnd = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: textStyle.copyWith(
          fontSize: sq * 0.2,
          fontWeight: FontWeight.w600,
          color: onLight ? BoardColors.dark : BoardColors.light,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final o = alignEnd ? Offset(at.dx - tp.width, at.dy - tp.height) : at;
    tp.paint(c, o);
  }

  @override
  bool shouldRepaint(_SquaresPainter old) =>
      old.orientation != orientation ||
      old.lastMove != lastMove ||
      old.selected != selected ||
      old.dests != dests ||
      old.check != check ||
      old.coordinates != coordinates;
}

class _ArrowPainter extends CustomPainter {
  _ArrowPainter(this.arrows, this.sq);
  final List<(Offset, Offset, Color)> arrows;
  final double sq;

  @override
  void paint(Canvas canvas, Size size) {
    final half = Offset(sq / 2, sq / 2);
    for (final (a, b, color) in arrows) {
      final from = a + half, to = b + half;
      final dir = to - from;
      final len = dir.distance;
      if (len == 0) continue;
      final u = dir / len;
      final head = sq * 0.42;
      final end = to - u * head;
      final paint = Paint()
        ..color = color
        ..strokeWidth = sq * 0.16
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(from + u * sq * 0.2, end, paint);
      final n = Offset(-u.dy, u.dx);
      canvas.drawPath(
        Path()
          ..moveTo(to.dx, to.dy)
          ..lineTo(end.dx + n.dx * head * 0.6, end.dy + n.dy * head * 0.6)
          ..lineTo(end.dx - n.dx * head * 0.6, end.dy - n.dy * head * 0.6)
          ..close(),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => true;
}
