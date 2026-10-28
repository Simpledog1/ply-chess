import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/material.dart';

import '../analysis/review.dart';
import '../online/online_games.dart';
import '../storage/game_store.dart';
import 'services.dart';
import 'theme.dart';

/// "3+2" style clock from a PGN TimeControl ("180+2", "1/86400" daily).
String formatClock(String? tc) {
  if (tc == null || tc == '-' || tc == '?') return '';
  if (tc.startsWith('1/')) {
    final days = (int.tryParse(tc.substring(2)) ?? 86400) ~/ 86400;
    return '$days day${days == 1 ? '' : 's'}';
  }
  final m = RegExp(r'^(\d+)(?:\+(\d+))?$').firstMatch(tc);
  if (m == null) return tc;
  final base = int.parse(m[1]!);
  final mins = base % 60 == 0
      ? '${base ~/ 60}'
      : (base / 60).toStringAsFixed(1);
  return '$mins+${m[2] ?? '0'}';
}

String _ago(DateTime? t) {
  if (t == null) return '';
  final d = DateTime.now().difference(t.toLocal());
  if (d.inMinutes < 60) return '${d.inMinutes.clamp(1, 59)} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inDays < 7) return '${d.inDays} d ago';
  final l = t.toLocal();
  return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
}

/// Recent games of the selected profile, with "Load more" and error states.
class OnlineGameList extends StatelessWidget {
  const OnlineGameList({super.key, this.onOpened, this.controller});

  /// Called after a game was opened (e.g. to close a sheet).
  final VoidCallback? onOpened;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([s.browser, s.analysis, s.store]),
      builder: (context, _) {
        final b = s.browser;
        final feed = b.feed;
        final theme = Theme.of(context);
        final p = PlyPalette.of(context);
        final muted = theme.textTheme.bodySmall?.copyWith(color: p.muted);

        if (feed == null && !b.loading) {
          return _Message(
            icon: Icons.person_search_outlined,
            title: b.error ?? 'Load your games',
            body: b.error != null
                ? 'You can still paste a PGN or open a PGN file.'
                : 'Pick Lichess or Chess.com, enter a username and press '
                      'Enter. Only public games are available.',
            error: b.error != null,
          );
        }
        final games = feed?.games ?? const <OnlineGame>[];
        final currentLink =
            s.analysis.game.headers['Link'] ?? s.analysis.game.headers['Site'];
        final items = <Widget>[
          if (feed != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Text(
                '${feed.displayName ?? feed.username} on ${feed.site.label}'
                ' · ${games.length} game${games.length == 1 ? '' : 's'}',
                style: muted,
              ),
            ),
          for (final g in games)
            _GameTile(
              g,
              me: feed!.username,
              selected: currentLink != null && g.id == currentLink,
              onTap: () {
                s.analysis.openOnline(g, profile: feed.key);
                s.tab.value = 0;
                onOpened?.call();
              },
            ),
          if (b.error != null && feed != null)
            _Message(
              icon: Icons.cloud_off,
              title: b.error!,
              body: games.isEmpty
                  ? 'No games were loaded. You can paste a PGN or open a PGN '
                        'file instead.'
                  : 'The games above are still available.',
              error: true,
              action: TextButton(
                onPressed: games.isEmpty
                    ? () => b.open(feed.site, feed.username)
                    : b.more,
                child: const Text('Try again'),
              ),
            )
          else if (b.loading)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  Text('Loading games…', style: muted),
                  TextButton(onPressed: b.cancel, child: const Text('Cancel')),
                ],
              ),
            )
          else if (feed != null && games.isEmpty)
            const _Message(
              icon: Icons.inbox_outlined,
              title: 'No public standard games found',
              body:
                  'This account has no public standard-chess games Ply can '
                  'read. Variants are skipped. You can paste a PGN instead.',
            )
          else if (feed != null && feed.hasMore)
            Padding(
              padding: const EdgeInsets.all(8),
              child: OutlinedButton(
                onPressed: b.more,
                child: Text('Load ${s.settings.pageSize} more'),
              ),
            )
          else if (games.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'No older games',
                textAlign: TextAlign.center,
                style: muted,
              ),
            ),
        ];
        return ListView(controller: controller, children: items);
      },
    );
  }
}

class _GameTile extends StatelessWidget {
  const _GameTile(
    this.g, {
    required this.me,
    required this.selected,
    required this.onTap,
  });
  final OnlineGame g;
  final String me;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = PlyPalette.of(context);
    final h = g.headers;
    final mine = GameStore.detectColor(g.game, [me]);
    final opp = mine == Side.black ? 'White' : 'Black';
    final r = g.game.result;
    final res = mine == null || r == '*'
        ? '–'
        : r == '1/2-1/2'
        ? 'D'
        : (r == '1-0') == (mine == Side.white)
        ? 'W'
        : 'L';
    final color = switch (res) {
      'W' => classColor(MoveClass.best),
      'L' => classColor(MoveClass.blunder),
      _ => p.muted,
    };
    final elo = h['${opp}Elo'];
    final opening = h['Opening'];
    final details = [
      formatClock(h['TimeControl']),
      _ago(g.playedAt),
      '${(g.game.length + 1) ~/ 2} moves',
    ].where((x) => x.isNotEmpty).join(' · ');
    return Material(
      color: selected
          ? theme.colorScheme.primary.withValues(alpha: 0.18)
          : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  res,
                  style: TextStyle(color: color, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (mine != null)
                          Container(
                            width: 9,
                            height: 9,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: mine == Side.white
                                  ? Colors.white
                                  : Colors.black,
                              border: Border.all(color: p.muted),
                              shape: BoxShape.circle,
                            ),
                          ),
                        Flexible(
                          child: Text(
                            'vs ${h[opp] ?? '?'}${elo == null || elo == '?' ? '' : ' ($elo)'}',
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      details,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: p.muted,
                      ),
                    ),
                    if (opening != null && opening != '?')
                      Text(
                        opening,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: p.muted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.error = false,
    this.action,
  });
  final IconData icon;
  final String title;
  final String body;
  final bool error;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = PlyPalette.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 36,
            color: error ? theme.colorScheme.error : p.muted,
          ),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            body,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: p.muted),
          ),
          ?action,
        ],
      ),
    );
  }
}
