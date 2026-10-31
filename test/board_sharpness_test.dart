// The board must land on whole physical pixels at any window size and any
// Windows display scaling, or every square edge and piece outline is
// smeared across two pixels and looks blurry.
import 'dart:ui' as ui;

import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ply/ui/board/chess_board.dart';
import 'package:ply/ui/theme.dart';

void main() {
  /// Renders the start position in a box of [box] logical pixels placed at
  /// [at], at [dpr], and returns the colours along a row through rank 4
  /// (empty squares only), in physical pixels.
  Future<List<Color>> rank4(
    WidgetTester tester, {
    required double dpr,
    required double box,
    required Offset at,
  }) async {
    final key = GlobalKey();
    tester.view.devicePixelRatio = dpr;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              Positioned(
                left: at.dx,
                top: at.dy,
                width: box,
                height: box,
                child: ChessBoard(
                  position: Chess.initial,
                  orientation: Side.white,
                  showCoordinates: false,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final rect = tester.getRect(find.byType(CustomPaint).first);
    final image = await tester.runAsync(() async {
      final b =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      return b.toImage(pixelRatio: dpr);
    });
    final data = (await tester.runAsync(
      () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
    ))!;
    // Middle of rank 4 (the 5th row from the top on a white-oriented board).
    final y = ((rect.top + rect.height * 4.5 / 8) * dpr).round();
    final x0 = ((rect.left + 2) * dpr).ceil();
    final x1 = ((rect.right - 2) * dpr).floor();
    return [
      for (var x = x0; x < x1; x++)
        Color.fromARGB(
          data.getUint8((y * image!.width + x) * 4 + 3),
          data.getUint8((y * image.width + x) * 4),
          data.getUint8((y * image.width + x) * 4 + 1),
          data.getUint8((y * image.width + x) * 4 + 2),
        ),
    ];
  }

  for (final dpr in [1.0, 1.25, 1.5, 1.75]) {
    testWidgets('square edges are hard at ${(dpr * 100).round()}% scaling', (
      tester,
    ) async {
      // A fractional size and position, as a resized window produces.
      final row = await rank4(
        tester,
        dpr: dpr,
        box: 583.37,
        at: const Offset(101.3, 57.6),
      );
      final blended = row
          .where((c) => c != BoardColors.light && c != BoardColors.dark)
          .length;
      expect(blended, 0, reason: '$blended blended pixels on rank 4');
    });
  }
}
