import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';

import '../../analysis/eval.dart';

/// Vertical bar showing White's winning chances; White's share is drawn on
/// the side of the board where White sits.
class EvalBar extends StatelessWidget {
  const EvalBar({
    super.key,
    required this.eval,
    required this.orientation,
    this.width = 14,
  });

  final Eval? eval;
  final Side orientation;
  final double width;

  @override
  Widget build(BuildContext context) {
    final w = (eval?.whiteWinPercent ?? 50) / 100;
    final whiteAtBottom = orientation == Side.white;
    final label = eval == null ? '' : eval!.label.replaceFirst('+', '');
    final whiteAhead = w >= 0.5;
    return Semantics(
      label: eval == null ? 'No evaluation' : 'Evaluation ${eval!.label}',
      child: SizedBox(
        width: width,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LayoutBuilder(
            builder: (context, c) {
              final h = c.maxHeight;
              return Stack(
                children: [
                  Container(color: const Color(0xFF3A3A3A)),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                    left: 0,
                    right: 0,
                    top: whiteAtBottom ? h * (1 - w) : 0,
                    height: h * w,
                    child: Container(color: const Color(0xFFF2F2F2)),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    // Label sits at the end of the side that is ahead.
                    top: whiteAhead == whiteAtBottom ? null : 2,
                    bottom: whiteAhead == whiteAtBottom ? 2 : null,
                    child: RotatedBox(
                      quarterTurns: label.length > 3 ? 3 : 0,
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: whiteAhead
                              ? const Color(0xFF3A3A3A)
                              : const Color(0xFFF2F2F2),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
