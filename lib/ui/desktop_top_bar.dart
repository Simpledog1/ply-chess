import 'package:dartchess/dartchess.dart' show Piece, Role, Side;
import 'package:flutter/material.dart';

import '../online/online_games.dart';
import '../storage/settings.dart';
import 'board/chess_board.dart';
import 'services.dart';
import 'theme.dart';

/// Desktop header: branding, site + username to load games, section tabs.
class DesktopTopBar extends StatefulWidget {
  const DesktopTopBar({super.key, required this.sections});

  /// Section names in tab order (Analyze, History, Insights, Settings).
  final List<String> sections;

  @override
  State<DesktopTopBar> createState() => _DesktopTopBarState();
}

class _DesktopTopBarState extends State<DesktopTopBar> {
  TextEditingController? _name;

  ChessSite _site(Settings s) => s.loadSource.site ?? ChessSite.lichess;

  Future<void> _load() async {
    final s = Services.of(context);
    final name = _name?.text.trim() ?? '';
    if (name.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    s.tab.value = 0;
    await s.browser.open(_site(s.settings), name);
  }

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final p = PlyPalette.of(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([s.settings, s.browser, s.tab]),
      builder: (context, _) {
        final site = _site(s.settings);
        final known = [
          for (final pr in s.settings.profiles)
            if (pr.site == site) pr.username,
        ];
        return Container(
          height: 60,
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
              Flexible(
                child: Text(
                  'Every move teaches.',
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: theme.textTheme.bodySmall?.copyWith(color: p.muted),
                ),
              ),
              const SizedBox(width: 16),
              SegmentedButton<ChessSite>(
                showSelectedIcon: false,
                segments: [
                  for (final v in ChessSite.values)
                    ButtonSegment(value: v, label: Text(v.label)),
                ],
                selected: {site},
                onSelectionChanged: (v) => s.settings.update(
                  (x) => x.loadSource = v.first == ChessSite.lichess
                      ? LoadSource.lichess
                      : LoadSource.chessCom,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 220,
                child: Autocomplete<String>(
                  initialValue: TextEditingValue(
                    text: s.settings.profile?.username ?? '',
                  ),
                  optionsBuilder: (v) => known.where(
                    (n) => n.toLowerCase().contains(v.text.toLowerCase()),
                  ),
                  onSelected: (_) => _load(),
                  fieldViewBuilder: (context, controller, focus, submit) {
                    _name = controller;
                    return TextField(
                      controller: controller,
                      focusNode: focus,
                      autocorrect: false,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _load(),
                      decoration: InputDecoration(
                        hintText: '${site.label} username',
                        prefixIcon: const Icon(Icons.person_outline, size: 18),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: s.browser.loading ? null : _load,
                icon: s.browser.loading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download, size: 18),
                label: const Text('Load games'),
              ),
              const SizedBox(width: 12),
              // Section tabs scroll sideways rather than overflow on narrow windows.
              Expanded(
                flex: 3,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: Row(
                    children: [
                      for (final (i, name) in widget.sections.indexed)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: s.tab.value == i
                                  ? theme.colorScheme.primary
                                  : p.muted,
                              backgroundColor: s.tab.value == i
                                  ? theme.colorScheme.primary.withValues(
                                      alpha: 0.12,
                                    )
                                  : null,
                            ),
                            onPressed: () => s.tab.value = i,
                            child: Text(name),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
