import 'dart:async';
import 'dart:math' as math;

import 'package:dartchess/dartchess.dart' show Side, Square;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../training/puzzle.dart';
import '../../training/puzzle_solver.dart';
import '../../training/recommender.dart';
import '../../training/training_controller.dart';
import '../../training/training_stats.dart';
import '../../training/training_store.dart';
import '../board/chess_board.dart';
import '../services.dart';
import '../theme.dart';

part 'training_solve.dart';
part 'training_results.dart';
part 'training_dialogs.dart';

/// Rebuilds every Training widget that calls [_watch] when training state
/// changes (const widgets included), like the analysis screen does.
class _Scope extends InheritedNotifier<TrainingController> {
  const _Scope({required super.notifier, required super.child});
}

TrainingController _watch(BuildContext context) {
  context.dependOnInheritedWidgetOfExactType<_Scope>();
  return Services.of(context).training;
}

String _pct(double? v) => v == null ? '–' : '${v.round()}%';

String _time(Duration? d) {
  if (d == null) return '–';
  final s = d.inSeconds;
  return s < 60 ? '$s s' : '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// Puzzle Training (Woodpecker method): set-up, calibration, collections,
/// the solving screen and results. Picks the right view from the
/// controller's state, so training resumes where it stopped.
class TrainingScreen extends StatefulWidget {
  const TrainingScreen({super.key});

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  /// After a collection is completed: the user chose to plan the next one.
  bool _planning = false;

  @override
  Widget build(BuildContext context) {
    final t = Services.of(context).training;
    return _Scope(
      notifier: t,
      child: ListenableBuilder(
        listenable: t,
        builder: (context, _) {
          if (!t.catalogue.loaded) {
            return const Center(child: CircularProgressIndicator());
          }
          if (t.session != null) return const _SolveView();
          final p = t.profile;
          final Widget body;
          if (t.store.loadError != null && p == null) {
            body = _Note(
              icon: Icons.error_outline,
              title: 'Training data could not be read',
              text: t.store.loadError!,
            );
          } else if (p == null) {
            body = const _Setup();
          } else if (!p.calibrated) {
            body = const _CalibrationIntro();
          } else {
            final a = t.active;
            final last = t.store.collections.isEmpty
                ? null
                : t.store.collections.last;
            if (a == null) {
              body = last?.status == CollectionStatus.completed && !_planning
                  ? _CollectionResults(
                      last!,
                      onPlan: () => setState(() => _planning = true),
                    )
                  : _NewCollection(onCreated: () => _planning = false);
            } else if (a.currentCycle == null) {
              body = _CycleResults(a, a.cycles.last);
            } else {
              body = _Dashboard(a);
            }
          }
          return _Page(child: body);
        },
      ),
    );
  }
}

/// A centred, scrolling page with the Training heading.
class _Page extends StatelessWidget {
  const _Page({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = _watch(context);
    final theme = Theme.of(context);
    final p = PlyPalette.of(context);
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 940),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Puzzle Training',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Woodpecker method: solve the same puzzles three '
                            'times to make tactics automatic.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: p.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (t.profile != null) ...[
                      IconButton(
                        tooltip: 'Download or import puzzles',
                        onPressed: () => showPuzzleDownloads(context),
                        icon: const Icon(Icons.cloud_download_outlined),
                      ),
                      IconButton(
                        tooltip: 'Training settings',
                        onPressed: () => showTrainingSettings(context),
                        icon: const Icon(Icons.tune),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.accent});
  final Widget child;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final p = PlyPalette.of(context);
    // A Material (not a coloured box) so list tiles show hover and ripples.
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: p.panelHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: accent?.withValues(alpha: 0.6) ?? p.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(width: double.infinity, child: child),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.title, required this.text});
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                Text(text, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A labelled number for stat rows.
class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.tooltip});
  final String label;
  final String value;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = PlyPalette.of(context);
    final w = Container(
      constraints: const BoxConstraints(minWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: p.input,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: p.muted),
          ),
          Text(value, style: theme.textTheme.titleMedium),
        ],
      ),
    );
    return tooltip == null ? w : Tooltip(message: tooltip!, child: w);
  }
}

// --- set-up -----------------------------------------------------------------

class _Setup extends StatefulWidget {
  const _Setup();

  @override
  State<_Setup> createState() => _SetupState();
}

class _SetupState extends State<_Setup> {
  RatingSource _source = RatingSource.none;
  final _rating = TextEditingController();
  int _size = 100;
  WrongMoveBehavior _wrong = WrongMoveBehavior.retry;
  bool _hints = true;

  @override
  void dispose() {
    _rating.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _watch(context);
    final theme = Theme.of(context);
    final p = PlyPalette.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: p.muted);
    final rating = int.tryParse(_rating.text.trim());
    final needsRating = _source != RatingSource.none;
    final ratingOk =
        !needsRating || (rating != null && rating >= 100 && rating <= 3500);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('How it works', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                '1. Ply builds a collection of 50, 100 or 200 tactics puzzles '
                'at your level, with mixed themes.\n'
                '2. You solve the whole collection three times (three '
                'cycles). Each time, patterns come back faster.\n'
                '3. Then Ply looks at your results and builds a new '
                'collection, a bit harder or more focused where needed.\n'
                'Puzzles come from the Lichess puzzle database and work '
                'offline. Your progress is saved on this PC.',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your rating (optional)', style: theme.textTheme.titleSmall),
              Text(
                'Used only as a starting point; a short calibration refines '
                'it.',
                style: muted,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DropdownMenu<RatingSource>(
                    initialSelection: _source,
                    label: const Text('Rating from'),
                    onSelected: (v) => setState(() => _source = v ?? _source),
                    dropdownMenuEntries: [
                      for (final s in RatingSource.values)
                        DropdownMenuEntry(value: s, label: s.label),
                    ],
                  ),
                  if (needsRating)
                    SizedBox(
                      width: 140,
                      child: TextField(
                        controller: _rating,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          hintText: 'e.g. 1500',
                          errorText: _rating.text.isNotEmpty && !ratingOk
                              ? '100–3500'
                              : null,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Collection size', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              _SizePicker(
                value: _size,
                onChanged: (v) => setState(() => _size = v),
              ),
              const SizedBox(height: 16),
              Text('After a wrong move', style: theme.textTheme.titleSmall),
              _WrongMovePicker(
                value: _wrong,
                onChanged: (v) => setState(() => _wrong = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow hints'),
                subtitle: const Text(
                  'Theme, then the piece to move, then the move. A puzzle '
                  'solved with a hint does not count as solved first try.',
                ),
                value: _hints,
                onChanged: (v) => setState(() => _hints = v),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: !ratingOk || (needsRating && rating == null)
                    ? null
                    : () => t.createProfile(
                        source: _source,
                        rating: needsRating ? rating : null,
                        size: _size,
                        wrongMove: _wrong,
                        hints: _hints,
                      ),
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Continue'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SizePicker extends StatelessWidget {
  const _SizePicker({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<int>(
    showSelectedIcon: false,
    segments: const [
      ButtonSegment(value: 50, label: Text('50 puzzles')),
      ButtonSegment(value: 100, label: Text('100 (recommended)')),
      ButtonSegment(value: 200, label: Text('200 puzzles')),
    ],
    selected: {value},
    onSelectionChanged: (v) => onChanged(v.first),
  );
}

class _WrongMovePicker extends StatelessWidget {
  const _WrongMovePicker({required this.value, required this.onChanged});
  final WrongMoveBehavior value;
  final ValueChanged<WrongMoveBehavior> onChanged;

  @override
  Widget build(BuildContext context) => RadioGroup<WrongMoveBehavior>(
    groupValue: value,
    onChanged: (v) => onChanged(v ?? value),
    child: const Column(
      children: [
        RadioListTile(
          contentPadding: EdgeInsets.zero,
          value: WrongMoveBehavior.retry,
          title: Text('Let me try again (recommended)'),
          subtitle: Text('The mistake is counted; the puzzle stays open.'),
        ),
        RadioListTile(
          contentPadding: EdgeInsets.zero,
          value: WrongMoveBehavior.reveal,
          title: Text('Show the solution'),
          subtitle: Text('The puzzle ends and counts as not solved.'),
        ),
      ],
    ),
  );
}

class _CalibrationIntro extends StatelessWidget {
  const _CalibrationIntro();

  @override
  Widget build(BuildContext context) {
    final t = _watch(context);
    final theme = Theme.of(context);
    final p = t.profile!;
    final done = p.calibration.length;
    final total = t.config.calibrationLength;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Find your level', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            '$total quick puzzles. Each one adapts to how you did on the '
            'last, so Ply can choose puzzles that are challenging but '
            'solvable. Take your time; there is no clock pressure.\n'
            'Starting estimate: about ${p.estimate.round()} '
            '(confidence: ${confidenceLabel(p.deviation)}).',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: t.nextCalibration,
                icon: const Icon(Icons.play_arrow),
                label: Text(
                  done == 0
                      ? 'Start calibration'
                      : 'Continue calibration ($done of $total)',
                ),
              ),
              TextButton(
                onPressed: t.skipCalibration,
                child: const Text('Skip, use my starting estimate'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// --- planning a collection ---------------------------------------------------

class _NewCollection extends StatefulWidget {
  const _NewCollection({required this.onCreated});
  final VoidCallback onCreated;

  @override
  State<_NewCollection> createState() => _NewCollectionState();
}

class _NewCollectionState extends State<_NewCollection> {
  int? _size;
  bool _reuse = false;
  final _seed = DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
  Object? _plan;
  String _planKey = '';
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final t = _watch(context);
    final theme = Theme.of(context);
    final p = PlyPalette.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: p.muted);
    final prof = t.profile!;
    final size = _size ?? prof.preferredSize;
    final key =
        '$size $_reuse ${t.catalogue.size} ${t.store.collections.length}';
    if (key != _planKey) {
      _planKey = key;
      _plan = t.planCollection(size, allowReuse: _reuse, seed: _seed);
    }
    final plan = _plan;
    final adj = t.nextAdjustment;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.store.collections.isEmpty
                    ? 'Your first collection'
                    : 'Next collection',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Puzzle level: about ${prof.estimate.round()} '
                '(confidence: ${confidenceLabel(prof.deviation)}). '
                '${adj.reason}',
                style: muted,
              ),
              const SizedBox(height: 12),
              _SizePicker(
                value: size,
                onChanged: (v) => setState(() => _size = v),
              ),
              const SizedBox(height: 12),
              if (plan is CollectionPlan) ...[
                _PlanPreview(plan),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          if (size != prof.preferredSize) {
                            await t.updatePreferences(size: size);
                          }
                          await t.createCollection(plan);
                          widget.onCreated();
                          t.nextInCycle();
                        },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Create collection and start cycle 1'),
                ),
              ] else if (plan is Shortage) ...[
                _Note(
                  icon: Icons.inventory_2_outlined,
                  title: 'Not enough suitable puzzles',
                  text: plan.message,
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => showPuzzleDownloads(context),
                      icon: const Icon(Icons.cloud_download_outlined),
                      label: const Text('Download puzzles'),
                    ),
                    if (!_reuse && plan.availableWithReuse >= size)
                      OutlinedButton(
                        onPressed: () => setState(() => _reuse = true),
                        child: const Text(
                          'Allow puzzles from earlier collections',
                        ),
                      ),
                    if (size > 50)
                      OutlinedButton(
                        onPressed: () =>
                            setState(() => _size = size == 200 ? 100 : 50),
                        child: Text('Use ${size == 200 ? 100 : 50} puzzles'),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'Library: ${t.catalogue.size} puzzles '
                '(${t.catalogue.userSize} downloaded or imported).',
                style: muted,
              ),
            ],
          ),
        ),
        const _History(),
      ],
    );
  }
}

class _PlanPreview extends StatelessWidget {
  const _PlanPreview(this.plan);
  final CollectionPlan plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counts = <String, int>{};
    for (final p in plan.puzzles) {
      counts[p.primaryTheme] = (counts[p.primaryTheme] ?? 0) + 1;
    }
    final top = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Stat(
              'Difficulty',
              '${plan.center - plan.halfWidth}–${plan.center + plan.halfWidth}',
              tooltip:
                  'Lichess puzzle ratings, centred a little below your '
                  'level so most puzzles are solvable.',
            ),
            _Stat('General', '${plan.general}'),
            _Stat(
              'Targeted',
              '${plan.targeted}',
              tooltip: plan.targetThemes.isEmpty
                  ? 'No clear weak themes yet; a broad mix instead.'
                  : 'Aimed at: ${plan.targetThemes.map(themeName).join(', ')}',
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          plan.targetThemes.isEmpty
              ? 'A broad mix of tactical themes:'
              : 'Extra practice on ${plan.targetThemes.map(themeName).join(', ')}; '
                    'themes in this collection:',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final e in top.take(10))
              Chip(
                label: Text('${themeName(e.key)} ${e.value}'),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        if (plan.reusesOldPuzzles)
          Text(
            'Includes some puzzles from earlier collections.',
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }
}

// --- dashboard ---------------------------------------------------------------

class _Dashboard extends StatelessWidget {
  const _Dashboard(this.c);
  final TrainingCollection c;

  @override
  Widget build(BuildContext context) {
    final t = _watch(context);
    final theme = Theme.of(context);
    final p = PlyPalette.of(context);
    final cycle = c.currentCycle!;
    final sum = AttemptSummary(cycle.attempts);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
          accent: theme.colorScheme.primary,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Collection ${c.number} · ${c.size} puzzles',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  for (var n = 1; n <= c.plannedCycles; n++)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: _CycleDot(c, n),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Cycle ${cycle.number} of ${c.plannedCycles} · '
                '${cycle.done} done, ${cycle.remaining} to go',
                style: theme.textTheme.bodySmall?.copyWith(color: p.muted),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: cycle.done / c.size),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Stat(
                    'First-try accuracy',
                    _pct(sum.firstTryRate),
                    tooltip:
                        'Solved with no wrong move and no hint, this '
                        'cycle so far.',
                  ),
                  _Stat('Solved', _pct(sum.solvedRate)),
                  _Stat('Average time', _time(sum.averageTime)),
                  _Stat(
                    'Puzzle level',
                    '${t.profile!.estimate.round()}',
                    tooltip:
                        'Estimated Lichess puzzle rating '
                        '(confidence: ${confidenceLabel(t.profile!.deviation)}).',
                  ),
                  if (c.cycles.length > 1)
                    _Stat(
                      'Provisionally mastered',
                      '${masteredCount(c)} of ${c.size}',
                      tooltip: const MasteryRulesNote().text,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(220, 48),
                    ),
                    onPressed: t.nextInCycle,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(
                      cycle.done == 0
                          ? 'Start cycle ${cycle.number}'
                          : 'Continue training',
                    ),
                  ),
                  TextButton(
                    onPressed: () => _confirmAbandon(context, c),
                    child: const Text('Abandon collection'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const _History(),
      ],
    );
  }
}

/// Text for the provisional-mastery tooltip.
class MasteryRulesNote {
  const MasteryRulesNote([this.rules = const MasteryRules()]);
  final MasteryRules rules;
  String get text =>
      'Solved first try, without hints, within ${rules.maxSeconds} s in the '
      'last ${rules.cycles} cycles. A rough guide, not a measure of skill.';
}

class _CycleDot extends StatelessWidget {
  const _CycleDot(this.c, this.n);
  final TrainingCollection c;
  final int n;

  @override
  Widget build(BuildContext context) {
    final cy = c.cycle(n);
    final done = cy?.status == CycleStatus.completed;
    final current = cy != null && !done;
    final color = done
        ? classColorGood
        : current
        ? Theme.of(context).colorScheme.primary
        : PlyPalette.of(context).border;
    return Tooltip(
      message: done
          ? 'Cycle $n done'
          : current
          ? 'Cycle $n in progress'
          : 'Cycle $n not started',
      child: CircleAvatar(
        radius: 13,
        backgroundColor: color.withValues(alpha: done || current ? 0.9 : 0.4),
        child: done
            ? const Icon(Icons.check, size: 15, color: Colors.white)
            : Text(
                '$n',
                style: const TextStyle(fontSize: 12, color: Colors.white),
              ),
      ),
    );
  }
}

const classColorGood = Color(0xFF7FB13D);

Future<void> _confirmAbandon(BuildContext context, TrainingCollection c) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Abandon this collection?'),
      content: const Text(
        'Its results stay in your history, but you cannot continue it. '
        'Ply then plans a new collection.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Keep training'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Abandon'),
        ),
      ],
    ),
  );
  if (ok == true && context.mounted) {
    await _watch(context).abandonActive();
  }
}

/// Every collection so far, newest first; tap one for its results.
class _History extends StatelessWidget {
  const _History();

  @override
  Widget build(BuildContext context) {
    final t = _watch(context);
    final theme = Theme.of(context);
    final p = PlyPalette.of(context);
    final list = t.store.collections.reversed.toList();
    if (list.isEmpty) return const SizedBox.shrink();
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Collection history', style: theme.textTheme.titleSmall),
          for (final c in list)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Collection ${c.number} · ${c.size} puzzles · '
                '${switch (c.status) {
                  CollectionStatus.active => 'in progress',
                  CollectionStatus.completed => 'completed',
                  CollectionStatus.abandoned => 'abandoned',
                }}',
              ),
              subtitle: Text(
                c.cycles.isEmpty
                    ? 'Not started'
                    : 'First-try accuracy by cycle: ${c.cycles.map((cy) => _pct(AttemptSummary(cy.attempts).firstTryRate)).join(' → ')}',
                style: theme.textTheme.bodySmall?.copyWith(color: p.muted),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => Dialog(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: _CollectionReport(c),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
