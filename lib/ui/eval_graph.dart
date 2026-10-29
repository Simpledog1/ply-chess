import 'package:flutter/material.dart';

import '../analysis/review.dart';
import 'theme.dart';

const accuracyNote =
    'Accuracy follows the Lichess formula: each move scores 0–100 from how much '
    'it lowered your winning chances, as estimated by Stockfish at a fixed depth. '
    'Ply reports the plain average over your moves. It is an estimate: it depends on '
    'search depth, treats every move equally (easy recaptures count as much as hard '
    'decisions), and is not comparable with other sites\' numbers. Best moves and forced '
    'moves score 100.';

/// White's winning chances after every ply; tap to jump to a position.
class EvalGraph extends StatelessWidget {
  const EvalGraph({
    super.key,
    required this.review,
    required this.moves,
    required this.current,
    required this.onTap,
  });
  final GameReview review;
  final List<MoveReview?> moves;
  final int current;
  final void Function(int ply) onTap;

  @override
  Widget build(BuildContext context) {
    final n = review.positions.length;
    return LayoutBuilder(
      builder: (context, c) {
        return GestureDetector(
          onTapUp: (d) => onTap(
            ((d.localPosition.dx / c.maxWidth) * (n - 1)).round().clamp(
              0,
              n - 1,
            ),
          ),
          child: CustomPaint(
            size: Size(c.maxWidth, c.maxHeight),
            painter: _GraphPainter(
              review,
              moves,
              current,
              Theme.of(context).colorScheme,
            ),
          ),
        );
      },
    );
  }
}

class _GraphPainter extends CustomPainter {
  _GraphPainter(this.review, this.moves, this.current, this.scheme);
  final GameReview review;
  final List<MoveReview?> moves;
  final int current;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final n = review.positions.length;
    if (n < 2) return;
    double x(int i) => size.width * i / (n - 1);
    double y(double w) => size.height * (1 - w / 100);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)),
      Paint()..color = const Color(0xFF2A3039),
    );
    final path = Path()..moveTo(0, size.height);
    double last = 50;
    for (var i = 0; i < n; i++) {
      final p = review.positions[i];
      last = p?.eval.whiteWinPercent ?? last;
      path.lineTo(x(i), y(last));
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)),
    );
    canvas.drawPath(path, Paint()..color = const Color(0xFFE3E7EC));
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      Paint()
        ..color = scheme.primary.withValues(alpha: 0.5)
        ..strokeWidth = 1,
    );
    canvas.drawLine(
      Offset(x(current.clamp(0, n - 1)), 0),
      Offset(x(current.clamp(0, n - 1)), size.height),
      Paint()
        ..color = scheme.primary
        ..strokeWidth = 2,
    );
    for (final m in moves) {
      if (m == null || !m.cls.isError) continue;
      final p = review.positions[m.ply + 1];
      if (p == null) continue;
      canvas.drawCircle(
        Offset(x(m.ply + 1), y(p.eval.whiteWinPercent)),
        4,
        Paint()..color = classColor(m.cls),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GraphPainter old) => true;
}
