// Renders the Windows app icon (Cburnett pawn on Ply blue) and packs it into
// an .ico file. Skipped unless PLY_ICON_OUT is set:
//   PLY_ICON_OUT=windows/runner/resources/app_icon.ico flutter test test/make_icon_test.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dartchess/dartchess.dart' show Piece, Role, Side;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ply/ui/board/chess_board.dart';
import 'package:ply/ui/theme.dart';

/// Packs PNG images into an ICO container (PNG-compressed entries).
Uint8List packIco(List<(int, Uint8List)> pngs) {
  final header = BytesBuilder()
    ..add([0, 0, 1, 0, pngs.length & 0xff, pngs.length >> 8]);
  var offset = 6 + 16 * pngs.length;
  final dir = BytesBuilder();
  for (final (size, png) in pngs) {
    final d = ByteData(16)
      ..setUint8(0, size >= 256 ? 0 : size)
      ..setUint8(1, size >= 256 ? 0 : size)
      ..setUint16(4, 1, Endian.little) // planes
      ..setUint16(6, 32, Endian.little) // bits per pixel
      ..setUint32(8, png.length, Endian.little)
      ..setUint32(12, offset, Endian.little);
    dir.add(d.buffer.asUint8List());
    offset += png.length;
  }
  return (header
        ..add(dir.toBytes())
        ..add([for (final (_, png) in pngs) ...png]))
      .toBytes();
}

void main() {
  final out = Platform.environment['PLY_ICON_OUT'];

  test('ico header and directory are well formed', () {
    final ico = packIco([
      (16, Uint8List.fromList([1, 2, 3])),
      (256, Uint8List.fromList([4, 5])),
    ]);
    final b = ByteData.sublistView(ico);
    expect(b.getUint16(2, Endian.little), 1); // icon type
    expect(b.getUint16(4, Endian.little), 2); // entries
    expect(b.getUint8(6), 16);
    expect(b.getUint8(22), 0); // 256 is stored as 0
    expect(b.getUint32(18, Endian.little), 38); // first image offset
    expect(ico.length, 38 + 3 + 2);
  });

  testWidgets('render app icon', (tester) async {
    final key = GlobalKey();
    await tester.runAsync(precachePieces);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: Container(
              width: 256,
              height: 256,
              decoration: BoxDecoration(
                color: plyBlue,
                borderRadius: BorderRadius.circular(56),
              ),
              padding: const EdgeInsets.all(28),
              child: const PieceImage(
                Piece(color: Side.white, role: Role.pawn),
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
    }
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final pngs = <(int, Uint8List)>[];
      for (final size in const [16, 24, 32, 48, 64, 128, 256]) {
        final image = await boundary.toImage(pixelRatio: size / 256);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        pngs.add((size, data!.buffer.asUint8List()));
      }
      File(out!).writeAsBytesSync(packIco(pngs));
    });
  }, skip: out == null);
}
