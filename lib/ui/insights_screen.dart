import 'package:flutter/material.dart';

import '../analysis/insights.dart';
import '../analysis/review.dart';
import '../chess/chess_game.dart';
import 'services.dart';
import 'theme.dart';

class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

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
        final ins = Insights.compute(
          s.store.games,
          s.settings.thresholds,
          options: s.settings.classOptions,
          book: s.analysis.book,
        );
        final theme = Theme.of(context);
        final muted = theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        );
        return Scaffold(
          appBar: AppBar(title: const Text('Insights')),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (ins.reviewedGames == 0)
                _EmptyInsights(
                  hasGames: s.store.games.isNotEmpty,
                  hasNames: s.settings.usernames.isNotEmpty,
                )
              else ...[
                _Overview(ins),
                const SizedBox(height: 12),
                _Section('Progress', [
                  if (ins.trend.length >= 2)
                    SizedBox(
                      height: 70,
                      child: CustomPaint(
                        painter: _Sparkline(
                          ins.trend.map((t) => t.$2).toList(),
                          theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Builder(
                    builder: (_) {
                      final (recent, prev) = ins.recentVsPrevious;
                      if (recent == null || prev == null) {
                        return Text(
                          'Review more than 10 games to compare recent and earlier accuracy.',
                          style: muted,
                        );
                      }
                      final diff = recent - prev;
                      return Text(
                        'Last 10 games: ${recent.toStringAsFixed(1)}% · previous 10: ${prev.toStringAsFixed(1)}% '
                        '(${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)})',
                      );
                    },
                  ),
                ]),
                const SizedBox(height: 12),
                _Section('Accuracy by phase', [
                  for (final p in Phase.values)
                    _Row(
                      p.name[0].toUpperCase() + p.name.substring(1),
                      ins.phaseAccuracy[p] == null
                          ? '–'
                          : '${ins.phaseAccuracy[p]!.toStringAsFixed(1)}%',
                      '${ins.phaseMoves[p]} moves',
                    ),
                  Text(
                    'Phases are estimated: opening = first 10 moves, endgame = at most 6 pieces besides kings and pawns.',
                    style: muted,
                  ),
                ]),
                const SizedBox(height: 12),
                _Section('Learning points across games', [
                  Text(
                    'From ${ins.reviewedGames} reviewed game(s). Marked '
                    'recurring only when seen in $minGamesForPattern+ '
                    'games out of $minGamesForInsights+ reviewed.',
                    style: muted,
                  ),
                  if (ins.lessons.isEmpty) Text('None yet.', style: muted),
                  for (final e
                      in (ins.lessons.entries.toList()
                        ..sort((a, b) => b.value.$2.compareTo(a.value.$2))))
                    _Row(
                      e.key.label,
                      ins.isRecurring(e.key) ? 'Recurring' : '',
                      '${e.value.$1}× in ${e.value.$2} game(s)',
                    ),
                ]),
                const SizedBox(height: 12),
                _Section('Possible weaknesses', [
                  Text(
                    ins.reviewedGames < minGamesForInsights
                        ? 'Patterns need at least $minGamesForInsights reviewed games; you have ${ins.reviewedGames}.'
                        : ins.reviewedGames < 10
                        ? 'Based on ${ins.reviewedGames} games — treat these as tentative.'
                        : 'Based on ${ins.reviewedGames} reviewed games.',
                    style: muted,
                  ),
                  const SizedBox(height: 6),
                  for (final w
                      in [...ins.weaknesses]..sort(
                        (a, b) => b
                            .evidence(ins.reviewedGames)
                            .index
                            .compareTo(a.evidence(ins.reviewedGames).index),
                      ))
                    _WeaknessTile(w, ins.reviewedGames),
                ]),
                if (ins.openingProblems.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _Section('Openings with repeated early errors', [
                    for (final o in ins.openingProblems)
                      _Row(
                        o.opening,
                        '${o.errors} errors',
                        'in ${o.games} games',
                      ),
                  ]),
                ],
                const SizedBox(height: 12),
                _Section('Missed tactics to review', [
                  if (ins.missedTactics.isEmpty)
                    Text('None found in your reviewed games.', style: muted),
                  for (final m in ins.missedTactics.take(20))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: Icon(
                        Icons.search,
                        color: classColor(m.review.cls),
                      ),
                      title: Text(
                        '${m.game.title} · move ${m.game.game.positionAt(m.review.ply).fullmoves}',
                      ),
                      subtitle: Text(
                        'Find the better move (${m.review.mover.label} to play)',
                      ),
                      onTap: () => s.open(m.game, atPly: m.review.ply),
                    ),
                ]),
              ],
              const SizedBox(height: 12),
              _Section('Positions to revisit', [
                if (s.store.positions.isEmpty)
                  Text(
                    'Pin positions from the Analyze screen menu or from a reviewed mistake.',
                    style: muted,
                  ),
                for (final p in s.store.positions.reversed)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.push_pin_outlined),
                    title: Text(p.note.isEmpty ? 'Position' : p.note),
                    subtitle: Text(
                      p.fen,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () {
                      final g = p.gameId == null
                          ? null
                          : s.store.byId(p.gameId!);
                      if (g != null &&
                          p.ply != null &&
                          p.ply! <= g.game.length &&
                          g.game.positionAt(p.ply!).fen == p.fen) {
                        s.open(g, atPly: p.ply!);
                      } else {
                        final game = ChessGame.fromFen(p.fen);
                        s.analysis.load(game, orientation: game.initial.turn);
                        s.tab.value = 0;
                      }
                    },
                    trailing: IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.close),
                      onPressed: () => s.store.removePosition(p.id),
                    ),
                  ),
              ]),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyInsights extends StatelessWidget {
  const _EmptyInsights({required this.hasGames, required this.hasNames});
  final bool hasGames, hasNames;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('No reviewed games yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'Insights are built only from your own moves in fully reviewed games. To get started:\n'
              '1. Import your games (Games tab).\n'
              '2. Tell Ply which side you played — add your usernames in Settings, or use "Edit details" on a game.\n'
              '3. Open a game and tap "Review game".',
            ),
            if (hasGames && !hasNames) ...[
              const SizedBox(height: 8),
              Text(
                'Tip: add your usernames in Settings so Ply can detect your colour automatically.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview(this.ins);
  final Insights ins;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = ins.reviewedGames;
    String perGame(MoveClass c) => (ins.count(c) / n).toStringAsFixed(1);
    Widget stat(String value, String label, [Color? color]) => Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(
          children: [
            Row(
              children: [
                stat('$n', 'reviewed games'),
                stat(
                  ins.averageAccuracy == null
                      ? '–'
                      : '${ins.averageAccuracy!.toStringAsFixed(1)}%',
                  'avg accuracy',
                ),
                stat(
                  '${ins.results['win']}/${ins.results['draw']}/${ins.results['loss']}',
                  'W / D / L',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                stat(
                  perGame(MoveClass.inaccuracy),
                  'inaccuracies\nper game',
                  classColor(MoveClass.inaccuracy),
                ),
                stat(
                  perGame(MoveClass.mistake),
                  'mistakes\nper game',
                  classColor(MoveClass.mistake),
                ),
                stat(
                  perGame(MoveClass.blunder),
                  'blunders\nper game',
                  classColor(MoveClass.blunder),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WeaknessTile extends StatelessWidget {
  const _WeaknessTile(this.w, this.games);
  final WeaknessStat w;
  final int games;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ev = w.evidence(games);
    final color = switch (ev) {
      Evidence.recurring => classColor(MoveClass.mistake),
      Evidence.normal => theme.colorScheme.onSurfaceVariant,
      Evidence.none => classColor(MoveClass.best),
      Evidence.insufficient => theme.colorScheme.outline,
    };
    final rate = (w.rate * 100).toStringAsFixed(1),
        base = (w.baselineRate * 100).toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(w.title, style: theme.textTheme.titleSmall)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  ev.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          Text(w.description, style: theme.textTheme.bodySmall),
          if (ev != Evidence.insufficient)
            Text(
              '${w.occurrences} of ${w.sample} moves ($rate%) in ${w.games} games · your general rate $base%',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            Text(
              '${w.sample} relevant moves so far (need $minSampleMoves).',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row(this.a, this.b, this.c);
  final String a, b, c;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(a)),
        Text(b, style: const TextStyle(fontWeight: FontWeight.w700)),
        SizedBox(
          width: 90,
          child: Text(
            c,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    ),
  );
}

class _Sparkline extends CustomPainter {
  _Sparkline(this.values, this.color);
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final lo = values.reduce((a, b) => a < b ? a : b) - 2;
    final hi = values.reduce((a, b) => a > b ? a : b) + 2;
    double x(int i) => size.width * i / (values.length - 1);
    double y(double v) => size.height * (1 - (v - lo) / (hi - lo));
    final p = Path()..moveTo(0, y(values.first));
    for (var i = 1; i < values.length; i++) {
      p.lineTo(x(i), y(values[i]));
    }
    canvas.drawPath(
      p,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
    for (var i = 0; i < values.length; i++) {
      canvas.drawCircle(
        Offset(x(i), y(values[i])),
        2.5,
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_Sparkline old) => old.values != values;
}
