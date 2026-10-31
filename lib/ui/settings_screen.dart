import 'dart:io';

import 'package:dartchess/dartchess.dart' show Chess, Side;
import 'package:flutter/material.dart';

import '../analysis/review.dart';
import 'games_screen.dart' show HistoryStatus, profileLabel;
import 'import_export.dart' show snack;
import 'services.dart';

const appVersion = '1.3.1';
const tagline = 'Every move teaches.';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final st = s.settings;
    return ListenableBuilder(
      listenable: Listenable.merge([st, s.engine]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final t = st.thresholds;
        final cores = Platform.numberOfProcessors;
        Widget header(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(
            text,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        );
        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: ListView(
            children: [
              header('Appearance'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('System'),
                    ),
                    ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                    ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                  ],
                  selected: {st.themeMode},
                  onSelectionChanged: (v) =>
                      st.update((x) => x.themeMode = v.first),
                ),
              ),
              SwitchListTile(
                title: const Text('Board coordinates'),
                value: st.showCoordinates,
                onChanged: (v) => st.update((x) => x.showCoordinates = v),
              ),
              header('Profiles & privacy'),
              const HistoryStatus(),
              const _ProfilesSection(),
              header('You'),
              ListTile(
                title: const Text('Your usernames'),
                subtitle: Text(
                  st.usernames.isEmpty
                      ? 'Extra names to detect your side in pasted PGNs '
                            '(profile names are used automatically)'
                      : st.usernames.join(', '),
                ),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _editUsernames(context),
              ),
              header('Engine'),
              _Stepper(
                title: 'Threads',
                value: st.threads,
                min: 1,
                max: cores.clamp(1, 8),
                onChanged: (v) async {
                  await st.update((x) => x.threads = v);
                  await s.engine.configure(threads: v, hashMb: st.hashMb);
                },
              ),
              ListTile(
                title: const Text('Hash memory'),
                trailing: DropdownButton<int>(
                  value: st.hashMb,
                  items: [
                    for (final m in const [16, 32, 64, 128, 256])
                      DropdownMenuItem(value: m, child: Text('$m MB')),
                  ],
                  onChanged: (v) async {
                    if (v == null) return;
                    await st.update((x) => x.hashMb = v);
                    await s.engine.configure(threads: st.threads, hashMb: v);
                  },
                ),
              ),
              const ListTile(
                title: Text('Depth, lines, time limit and arrows'),
                subtitle: Text('Analyze tab → gear icon (Analysis Settings)'),
              ),
              const _EngineCheck(),
              header('Move classification'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'A move is judged by how many percentage points it drops the mover\'s winning chances '
                  '(Stockfish evaluation converted with the Lichess formula). Defaults match Lichess.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              _ThresholdSlider(
                'Inaccuracy from',
                t.inaccuracy,
                2,
                15,
                (v) => st.update(
                  (x) => x.thresholds = Thresholds(
                    inaccuracy: v,
                    mistake: t.mistake < v ? v : t.mistake,
                    blunder: t.blunder < v ? v : t.blunder,
                  ),
                ),
              ),
              _ThresholdSlider(
                'Mistake from',
                t.mistake,
                5,
                25,
                (v) => st.update(
                  (x) => x.thresholds = Thresholds(
                    inaccuracy: t.inaccuracy > v ? v : t.inaccuracy,
                    mistake: v,
                    blunder: t.blunder < v ? v : t.blunder,
                  ),
                ),
              ),
              _ThresholdSlider(
                'Blunder from',
                t.blunder,
                8,
                40,
                (v) => st.update(
                  (x) => x.thresholds = Thresholds(
                    inaccuracy: t.inaccuracy > v ? v : t.inaccuracy,
                    mistake: t.mistake > v ? v : t.mistake,
                    blunder: v,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: TextButton(
                    onPressed: () =>
                        st.update((x) => x.thresholds = const Thresholds()),
                    child: const Text('Reset to defaults (5 / 10 / 15)'),
                  ),
                ),
              ),
              header('About'),
              ListTile(
                title: const Text('Ply $appVersion'),
                subtitle: const Text(
                  '$tagline\nPersonal chess analysis. Works offline; your games stay on this device.',
                ),
                isThreeLine: true,
              ),
              ListTile(
                title: const Text('Licenses and credits'),
                subtitle: const Text(
                  'Stockfish (GPLv3), Cburnett pieces (GPLv2+), dartchess (GPLv3) and others',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'Ply',
                  applicationVersion: appVersion,
                  applicationLegalese:
                      'Ply source code: MIT License. The app bundles GPL-licensed components '
                      '(Stockfish, dartchess, Cburnett pieces), so the distributed app as a whole is '
                      'covered by GPLv3. Source: github.com/Simpledog1/ply-chess',
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editUsernames(BuildContext context) async {
    final st = Services.of(context).settings;
    final c = TextEditingController(text: st.usernames.join(', '));
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your usernames'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. myname, myname_blitz',
            helperText: 'Comma separated',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (v == null) return;
    await st.update(
      (x) => x.usernames = v
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  final String title;
  final int value, min, max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(title),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(width: 28, child: Text('$value', textAlign: TextAlign.center)),
        IconButton(
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add),
        ),
      ],
    ),
  );
}

class _ThresholdSlider extends StatelessWidget {
  const _ThresholdSlider(
    this.label,
    this.value,
    this.min,
    this.max,
    this.onChanged,
  );
  final String label;
  final double value, min, max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      children: [
        SizedBox(width: 120, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: (max - min).round(),
            label: '${value.round()}',
            onChanged: (v) => onChanged(v.roundToDouble()),
          ),
        ),
        SizedBox(width: 36, child: Text('${value.round()}%')),
      ],
    ),
  );
}

/// Starts the bundled engine and runs a short search, so it can be verified
/// on a real device.
class _EngineCheck extends StatefulWidget {
  const _EngineCheck();

  @override
  State<_EngineCheck> createState() => _EngineCheckState();
}

class _EngineCheckState extends State<_EngineCheck> {
  String? _result;
  bool _running = false;

  Future<void> _run() async {
    final s = Services.of(context);
    setState(() {
      _running = true;
      _result = null;
    });
    final sw = Stopwatch()..start();
    try {
      final e = await s.engine.engine;
      final r = await e.search(
        fen: Chess.initial.fen,
        turn: Side.white,
        depth: 18,
      );
      final b = r.best!;
      _result =
          '${e.name} OK · depth ${b.depth} · ${b.eval.label} · best ${r.bestMove}'
          '${b.nps != null ? ' · ${(b.nps! / 1000).round()} kN/s' : ''} · ${sw.elapsedMilliseconds} ms';
    } catch (err) {
      _result = 'Engine check failed: ${s.engine.error ?? err}';
    }
    if (mounted) setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) => ListTile(
    title: const Text('Check engine'),
    subtitle: Text(
      _result ?? 'Start Stockfish and search the starting position to depth 18',
    ),
    trailing: _running
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.play_circle_outline),
    onTap: _running ? null : _run,
  );
}

/// Remembered profiles with their saved data, and delete buttons.
class _ProfilesSection extends StatelessWidget {
  const _ProfilesSection();

  Future<bool> _confirm(
    BuildContext context,
    String title,
    String body,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final st = s.settings;
    return ListenableBuilder(
      listenable: s.store,
      builder: (context, _) {
        final counts = s.store.countsByProfile();
        final theme = Theme.of(context);
        final muted = theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final p in st.profiles)
              ListTile(
                leading: Icon(
                  p.key == st.currentProfile
                      ? Icons.person
                      : Icons.person_outline,
                ),
                title: Text(profileLabel(p.key)),
                subtitle: Text(
                  '${counts[p.key] ?? 0} saved game(s) · last used '
                  '${p.lastUsed.toLocal().toString().substring(0, 16)}',
                ),
                trailing: IconButton(
                  tooltip: 'Forget profile and delete its data',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    if (!await _confirm(
                      context,
                      'Delete ${profileLabel(p.key)}?',
                      'Forgets this username and deletes its '
                          '${counts[p.key] ?? 0} saved game(s) and analysis '
                          'from this PC. Nothing on ${p.site.label} changes.',
                    )) {
                      return;
                    }
                    await s.store.deleteProfile(p.key);
                    await st.forgetProfile(p.key);
                    s.browser.forget(p.key);
                    if (context.mounted) snack(context, 'Profile deleted');
                  },
                ),
              ),
            ListTile(
              title: const Text('Games per page'),
              subtitle: const Text('How many recent games to load at a time'),
              trailing: DropdownButton<int>(
                value: st.pageSize,
                items: [
                  for (final n in const [10, 20, 30, 50])
                    DropdownMenuItem(value: n, child: Text('$n')),
                ],
                onChanged: (v) {
                  if (v != null) st.update((x) => x.pageSize = v);
                },
              ),
            ),
            ListTile(
              title: const Text('Delete all local history'),
              subtitle: Text(
                '${s.store.games.length} saved game(s), '
                '${s.store.positions.length} pinned position(s)',
              ),
              trailing: const Icon(Icons.delete_forever_outlined),
              enabled: s.store.games.isNotEmpty || s.store.positions.isNotEmpty,
              onTap: () async {
                if (!await _confirm(
                  context,
                  'Delete all local history?',
                  'Removes every saved game, analysis and pinned position '
                      'from this PC. Profiles and settings are kept.',
                )) {
                  return;
                }
                await s.store.deleteAll();
                if (context.mounted) snack(context, 'Local history deleted');
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'Data folder: ${st.dir.path}\n'
                'A username only tells Ply whose public games to load; it '
                'does not prove the account is yours. Ply never asks for '
                'passwords or tokens, sends nothing but the username to '
                'Lichess or Chess.com, and is not affiliated with either.',
                style: muted,
              ),
            ),
          ],
        );
      },
    );
  }
}
