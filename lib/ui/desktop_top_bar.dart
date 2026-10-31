import 'package:dartchess/dartchess.dart' show Piece, Role, Side;
import 'package:flutter/material.dart';

import 'board/chess_board.dart';
import 'services.dart';
import 'theme.dart';

/// Desktop header: branding and the section tabs. Loading games lives in
/// the Game Analysis panel (Your games).
class DesktopTopBar extends StatelessWidget {
  const DesktopTopBar({super.key, required this.sections});

  /// Section names in tab order (Analyze, History, Insights, Settings).
  final List<String> sections;

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final p = PlyPalette.of(context);
    final theme = Theme.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: s.tab,
      builder: (context, tab, _) => Container(
        height: 56,
        color: p.panel,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            PieceImage(
              const Piece(color: Side.white, role: Role.pawn),
              size: 30,
            ),
            const SizedBox(width: 6),
            Text(
              'Ply',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            // Takes the free space, so the section tabs sit at the right.
            Expanded(
              child: Text(
                'Every move teaches.',
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: theme.textTheme.bodySmall?.copyWith(color: p.muted),
              ),
            ),
            for (final (i, name) in sections.indexed)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: tab == i
                        ? theme.colorScheme.primary
                        : p.muted,
                    backgroundColor: tab == i
                        ? theme.colorScheme.primary.withValues(alpha: 0.12)
                        : null,
                  ),
                  onPressed: () => s.tab.value = i,
                  child: Text(name),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
