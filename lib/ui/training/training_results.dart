part of 'training_screen.dart';

/// After a cycle (not the last): its results and the start of the next.
class _CycleResults extends StatelessWidget {
  const _CycleResults(this.c, this.cycle);
  final TrainingCollection c;
  final TrainingCycle cycle;

  @override
  Widget build(BuildContext context) {
    final t = _watch(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
          accent: classColorGood,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cycle ${cycle.number} of ${c.plannedCycles} complete',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Next: the same ${c.size} puzzles again, in a new order. '
                'Recognising them faster and without mistakes is the point.',
              ),
              const SizedBox(height: 12),
              _SummaryStats(AttemptSummary(cycle.attempts)),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(220, 48)),
                onPressed: () async {
                  await t.startNextCycle();
                  t.nextInCycle();
                },
                icon: const Icon(Icons.play_arrow),
                label: Text('Start cycle ${cycle.number + 1}'),
              ),
            ],
          ),
        ),
        _Card(child: _CollectionReport(c)),
      ],
    );
  }
}

/// After the last cycle: the three cycles compared, what improved, what
/// still needs work, and how the next collection will change.
class _CollectionResults extends StatelessWidget {
  const _CollectionResults(this.c, {required this.onPlan});
  final TrainingCollection c;
  final VoidCallback onPlan;

  @override
  Widget build(BuildContext context) {
    final t = _watch(context);
    final theme = Theme.of(context);
    final sums = [for (final cy in c.cycles) AttemptSummary(cy.attempts)];
    final first = sums.first, last = sums.last;
    final accGain = (last.firstTryRate ?? 0) - (first.firstTryRate ?? 0);
    final t1 = first.averageTime, t3 = last.averageTime;
    final persistent = [
      for (final s in themeStats(c.cycles.last.attempts).values)
        if (s.attempts >= 5 && s.firstTryRate < 0.7) s,
    ]..sort((a, b) => a.firstTryRate.compareTo(b.firstTryRate));
    final adj = t.nextAdjustment;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
          accent: classColorGood,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Collection ${c.number} complete',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'First-try accuracy went from ${_pct(first.firstTryRate)} to '
                '${_pct(last.firstTryRate)} '
                '(${accGain >= 0 ? '+' : ''}${accGain.round()} points)'
                '${t1 != null && t3 != null ? ', and the average time from ${_time(t1)} to ${_time(t3)}' : ''}. '
                '${masteredCount(c)} of ${c.size} puzzles are provisionally '
                'mastered.',
              ),
              const SizedBox(height: 6),
              Text(
                persistent.isEmpty
                    ? 'No theme stayed clearly weak in the last cycle.'
                    : 'Still hard in the last cycle: '
                          '${persistent.take(3).map((s) => '${themeName(s.theme)} (${(s.firstTryRate * 100).round()}%)').join(', ')}.',
              ),
              const SizedBox(height: 6),
              Text('Next collection: ${adj.reason}'),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(220, 48)),
                onPressed: onPlan,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Plan the next collection'),
              ),
            ],
          ),
        ),
        _Card(child: _CollectionReport(c)),
        const _History(),
      ],
    );
  }
}

class _SummaryStats extends StatelessWidget {
  const _SummaryStats(this.s);
  final AttemptSummary s;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      _Stat('First-try accuracy', _pct(s.firstTryRate)),
      _Stat('Solved in the end', _pct(s.solvedRate)),
      _Stat('Average time', _time(s.averageTime)),
      _Stat('Wrong moves', '${s.wrongMoves}'),
      _Stat('Hints used', '${s.hinted}'),
      if (s.skipped > 0) _Stat('Skipped', '${s.skipped}'),
    ],
  );
}

/// Cycle-by-cycle comparison and per-theme results of a collection.
class _CollectionReport extends StatelessWidget {
  const _CollectionReport(this.c);
  final TrainingCollection c;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = PlyPalette.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: p.muted);
    final cycles = c.cycles.where((cy) => cy.attempts.isNotEmpty).toList();
    final cycleNo = <Attempt, int>{
      for (final cy in c.cycles)
        for (final a in cy.attempts) a: cy.number,
    };
    final themes =
        themeStats(
            cycleNo.keys,
            cycleOf: (a) => cycleNo[a]!,
          ).values.where((s) => s.attempts >= 3).toList()
          ..sort((a, b) => b.attempts.compareTo(a.attempts));
    TableRow row(List<String> cells, {bool head = false}) => TableRow(
      children: [
        for (final (i, x) in cells.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              x,
              textAlign: i == 0 ? TextAlign.start : TextAlign.end,
              style: head
                  ? theme.textTheme.labelMedium?.copyWith(color: p.muted)
                  : theme.textTheme.bodyMedium,
            ),
          ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Collection ${c.number}: ${c.size} puzzles rated about '
          '${c.meta['center'] ?? c.targetRating}',
          style: theme.textTheme.titleSmall,
        ),
        if (c.meta['reason'] != null) Text('${c.meta['reason']}', style: muted),
        const SizedBox(height: 8),
        if (cycles.isEmpty)
          Text('No puzzles solved yet.', style: muted)
        else
          Table(
            columnWidths: const {0: FlexColumnWidth(1.4)},
            children: [
              row([
                'Cycle',
                'First try',
                'Solved',
                'Avg time',
                'Wrong',
                'Hints',
                'Skipped',
              ], head: true),
              for (final cy in cycles)
                () {
                  final s = AttemptSummary(cy.attempts);
                  return row([
                    '${cy.number}${cy.status == CycleStatus.active ? ' (${cy.done}/${c.size})' : ''}',
                    _pct(s.firstTryRate),
                    _pct(s.solvedRate),
                    _time(s.averageTime),
                    '${s.wrongMoves}',
                    '${s.hinted}',
                    '${s.skipped}',
                  ]);
                }(),
            ],
          ),
        if (themes.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('By theme (all cycles)', style: theme.textTheme.titleSmall),
          Text(
            'Themes seen at least 3 times. "Repeated" counts puzzles solved '
            'first try in two or more cycles.',
            style: muted,
          ),
          const SizedBox(height: 6),
          Table(
            columnWidths: const {0: FlexColumnWidth(2)},
            children: [
              row([
                'Theme',
                'Attempts',
                'First try',
                'Avg time',
                'Repeated',
              ], head: true),
              for (final s in themes.take(14))
                row([
                  themeName(s.theme),
                  '${s.attempts}',
                  '${(s.firstTryRate * 100).round()}%',
                  _time(s.averageTime),
                  '${s.repeatedSuccess}/${s.puzzles.length}',
                ]),
            ],
          ),
        ],
      ],
    );
  }
}
