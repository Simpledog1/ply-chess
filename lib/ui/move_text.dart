import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';

import 'board/chess_board.dart';

/// A SAN move. Unless [simple], piece letters are drawn as small Cburnett
/// piece images (figurine notation), e.g. "Nf3" → [knight]f3. Figurines
/// always use the white (outlined) pieces so they read on dark and light.
class MoveText extends StatelessWidget {
  const MoveText(
    this.san, {
    super.key,
    required this.simple,
    this.style,
    this.prefix = '',
    this.suffix = '',
  });

  final String san;
  final bool simple;
  final TextStyle? style;
  final String prefix;
  final String suffix;

  static const _roles = {
    'K': Role.king,
    'Q': Role.queen,
    'R': Role.rook,
    'B': Role.bishop,
    'N': Role.knight,
  };

  @override
  Widget build(BuildContext context) {
    final st = style ?? DefaultTextStyle.of(context).style;
    if (simple) return Text('$prefix$san$suffix', style: st);
    final size = (st.fontSize ?? 14) * 1.15;
    final spans = <InlineSpan>[TextSpan(text: prefix)];
    final buf = StringBuffer();
    for (final ch in san.split('')) {
      final role = _roles[ch];
      if (role == null) {
        buf.write(ch);
        continue;
      }
      if (buf.isNotEmpty) {
        spans.add(TextSpan(text: buf.toString()));
        buf.clear();
      }
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: PieceImage(
            Piece(color: Side.white, role: role),
            size: size,
          ),
        ),
      );
    }
    buf.write(suffix);
    spans.add(TextSpan(text: buf.toString()));
    return Text.rich(TextSpan(children: spans), style: st);
  }
}
