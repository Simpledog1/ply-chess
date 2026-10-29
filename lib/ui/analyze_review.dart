part of 'analyze_screen.dart';

/// Move number prefix for the move played from [before], e.g. `14.` / `14…`.
String _moveNo(Position before) =>
    '${before.fullmoves}${before.turn == Side.white ? '.' : '…'} ';

/// Players, result and opening of the open game.
class _GameTitle extends StatelessWidget {
  const _GameTitle();

  @override
  Widget build(BuildContext context) {
    final a = watchAnalysis(context);
    final theme = Theme.of(context);
    final p = PlyPalette.of(context);
    final h = a.game.headers;
    String? name(String k) => h[k] == null || h[k] == '?' ? null : h[k];
    final w = name('White'), b = name('Black');
    final title = w != null && b != null
        ? '$w vs $b'
        : a.game.length == 0
        ? 'Analysis board'
        : 'Game';
    final result = a.game.result;
    final date = name('Date')?.replaceAll('.??', '');
    final sub = [
      if (result != '*') result,
      ?a.openingName,
      if (date != null && !date.startsWith('?')) date,
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium,
        ),
        if (sub.isNotEmpty)
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: p.muted),
          ),
      ],
    );
  }
}

/// What the shown move was worth: the heart of the analysis screen. Shows
/// the rating, the evaluation before and after, Stockfish's move and line,
/// or an honest pending state while that is not known yet.
class _MoveFeedback extends StatelessWidget {
  const _MoveFeedback();

  @override
  Widget build(BuildContext context) {
    final a = watchAnalysis(context);
    final theme = Theme.of(context);
    final p = PlyPalette.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: p.muted);
    if (a.preview != null) return const _PreviewBanner();

    Widget card({required Widget child, Color? accent}) => AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: p.cardBox(accent: accent),
      child: child,
    );
    Widget note(IconData icon, String title, String text, [Widget? action]) =>
        card(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 22, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(text, style: muted),
                    if (action != null) ...[const SizedBox(height: 8), action],
                  ],
                ),
              ),
            ],
          ),
        );

    final l = a.line;
    if (l.length == 0) {
      return note(
        Icons.waving_hand_outlined,
        'Welcome to Ply',
        'Open one of your games (load a username, paste a PGN or open a '
            'file), then press Analyse game. Stockfish rates every move and '
            'this card explains each one. You can also play moves on the '
            'board.',
      );
    }
    if (a.ply == 0) {
      return note(
        Icons.flag_outlined,
        'Start position',
        a.review == null
            ? 'Press Analyse game to rate every move, or step through the '
                  'game with → or by clicking a move.'
            : 'Step through the game with → or click any move: each one is '
                  'rated here.',
      );
    }

    final before = l.positionAt(a.ply - 1);
    final played = l.plies[a.ply - 1];
    final whatIf = a.onWhatIf;
    final m = a.settings.hideClassifications ? null : a.lastMoveReview;
    final color = m == null ? null : classColor(m.cls);

    final header = Row(
      children: [
        if (m != null) ...[
          ClassBadge(m.cls, size: 30),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  MoveText(
                    played.san,
                    simple: a.settings.simpleNotation,
                    prefix: _moveNo(before),
                    style: theme.textTheme.titleMedium,
                  ),
                  if (m != null)
                    Tooltip(
                      message: m.explanation,
                      child: Text(
                        m.cls.label,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        _Pill(
          whatIf ? 'Your what-if move' : 'Played in the game',
          icon: whatIf ? Icons.alt_route : Icons.history_edu,
          color: whatIf ? classColor(MoveClass.inaccuracy) : p.muted,
        ),
      ],
    );

    if (m == null) {
      final best = a.analysisAt(a.ply - 1);
      final bestSan = best?.bestMove == null
          ? null
          : uciLineToSan(before, [best!.bestMove!]).firstOrNull;
      Widget status(Widget lead, String title, String text, [Widget? act]) =>
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(padding: const EdgeInsets.only(top: 2), child: lead),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.bodyMedium),
                        Text(text, style: muted),
                        if (act != null) ...[const SizedBox(height: 6), act],
                      ],
                    ),
                  ),
                ],
              ),
            ],
          );
      const spinner = SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
      final Widget body;
      if (a.settings.hideClassifications) {
        body = status(
          Icon(Icons.visibility_off_outlined, size: 18, color: p.muted),
          'Move ratings are hidden',
          'Turn them back on in Settings → Analysis.',
        );
      } else if (a.checkError != null) {
        body = status(
          Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
          'Could not check this move',
          a.checkError!,
          OutlinedButton.icon(
            onPressed: a.retryCheck,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Try again'),
          ),
        );
      } else if (whatIf && a.reviewing) {
        body = status(
          spinner,
          'Waiting for the game analysis',
          'Your move is checked as soon as Stockfish has finished the game.',
        );
      } else if (a.checking) {
        body = status(
          spinner,
          'Checking your move… (preliminary)',
          best?.bestMove == played.uci
              ? 'It matches Stockfish\'s top choice. Looking at the position '
                    'after it to rate it.'
              : bestSan != null
              ? 'Stockfish preferred $bestSan here. Measuring how much this '
                    'move changes the position.'
              : 'Stockfish is analysing the positions before and after it '
                    '(depth ${a.checkDepth}).',
        );
      } else if (a.reviewing) {
        body = status(
          spinner,
          'Analysing the game…',
          'This move is rated as soon as Stockfish reaches it.',
        );
      } else {
        final partial = a.review != null;
        body = status(
          Icon(Icons.hourglass_empty, size: 18, color: p.muted),
          'Analysis not available yet',
          partial
              ? 'The analysis stopped before this move. Resume it to rate it.'
              : 'Analyse the game to see how good each move was.',
          FilledButton.icon(
            onPressed: a.startReview,
            icon: const Icon(Icons.query_stats, size: 18),
            label: Text(partial ? 'Resume analysis' : 'Analyse game'),
          ),
        );
      }
      return card(child: body);
    }

    final showBest =
        m.bestSan != null &&
        !m.cls.isRoutine &&
        m.cls != MoveClass.best &&
        m.cls != MoveClass.brilliant &&
        m.cls != MoveClass.critical;
    final bestPv = a.analysisAt(a.ply - 1)?.pv ?? const <String>[];
    return card(
      accent: m.cls.isError ? color : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 8),
          Text(moveHeadline(m), style: theme.textTheme.bodyMedium),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _EvalBox('Before', m.before)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.arrow_forward, size: 16, color: p.muted),
              ),
              Expanded(child: _EvalBox('After', m.after, highlight: color)),
            ],
          ),
          if (showBest) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  size: 18,
                  color: classColor(MoveClass.best),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Stockfish\'s move: ',
                        style: theme.textTheme.bodyMedium,
                      ),
                      MoveText(
                        m.bestSan!,
                        simple: a.settings.simpleNotation,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: bestPv.isEmpty
                      ? null
                      : () {
                          final at = a.ply - 1;
                          a.goTo(at);
                          a.previewLine(bestPv, 0);
                        },
                  child: const Text('Show line'),
                ),
              ],
            ),
          ],
          if (m.replyLine.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('What follows: ${m.replyLine}', style: muted),
          ],
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final t in m.tags) _Pill(t.label, color: color ?? p.muted),
              Text(
                m.cls == MoveClass.theory
                    ? 'Opening book'
                    : 'Stockfish depth ${m.depth}'
                          '${whatIf ? ' · not part of the game' : ''}',
                style: muted?.copyWith(fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Evaluation with plain words below it.
class _EvalBox extends StatelessWidget {
  const _EvalBox(this.label, this.eval, {this.highlight});
  final String label;
  final Eval eval;
  final Color? highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = PlyPalette.of(context);
    return Tooltip(
      message: '+ favours White, − favours Black (in pawns)',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
            Text(
              eval.label,
              style: theme.textTheme.titleSmall?.copyWith(
                color: highlight,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              evalWords(eval),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(color: p.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small rounded label with an optional icon.
class _Pill extends StatelessWidget {
  const _Pill(this.text, {required this.color, this.icon});
  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// Shown while the board is on moves the user tried: the moves, undo, and
/// the way back to the game.
class _WhatIfBar extends StatelessWidget {
  const _WhatIfBar();

  @override
  Widget build(BuildContext context) {
    final a = watchAnalysis(context);
    final v = a.variation;
    if (v == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final p = PlyPalette.of(context);
    final amber = classColor(MoveClass.inaccuracy);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.alt_route, size: 20, color: amber),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What-if line from move ${_moveNo(v.positionAt(a.branch)).trim()}'
                  ' · the game itself is unchanged',
                  style: theme.textTheme.labelMedium?.copyWith(color: p.muted),
                ),
                const SizedBox(height: 2),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (var i = a.branch; i < v.length; i++)
                      _WhatIfMove(index: i),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Take back the last what-if move (Backspace)',
            onPressed: a.undoWhatIf,
            icon: const Icon(Icons.undo),
          ),
          const SizedBox(width: 4),
          FilledButton.tonalIcon(
            onPressed: a.backToGame,
            icon: const Icon(Icons.keyboard_return, size: 18),
            label: const Text('Back to game'),
          ),
        ],
      ),
    );
  }
}

class _WhatIfMove extends StatelessWidget {
  const _WhatIfMove({required this.index});
  final int index;

  @override
  Widget build(BuildContext context) {
    final a = watchAnalysis(context);
    final theme = Theme.of(context);
    final v = a.line;
    final before = v.positionAt(index);
    final m = a.settings.hideClassifications ? null : a.reviewAt(index + 1);
    final current = a.ply == index + 1;
    final first = index == a.branch;
    return Semantics(
      selected: current,
      label: m?.cls.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => a.goTo(index + 1),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: current
              ? BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(6),
                )
              : null,
          child: MoveText(
            v.plies[index].san,
            simple: a.settings.simpleNotation,
            prefix: before.turn == Side.white || first ? _moveNo(before) : '',
            suffix: m == null ? '' : classSymbol(m.cls),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: current ? FontWeight.w700 : null,
              color: m != null && m.cls.isError ? classColor(m.cls) : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// The game review, inline: summary, key moments, good moves and learning
/// points. Every item jumps to its position on the board.
class _GameReview extends StatelessWidget {
  const _GameReview();

  @override
  Widget build(BuildContext context) {
    final a = watchAnalysis(context);
    final theme = Theme.of(context);
    final p = PlyPalette.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: p.muted);
    final r = a.review;
    if (r == null || r.analysedCount == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Text(
          a.game.length == 0
              ? 'Open a game to see its review here.'
              : a.reviewing
              ? 'Stockfish is working through the game. Results appear here '
                    'as they come in.'
              : 'Press Analyse game: Stockfish checks every position, then '
                    'the summary, key moments and learning points appear '
                    'here, next to the board.',
          style: muted,
        ),
      );
    }
    final hide = a.settings.hideClassifications;
    final me =
        a.saved?.myColor ?? GameStore.detectColor(a.game, a.settings.myNames);
    final moves = a.moveReviews;
    final mine = [
      for (final m in moves)
        if (m != null && (me == null || m.mover == me)) m,
    ];
    final moments = criticalMoments(mine, limit: 5);
    final strong = [
      for (final m in mine)
        if (m.cls == MoveClass.brilliant || m.cls == MoveClass.critical) m,
    ].take(3).toList();
    final lessons = groupLessons(findLessons(a.game, r, moves, side: me));
    String who(Side s) {
      final n = a.game.headers[s == Side.white ? 'White' : 'Black'];
      return n == null || n == '?' ? (s == Side.white ? 'White' : 'Black') : n;
    }

    final result = a.game.result;
    final outcome = switch (result) {
      '1-0' => '${who(Side.white)} won',
      '0-1' => '${who(Side.black)} won',
      '1/2-1/2' => 'Draw',
      _ => null,
    };

    Widget heading(String t, [String? sub]) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t, style: theme.textTheme.titleSmall),
          if (sub != null) Text(sub, style: muted),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!r.complete)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              a.reviewing
                  ? 'Ready: ${r.analysedCount} of ${r.positions.length} '
                        'positions. The rest is still being calculated.'
                  : 'Partial analysis: ${r.analysedCount} of '
                        '${r.positions.length} positions. Results cover the '
                        'analysed part only.',
              style: muted?.copyWith(
                color: a.reviewing ? null : theme.colorScheme.error,
              ),
            ),
          ),
        if (outcome != null)
          Text(
            '$result · $outcome',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final s in Side.values) ...[
              if (s == Side.black) const SizedBox(width: 8),
              Expanded(
                child: _SideTile(
                  name: who(s),
                  summary: summarize(moves, s),
                  isMe: me == s,
                  hideCounts: hide,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Text('Winning chances for White', style: muted),
        const SizedBox(height: 4),
        SizedBox(
          height: 64,
          child: EvalGraph(
            review: r,
            moves: moves,
            current: a.onWhatIf ? a.branch : a.ply,
            onTap: a.goToGame,
          ),
        ),
        if (!hide) ...[
          heading(
            'Key moments',
            me == null
                ? 'The biggest swings in the game.'
                : 'Your biggest swings as '
                      '${me == Side.white ? 'White' : 'Black'}.',
          ),
          if (moments.isEmpty)
            Text(
              'No inaccuracies, mistakes or blunders at this depth.',
              style: muted,
            ),
          for (final m in moments) _MomentRow(m),
          if (strong.isNotEmpty) ...[
            heading('Well played'),
            for (final m in strong) _MomentRow(m),
          ],
        ],
        heading('Learning points', 'From this game only.'),
        if (lessons.isEmpty) Text('Nothing specific stood out.', style: muted),
        for (final (kind, items) in lessons)
          for (final l in items)
            _LinkRow(
              title: kind.label,
              text: l.text,
              onTap: () => a.goToGame(l.ply + 1),
            ),
        const SizedBox(height: 12),
        if (r.complete && r.depth < a.settings.deepReviewDepth && !a.reviewing)
          Align(
            alignment: Alignment.centerLeft,
            child: Tooltip(
              message:
                  'Re-checks every position at depth '
                  '${a.settings.deepReviewDepth}. Slower, a little more '
                  'reliable in sharp positions.',
              child: OutlinedButton.icon(
                onPressed: () =>
                    a.startReview(depth: a.settings.deepReviewDepth),
                icon: const Icon(Icons.manage_search, size: 18),
                label: const Text('Deeper review'),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Stockfish depth ${r.depth} for every position. Ratings come from '
          'the drop in the mover\'s winning chances (thresholds in Settings).',
          style: muted?.copyWith(fontSize: 11),
        ),
      ],
    );
  }
}

class _SideTile extends StatelessWidget {
  const _SideTile({
    required this.name,
    required this.summary,
    required this.isMe,
    required this.hideCounts,
  });
  final String name;
  final SideSummary summary;
  final bool isMe;
  final bool hideCounts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = PlyPalette.of(context);
    final acc = summary.accuracy;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: p.cardBox(accent: isMe ? theme.colorScheme.primary : null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isMe ? '$name (you)' : name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(color: p.muted),
          ),
          Tooltip(
            message: accuracyNote,
            child: Text(
              acc == null ? '–' : '${acc.toStringAsFixed(0)}% accuracy',
              style: theme.textTheme.titleSmall,
            ),
          ),
          if (!hideCounts) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                for (final c in [
                  MoveClass.inaccuracy,
                  MoveClass.mistake,
                  MoveClass.blunder,
                ])
                  Tooltip(
                    message: '${summary.counts[c]} × ${c.label}',
                    child: Text(
                      '${summary.counts[c]} ${classSymbol(c)}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: classColor(c),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A rated move in the review: jumps to it, or to the position before it to
/// look for the better move.
class _MomentRow extends StatelessWidget {
  const _MomentRow(this.m);
  final MoveReview m;

  @override
  Widget build(BuildContext context) {
    final a = watchAnalysis(context);
    final theme = Theme.of(context);
    final p = PlyPalette.of(context);
    final selected = !a.onWhatIf && a.ply == m.ply + 1;
    final before = a.game.positionAt(m.ply);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Material(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.14)
            : p.panelHigh,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => a.goToGame(m.ply + 1),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            child: Row(
              children: [
                ClassBadge(m.cls, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          MoveText(
                            m.san,
                            simple: a.settings.simpleNotation,
                            prefix: _moveNo(before),
                            suffix: classSymbol(m.cls),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            m.cls.label,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: classColor(m.cls),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        m.cls.isError && m.bestSan != null
                            ? '${m.before.label} → ${m.after.label} · '
                                  'better was ${m.bestSan}'
                            : moveHeadline(m),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: p.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (m.cls.isError)
                  IconButton(
                    tooltip:
                        'Go to the position before it and find the '
                        'better move',
                    onPressed: () => a.goToGame(m.ply),
                    icon: const Icon(Icons.lightbulb_outline, size: 20),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.title,
    required this.text,
    required this.onTap,
  });
  final String title;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = PlyPalette.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.school_outlined, size: 16, color: p.muted),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    text,
                    style: theme.textTheme.bodySmall?.copyWith(color: p.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
