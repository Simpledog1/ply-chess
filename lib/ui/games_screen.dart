import 'package:dartchess/dartchess.dart' show Piece, Role, Side;
import 'package:flutter/material.dart';

import '../analysis/review.dart';
import '../storage/game_store.dart';
import 'board/chess_board.dart';
import 'import_export.dart';
import 'services.dart';

class GamesScreen extends StatefulWidget {
  const GamesScreen({super.key});

  @override
  State<GamesScreen> createState() => _GamesScreenState();
}

class _GamesScreenState extends State<GamesScreen> {
  final _results = <String>{};
  Side? _color;
  String? _speed;
  String _query = '';

  bool _matches(SavedGame g) {
    if (_results.isNotEmpty && !_results.contains(g.myResult)) return false;
    if (_color != null && g.myColor != _color) return false;
    if (_speed != null && g.speed != _speed) return false;
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      final hay = [
        g.title,
        g.headers['Event'],
        g.headers['Opening'],
        g.headers['Site'],
      ].whereType<String>().join(' ').toLowerCase();
      if (!hay.contains(q)) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        s.store,
        s.settings,
        s.analysis.bookLoaded,
      ]),
      builder: (context, _) {
        final all = s.store.games.toList()
          ..sort((a, b) => b.date.compareTo(a.date));
        final shown = all.where(_matches).toList();
        final speeds =
            all.map((g) => g.speed).whereType<String>().toSet().toList()
              ..sort();
        final theme = Theme.of(context);
        return Scaffold(
          appBar: AppBar(title: const Text('Games')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => showImportSheet(context, saveSingle: true),
            icon: const Icon(Icons.add),
            label: const Text('Import'),
          ),
          body: all.isEmpty
              ? _Empty(
                  onImport: () => showImportSheet(context, saveSingle: true),
                )
              : Column(
                  children: [
                    if (s.store.loadError != null)
                      MaterialBanner(
                        content: Text(s.store.loadError!),
                        actions: const [SizedBox()],
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                      child: TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search players, event, opening',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => setState(() => _query = v.trim()),
                      ),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          for (final r in const ['win', 'loss', 'draw'])
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: FilterChip(
                                label: Text(
                                  '${r[0].toUpperCase()}${r.substring(1)}',
                                ),
                                selected: _results.contains(r),
                                onSelected: (v) => setState(
                                  () =>
                                      v ? _results.add(r) : _results.remove(r),
                                ),
                              ),
                            ),
                          for (final c in Side.values)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: FilterChip(
                                label: Text(
                                  c == Side.white ? 'As White' : 'As Black',
                                ),
                                selected: _color == c,
                                onSelected: (v) =>
                                    setState(() => _color = v ? c : null),
                              ),
                            ),
                          for (final sp in speeds)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: FilterChip(
                                label: Text(sp),
                                selected: _speed == sp,
                                onSelected: (v) =>
                                    setState(() => _speed = v ? sp : null),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_results.isNotEmpty || _color != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Result and colour filters only match games where your colour is known.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    Expanded(
                      child: shown.isEmpty
                          ? const Center(
                              child: Text('No games match these filters'),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.only(bottom: 88),
                              itemCount: shown.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1, indent: 16),
                              itemBuilder: (context, i) => _GameTile(shown[i]),
                            ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onImport});
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: 0.5,
              child: PieceImage(
                const Piece(color: Side.white, role: Role.knight),
                size: 72,
              ),
            ),
            const SizedBox(height: 12),
            Text('No saved games yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Import a PGN file or paste a game. Reviewed games feed your Insights.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.add),
              label: const Text('Import games'),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameTile extends StatelessWidget {
  const _GameTile(this.g);
  final SavedGame g;

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final theme = Theme.of(context);
    final r = g.review;
    final reviewed = r != null && r.matches(g.game);
    double? acc;
    if (reviewed && g.myColor != null) {
      acc = summarize(
        reviewMoves(
          g.game,
          r,
          s.settings.thresholds,
          options: s.settings.classOptions,
          book: s.analysis.book,
        ),
        g.myColor!,
      ).accuracy;
    }
    final res = g.myResult;
    final resColor = switch (res) {
      'win' => const Color(0xFF2E9E6A),
      'loss' => theme.colorScheme.error,
      _ => theme.colorScheme.onSurfaceVariant,
    };
    final d = g.date;
    final subtitle = [
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
      ?g.speed,
      g.game.result,
      '${(g.game.length + 1) ~/ 2} moves',
      if (g.myColor != null)
        'you: ${g.myColor == Side.white ? 'White' : 'Black'}',
    ].join(' · ');
    return ListTile(
      onTap: () => s.open(g),
      leading: CircleAvatar(
        backgroundColor: resColor.withValues(alpha: 0.15),
        child: Text(switch (res) {
          'win' => 'W',
          'loss' => 'L',
          'draw' => 'D',
          _ => '–',
        }, style: TextStyle(color: resColor, fontWeight: FontWeight.w700)),
      ),
      title: Text(g.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 2),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (acc != null)
            Text(
              '${acc.toStringAsFixed(0)}%',
              style: theme.textTheme.labelLarge,
            )
          else if (r != null && !r.complete)
            const Tooltip(
              message: 'Partial review',
              child: Icon(Icons.hourglass_bottom, size: 18),
            )
          else if (reviewed)
            const Tooltip(
              message: 'Reviewed',
              child: Icon(Icons.check_circle_outline, size: 18),
            ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'edit':
                  await editGameDetails(context, g);
                case 'copy':
                  await copyText(context, g.pgn, 'PGN');
                case 'export':
                  await savePgnFile(context, g.pgn, g.title);
                case 'delete':
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete game?'),
                      content: Text(
                        '"${g.title}" and its review will be removed from this device.',
                      ),
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
                  );
                  if (ok == true) {
                    await s.store.delete(g.id);
                    if (s.analysis.savedId == g.id) s.analysis.savedId = null;
                  }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit details')),
              PopupMenuItem(value: 'copy', child: Text('Copy PGN')),
              PopupMenuItem(value: 'export', child: Text('Export PGN file')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Edits PGN headers and which side the user played.
Future<void> editGameDetails(BuildContext context, SavedGame g) async {
  final s = Services.of(context);
  const fields = [
    'White',
    'Black',
    'WhiteElo',
    'BlackElo',
    'Event',
    'Site',
    'Date',
    'TimeControl',
    'Opening',
  ];
  final ctrls = {
    for (final f in fields)
      f: TextEditingController(
        text: g.headers[f] == '?' ? '' : g.headers[f] ?? '',
      ),
  };
  var result = g.game.result;
  Side? color = g.myColor;
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('Game details'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final f in fields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      controller: ctrls[f],
                      decoration: InputDecoration(
                        labelText: f == 'Date' ? 'Date (YYYY.MM.DD)' : f,
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                DropdownButtonFormField<String>(
                  initialValue: result,
                  decoration: const InputDecoration(
                    labelText: 'Result',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: '1-0',
                      child: Text('1-0 (White won)'),
                    ),
                    DropdownMenuItem(
                      value: '0-1',
                      child: Text('0-1 (Black won)'),
                    ),
                    DropdownMenuItem(
                      value: '1/2-1/2',
                      child: Text('½-½ (draw)'),
                    ),
                    DropdownMenuItem(value: '*', child: Text('* (unknown)')),
                  ],
                  onChanged: (v) => set(() => result = v ?? result),
                ),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('I played'),
                ),
                const SizedBox(height: 4),
                SegmentedButton<Side?>(
                  segments: const [
                    ButtonSegment(value: Side.white, label: Text('White')),
                    ButtonSegment(value: Side.black, label: Text('Black')),
                    ButtonSegment(value: null, label: Text('Not me')),
                  ],
                  selected: {color},
                  onSelectionChanged: (v) => set(() => color = v.first),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  if (saved != true) return;
  final h = {...g.headers};
  for (final f in fields) {
    final v = ctrls[f]!.text.trim();
    if (v.isEmpty) {
      if (const ['White', 'Black', 'Event', 'Site', 'Date'].contains(f)) {
        h[f] = f == 'Date' ? '????.??.??' : '?';
      } else {
        h.remove(f);
      }
    } else {
      h[f] = v;
    }
  }
  h['Result'] = result;
  final updated = g.copyWith(
    pgn: g.game.withHeaders(h).toPgn(),
    myColor: color,
    clearMyColor: color == null,
  );
  await s.store.upsert(updated);
  if (s.analysis.savedId == g.id) {
    final a = s.analysis;
    a.load(
      updated.game,
      from: updated,
      atPly: a.ply,
      orientation: a.orientation,
    );
  }
}
