part of 'training_screen.dart';

/// The puzzle being solved: a large board and a focused side panel.
class _SolveView extends StatelessWidget {
  const _SolveView();

  @override
  Widget build(BuildContext context) {
    final p = PlyPalette.of(context);
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 900;
            final panel = Container(
              width: wide ? 400 : null,
              decoration: p.panelBox(),
              clipBehavior: Clip.antiAlias,
              child: const _SolvePanel(),
            );
            if (wide) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Expanded(child: Center(child: _PuzzleBoard())),
                    const SizedBox(width: 16),
                    panel,
                  ],
                ),
              );
            }
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: SizedBox(
                    height: c.maxHeight * 0.55,
                    child: const Center(child: _PuzzleBoard()),
                  ),
                ),
                Expanded(child: panel),
              ],
            );
          },
        ),
      ),
    );
  }
}

const _wrongColor = Color(0xFFE5403A);

(Square, Square)? _squares(String? uci) => uci == null
    ? null
    : (
        Square.fromName(uci.substring(0, 2)),
        Square.fromName(uci.substring(2, 4)),
      );

/// A round marker for a square: ✗ for a wrong move, ✓ for a right one.
Widget _mark(IconData icon, Color color) => Container(
  decoration: BoxDecoration(
    color: color,
    shape: BoxShape.circle,
    boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black45)],
  ),
  child: Icon(icon, size: 16, color: Colors.white),
);

/// The puzzle board. It shows what the session wants seen: a wrong move
/// in red (then taken back), a right move in green, the solution step by
/// step. Moves are only accepted when no feedback is playing.
class _PuzzleBoard extends StatelessWidget {
  const _PuzzleBoard();

  @override
  Widget build(BuildContext context) {
    final t = _watch(context);
    final s = t.session!;
    final sol = s.solver;
    final hint = s.hint;
    final fb = s.feedback;
    final last = s.boardMove;
    // The move just made by the player (not the opponent's reply).
    final playerMove =
        last != null &&
        (s.shownMove != null ||
            fb == MoveFeedback.correct ||
            fb == MoveFeedback.solved);
    final wrongShown = fb == MoveFeedback.wrong && s.shownMove != null;
    final good = fb == MoveFeedback.correct || fb == MoveFeedback.solved;
    final frame = wrongShown
        ? _wrongColor
        : good
        ? classColorGood
        : null;
    final (Square, Widget)? badge = wrongShown
        ? (_squares(last)!.$2, _mark(Icons.close, _wrongColor))
        : good && playerMove
        ? (_squares(last)!.$2, _mark(Icons.check, classColorGood))
        : hint?.from != null && hint?.move == null
        ? (
            hint!.from!,
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF2BE2B),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lightbulb,
                size: 14,
                color: Colors.black87,
              ),
            ),
          )
        : null;
    final arrow = s.solutionArrow ?? hint?.move;
    return LayoutBuilder(
      builder: (context, c) {
        final size = math.min(c.maxWidth, c.maxHeight);
        return _Shake(
          trigger: wrongShown ? s.feedbackId : 0,
          child: SizedBox.square(
            dimension: size,
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: frame?.withValues(alpha: 0.85) ?? Colors.transparent,
                  width: 3,
                ),
              ),
              child: ChessBoard(
                position: s.boardPosition,
                orientation: sol.solver,
                lastMove: _squares(last),
                lastMoveColor: wrongShown
                    ? _wrongColor.withValues(alpha: 0.55)
                    : good && playerMove
                    ? classColorGood.withValues(alpha: 0.55)
                    : null,
                arrows: [
                  if (arrow != null)
                    BoardArrow(
                      _squares(arrow)!.$1,
                      _squares(arrow)!.$2,
                      s.solutionArrow != null
                          ? classColorGood.withValues(alpha: 0.85)
                          : BoardColors.arrow,
                    ),
                ],
                badge: badge,
                onMove: s.over || s.busy || sol.replyPending ? null : t.play,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Shakes its child sideways briefly whenever [trigger] changes to a
/// non-zero value. Skipped when the system asks for reduced motion.
class _Shake extends StatefulWidget {
  const _Shake({required this.trigger, required this.child});
  final int trigger;
  final Widget child;

  @override
  State<_Shake> createState() => _ShakeState();
}

class _ShakeState extends State<_Shake> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );

  @override
  void didUpdateWidget(_Shake old) {
    super.didUpdateWidget(old);
    final calm = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.trigger != 0 && widget.trigger != old.trigger && !calm) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (context, child) {
      final v = _c.value;
      final dx = v == 0 || v == 1
          ? 0.0
          : math.sin(v * math.pi * 6) * 8 * (1 - v);
      return Transform.translate(offset: Offset(dx, 0), child: child);
    },
  );
}

class _SolvePanel extends StatelessWidget {
  const _SolvePanel();

  @override
  Widget build(BuildContext context) {
    final t = _watch(context);
    final s = t.session!;
    final theme = Theme.of(context);
    final p = PlyPalette.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: p.muted);
    final calibration = s.kind == SessionKind.calibration;
    final c = t.active;
    final side = s.solver.solver == Side.white ? 'White' : 'Black';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(10, 10, 10, 0),
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: plyBlue,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            calibration ? 'Calibration' : 'Puzzle Training',
            style: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              Text(
                calibration
                    ? 'Puzzle ${s.number} of ${s.total}'
                    : 'Collection ${c?.number} · Cycle '
                          '${c?.currentCycle?.number ?? c?.cycles.length} of '
                          '${c?.plannedCycles} · Puzzle ${s.number} of ${s.total}',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(value: (s.number - 1) / s.total),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.circle,
                    size: 14,
                    color: side == 'White' ? Colors.white : Colors.black,
                    shadows: const [Shadow(blurRadius: 2)],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.over
                          ? 'You played $side'
                          : '$side to move: find the best move',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  const _Clock(),
                  _Stat('Puzzle rating', '${s.puzzle.rating}'),
                  if (s.puzzle.playerMoves > 1)
                    _Stat('Moves to find', '${s.puzzle.playerMoves}'),
                ],
              ),
              const SizedBox(height: 12),
              // Fades in each new message, so every move visibly registers.
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: s.message == null
                    ? const SizedBox.shrink()
                    : KeyedSubtree(
                        key: ValueKey('${s.feedbackId} ${s.message}'),
                        child: _Feedback(s),
                      ),
              ),
              const SizedBox(height: 12),
              if (!s.over)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (t.profile?.hintsEnabled ?? true)
                      Tooltip(
                        message:
                            'First the theme, then the piece, then the '
                            'move. Costs first-try credit.',
                        child: OutlinedButton.icon(
                          onPressed: s.busy || s.solver.replyPending
                              ? null
                              : t.hint,
                          icon: const Icon(Icons.lightbulb_outline, size: 18),
                          label: Text(
                            s.solver.hintLevel == 0
                                ? 'Hint'
                                : 'More (${s.solver.hintLevel}/3)',
                          ),
                        ),
                      ),
                    Tooltip(
                      message: 'Back to the starting position',
                      child: OutlinedButton.icon(
                        onPressed: s.busy ? null : t.resetPuzzle,
                        icon: const Icon(Icons.restart_alt, size: 18),
                        label: const Text('Reset'),
                      ),
                    ),
                    Tooltip(
                      message:
                          'Show the solution; the puzzle counts as not '
                          'solved',
                      child: OutlinedButton.icon(
                        onPressed: s.busy ? null : t.showSolution,
                        icon: const Icon(Icons.visibility_outlined, size: 18),
                        label: const Text('Solution'),
                      ),
                    ),
                    Tooltip(
                      message: 'Skip this puzzle (recorded as skipped)',
                      child: TextButton(
                        onPressed: s.busy ? null : t.skip,
                        child: const Text('Skip'),
                      ),
                    ),
                  ],
                )
              else
                _Result(s),
              const SizedBox(height: 16),
              Text(
                'Moves are checked against the full solution from the '
                'Lichess puzzle database; any checkmate also counts.',
                style: muted?.copyWith(fontSize: 11),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: p.border),
        Padding(
          padding: const EdgeInsets.all(6),
          child: TextButton.icon(
            onPressed: t.closeSession,
            icon: const Icon(Icons.pause, size: 18),
            label: Text(
              s.over
                  ? 'Back to the overview'
                  : 'Pause (this puzzle starts again later)',
            ),
          ),
        ),
      ],
    );
  }
}

/// Elapsed time on the current puzzle.
class _Clock extends StatefulWidget {
  const _Clock();

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(
      const Duration(seconds: 1),
      (_) => mounted ? setState(() {}) : null,
    );
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _watch(context).session;
    return _Stat('Time', _time(s?.clock.elapsed));
  }
}

class _Feedback extends StatelessWidget {
  const _Feedback(this.s);
  final PuzzleSession s;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final good =
        s.feedback == MoveFeedback.correct || s.feedback == MoveFeedback.solved;
    final bad = s.feedback == MoveFeedback.wrong;
    final color = good
        ? classColorGood
        : bad
        ? const Color(0xFFE5403A)
        : theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(
            good
                ? Icons.check_circle
                : bad
                ? Icons.cancel
                : Icons.info_outline,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(s.message!, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// After the puzzle: outcome, the idea, the solution, time and help used.
class _Result extends StatelessWidget {
  const _Result(this.s);
  final PuzzleSession s;

  @override
  Widget build(BuildContext context) {
    final t = _watch(context);
    final theme = Theme.of(context);
    final p = PlyPalette.of(context);
    final a = s.result!;
    final title = a.firstTryCorrect
        ? 'Solved first try'
        : a.solved
        ? 'Solved with help'
        : a.skipped
        ? 'Skipped'
        : 'Not solved';
    final motifs = s.puzzle.motifs;
    final next = s.kind == SessionKind.calibration
        ? (t.profile!.calibration.length >= t.config.calibrationLength
              ? 'Finish calibration'
              : 'Next puzzle')
        : ((t.active?.currentCycle?.remaining ?? 0) == 0
              ? 'See the cycle results'
              : 'Next puzzle');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: p.cardBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            motifs.isEmpty
                ? 'Idea: ${s.puzzle.themes.contains('mate') ? 'a forced checkmate' : 'the most forcing continuation'}.'
                : 'Idea: ${motifs.map(themeName).join(', ')}.',
            style: theme.textTheme.bodyMedium,
          ),
          Text(
            'Solution: ${formatSolution(s.puzzle)}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            [
              'Time ${_time(Duration(milliseconds: a.elapsedMs))}',
              '${a.wrongMoves} wrong move${a.wrongMoves == 1 ? '' : 's'}',
              a.hintLevel == 0 ? 'no hints' : 'hint level ${a.hintLevel}',
            ].join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(color: p.muted),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            autofocus: true,
            onPressed: () {
              final more = s.kind == SessionKind.calibration
                  ? t.nextCalibration()
                  : t.nextInCycle();
              if (!more) t.closeSession();
            },
            icon: const Icon(Icons.arrow_forward),
            label: Text(next),
          ),
        ],
      ),
    );
  }
}
