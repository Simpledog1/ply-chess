import 'package:flutter/material.dart';

import '../online/online_games.dart';
import '../storage/settings.dart';
import 'services.dart';
import 'theme.dart';

/// Load a profile's recent games: site, username (with the usernames used
/// before as suggestions) and the Load games button.
class GameLoader extends StatefulWidget {
  const GameLoader({super.key});

  @override
  State<GameLoader> createState() => _GameLoaderState();
}

class _GameLoaderState extends State<GameLoader> {
  TextEditingController? _name;

  ChessSite _site(Settings s) => s.loadSource.site ?? ChessSite.lichess;

  Future<void> _load() async {
    final s = Services.of(context);
    final name = _name?.text.trim() ?? '';
    if (name.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    await s.browser.open(_site(s.settings), name);
  }

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final p = PlyPalette.of(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([s.settings, s.browser]),
      builder: (context, _) {
        final site = _site(s.settings);
        final known = [
          for (final pr in s.settings.profiles)
            if (pr.site == site) pr.username,
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Load games from',
                    style: theme.textTheme.bodyMedium?.copyWith(color: p.muted),
                  ),
                ),
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
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
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
                          prefixIcon: const Icon(
                            Icons.person_outline,
                            size: 18,
                          ),
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
                      : const Icon(Icons.search, size: 18),
                  label: const Text('Load games'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
