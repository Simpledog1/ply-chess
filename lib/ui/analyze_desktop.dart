part of 'analyze_screen.dart';

/// Desktop: the board on the left, taking most of the width, and the Game
/// Analysis panel on the right (games, report, analysis, move controls).
class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({required this.width});
  final double width;

  @override
  Widget build(BuildContext context) {
    final p = PlyPalette.of(context);
    final panel = width >= 1500
        ? 460.0
        : width >= 1250
        ? 420.0
        : 384.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) =>
                  Center(child: _BoardArea(maxHeight: c.maxHeight)),
            ),
          ),
          const SizedBox(width: 16),
          Container(
            width: panel,
            decoration: p.panelBox(),
            clipBehavior: Clip.antiAlias,
            child: const _SidePanel(),
          ),
        ],
      ),
    );
  }
}

enum _View { games, report, analysis }

/// The Game Analysis panel. Games lists the loaded profile's games and the
/// PGN/FEN imports; Report summarises the analysed game; Analysis rates the
/// shown move, suggests the next one and holds the moves and what-if line.
class _SidePanel extends StatefulWidget {
  const _SidePanel();

  @override
  State<_SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<_SidePanel> {
  final _currentKey = GlobalKey();
  String _lastShown = '';
  _View? _view;
  ChessGame? _lastGame;
  bool _hadVariation = false;
  GamesBrowser? _browser;
  Object? _lastFeed;
  String? _lastError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final b = Services.of(context).browser;
    if (b != _browser) {
      _browser?.removeListener(_onBrowser);
      _browser = b..addListener(_onBrowser);
      _lastFeed = b.feed;
      _lastError = b.error;
    }
  }

  @override
  void dispose() {
    _browser?.removeListener(_onBrowser);
    super.dispose();
  }

  /// Loading games (top bar or Load more) shows them.
  void _onBrowser() {
    final b = _browser!;
    final changed =
        b.loading || !identical(b.feed, _lastFeed) || b.error != _lastError;
    _lastFeed = b.feed;
    _lastError = b.error;
    if (changed && _view != _View.games && mounted) {
      setState(() => _view = _View.games);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = watchAnalysis(context);
    // Opening a game shows its report; free-play moves show the analysis.
    if (_lastGame != null && !identical(a.game, _lastGame)) {
      _view = a.freePlay ? _View.analysis : _View.report;
    }
    _lastGame = a.game;
    // A new what-if line is only visible in the Analysis view.
    final hasVariation = a.variation != null;
    if (hasVariation && !_hadVariation) _view = _View.analysis;
    _hadVariation = hasVariation;
    final view = _view ??= a.game.length == 0 ? _View.games : _View.report;

    if (view == _View.analysis) {
      // Scroll the shown move (game or what-if) into view when it changes.
      // Also when the rating card above changes height.
      final shown =
          '${a.ply} ${a.onWhatIf} ${a.variation?.length} '
          '${a.checking} ${a.lastMoveReview != null}';
      if (shown != _lastShown) {
        _lastShown = shown;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = _currentKey.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(
              ctx,
              duration: const Duration(milliseconds: 120),
              alignment: 0.5,
            );
          }
        });
      }
    } else {
      _lastShown = '';
    }

    final p = PlyPalette.of(context);
    final theme = Theme.of(context);
    void show(_View v) => setState(() => _view = v);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A. Header.
        Container(
          margin: const EdgeInsets.fromLTRB(10, 10, 10, 0),
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: plyBlue,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'Game Analysis',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Your games and imports',
                isSelected: view == _View.games,
                onPressed: () => show(
                  view == _View.games && a.game.length > 0
                      ? _View.report
                      : _View.games,
                ),
                icon: const Icon(Icons.arrow_back),
                selectedIcon: const Icon(Icons.list_alt),
              ),
              const _ReviewAction(),
              const Spacer(),
              const _IconRow(compact: true),
            ],
          ),
        ),
        // B. Report / Analysis.
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
          child: SegmentedButton<_View>(
            showSelectedIcon: false,
            emptySelectionAllowed: true,
            segments: const [
              ButtonSegment(
                value: _View.report,
                label: Text('Report'),
                icon: Icon(Icons.assessment_outlined, size: 18),
              ),
              ButtonSegment(
                value: _View.analysis,
                label: Text('Analysis'),
                icon: Icon(Icons.manage_search, size: 18),
              ),
            ],
            selected: {if (view != _View.games) view},
            onSelectionChanged: (v) {
              if (v.isNotEmpty) show(v.first);
            },
          ),
        ),
        Divider(height: 1, color: p.border),
        Expanded(
          child: switch (view) {
            _View.games => const _GamesView(),
            _View.report => const _ReportView(),
            _View.analysis => _AnalysisView(currentKey: _currentKey),
          },
        ),
        Container(color: p.panelHigh, child: const _Controls()),
      ],
    );
  }
}

/// The analysis action that fits the game's state: analyse, resume, stop,
/// or a deeper review.
class _ReviewAction extends StatelessWidget {
  const _ReviewAction();

  @override
  Widget build(BuildContext context) {
    final a = watchAnalysis(context);
    final r = a.review;
    final deep = a.settings.deepReviewDepth;
    if (a.reviewing) {
      return IconButton(
        tooltip: 'Stop the analysis',
        onPressed: a.cancelReview,
        icon: const Icon(Icons.stop_circle_outlined),
      );
    }
    if (r == null || r.analysedCount == 0) {
      return IconButton(
        tooltip: a.game.length == 0 ? 'Open a game first' : 'Analyse game',
        onPressed: a.game.length == 0 ? null : a.startReview,
        icon: const Icon(Icons.query_stats),
      );
    }
    if (!r.complete) {
      return IconButton(
        tooltip: 'Resume the analysis',
        onPressed: a.startReview,
        icon: const Icon(Icons.play_circle_outline),
      );
    }
    return IconButton(
      tooltip: r.depth < deep
          ? 'Deeper review (depth $deep, slower)'
          : 'Analysed at depth ${r.depth}',
      onPressed: r.depth < deep ? () => a.startReview(depth: deep) : null,
      icon: const Icon(Icons.refresh),
    );
  }
}

/// Recent games of the loaded profile, and the other ways to open a game.
class _GamesView extends StatelessWidget {
  const _GamesView();

  @override
  Widget build(BuildContext context) {
    final p = PlyPalette.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your games', style: theme.textTheme.titleSmall),
              Text(
                'Choose the site and type a username in the bar at the top, '
                'or open a PGN below. Click a game to analyse it.',
                style: theme.textTheme.bodySmall?.copyWith(color: p.muted),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: p.border),
        const Expanded(child: OnlineGameList()),
        Divider(height: 1, color: p.border),
        Padding(
          padding: const EdgeInsets.all(6),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 2,
            children: [
              TextButton.icon(
                onPressed: () => pastePgn(context),
                icon: const Icon(Icons.content_paste, size: 18),
                label: const Text('Paste PGN'),
              ),
              TextButton.icon(
                onPressed: () => pickPgnFile(context),
                icon: const Icon(Icons.file_open_outlined, size: 18),
                label: const Text('Open PGN'),
              ),
              Tooltip(
                message: 'Set up a position from a FEN string',
                child: TextButton.icon(
                  onPressed: () => loadFen(context),
                  icon: const Icon(Icons.grid_on, size: 18),
                  label: const Text('FEN'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The game's results: graph, accuracy, classification counts, key moments
/// and learning points. Only what the analysis actually produced is shown.
class _ReportView extends StatelessWidget {
  const _ReportView();

  @override
  Widget build(BuildContext context) {
    final a = watchAnalysis(context);
    final theme = Theme.of(context);
    final p = PlyPalette.of(context);
    final r = a.review;
    final has = r != null && r.analysedCount > 0;
    final hide = a.settings.hideClassifications;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      children: [
        const _GameTitle(),
        const SizedBox(height: 8),
        if (a.reviewing || !(r?.complete ?? false)) ...[
          const _AnalyseButton(),
          const SizedBox(height: 10),
        ],
        if (has) ...[
          Container(
            height: 96,
            padding: const EdgeInsets.all(4),
            decoration: p.cardBox(),
            child: Tooltip(
              message:
                  'White\'s winning chances over the game. Dots mark '
                  'inaccuracies, mistakes and blunders; click to jump there.',
              child: EvalGraph(
                review: r,
                moves: a.moveReviews,
                current: a.onWhatIf ? a.branch : a.ply,
                onTap: a.goToGame,
              ),
            ),
          ),
          const SizedBox(height: 10),
          const _Accuracies(),
          if (!hide) ...[const SizedBox(height: 10), const _ClassTable()],
        ],
        const SizedBox(height: 4),
        const _GameReview(summary: false),
        if (!has && a.game.length == 0)
          Text(
            'Open a game from Your games (the arrow above).',
            style: theme.textTheme.bodySmall?.copyWith(color: p.muted),
          ),
      ],
    );
  }
}

String _playerName(ChessGame g, Side s) {
  final n = g.headers[s == Side.white ? 'White' : 'Black'];
  return n == null || n == '?' ? (s == Side.white ? 'White' : 'Black') : n;
}

/// Each player's accuracy: White on a light cell, Black on a dark one.
class _Accuracies extends StatelessWidget {
  const _Accuracies();

  @override
  Widget build(BuildContext context) {
    final a = watchAnalysis(context);
    final theme = Theme.of(context);
    final p = PlyPalette.of(context);
    final partial = !(a.review?.complete ?? false);
    Widget cell(Side s) {
      final acc = summarize(a.moveReviews, s).accuracy;
      final white = s == Side.white;
      final fg = white ? const Color(0xFF14181E) : const Color(0xFFE6E9EE);
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          color: white ? const Color(0xFFE3E7EC) : const Color(0xFF0B0E12),
          child: Column(
            children: [
              Text(
                _playerName(a.game, s),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: fg.withValues(alpha: 0.7),
                ),
              ),
              Text(
                acc == null ? '–' : '${acc.toStringAsFixed(1)}%',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: p.cardBox(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Tooltip(
              message: accuracyNote,
              child: Text(
                partial ? 'Accuracy (partial analysis)' : 'Accuracy',
                style: theme.textTheme.titleSmall,
              ),
            ),
          ),
          Row(children: [cell(Side.white), cell(Side.black)]),
        ],
      ),
    );
  }
}

/// How many moves of each classification each player made. Clicking a
/// count shows that player's next move of that kind.
class _ClassTable extends StatelessWidget {
  const _ClassTable();

  @override
  Widget build(BuildContext context) {
    final a = watchAnalysis(context);
    final theme = Theme.of(context);
    final p = PlyPalette.of(context);
    final o = a.settings.classOptions;
    final w = summarize(a.moveReviews, Side.white).counts;
    final b = summarize(a.moveReviews, Side.black).counts;
    final classes = [
      if (o.brilliant) MoveClass.brilliant,
      if (o.critical) MoveClass.critical,
      MoveClass.best,
      MoveClass.excellent,
      MoveClass.good,
      MoveClass.inaccuracy,
      MoveClass.mistake,
      MoveClass.blunder,
      if (o.theory) MoveClass.theory,
      if (w[MoveClass.forced]! + b[MoveClass.forced]! > 0) MoveClass.forced,
    ];

    void next(MoveClass c, Side s) {
      final ms = [
        for (final m in a.moveReviews)
          if (m != null && m.cls == c && m.mover == s) m,
      ];
      if (ms.isEmpty) return;
      final shown = a.onWhatIf ? -1 : a.ply - 1;
      final m = ms.firstWhere((m) => m.ply > shown, orElse: () => ms.first);
      a.goToGame(m.ply + 1);
    }

    final label = theme.textTheme.labelMedium?.copyWith(color: p.muted);
    Widget count(MoveClass c, Side s, int n) => Expanded(
      child: Tooltip(
        message: n == 0
            ? ''
            : 'Show ${_playerName(a.game, s)}\'s next ${c.label.toLowerCase()} '
                  'move',
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: n == 0 ? null : () => next(c, s),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(
              '$n',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: n == 0 ? p.muted : classColor(c),
                fontWeight: n == 0 ? null : FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: p.cardBox(),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(width: 96),
              Expanded(
                child: Text(
                  _playerName(a.game, Side.white),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: label,
                ),
              ),
              const SizedBox(width: 28),
              Expanded(
                child: Text(
                  _playerName(a.game, Side.black),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: label,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          for (final c in classes)
            Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    c.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: classColor(c),
                    ),
                  ),
                ),
                count(c, Side.white, w[c]!),
                ClassBadge(c, size: 20),
                const SizedBox(width: 8),
                count(c, Side.black, b[c]!),
              ],
            ),
        ],
      ),
    );
  }
}

/// The shown move's rating and what to play next, fixed at the top; below,
/// the live engine and the moves with any what-if line.
class _AnalysisView extends StatelessWidget {
  const _AnalysisView({required this.currentKey});
  final GlobalKey currentKey;

  @override
  Widget build(BuildContext context) {
    final p = PlyPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(10, 10, 10, 6),
          child: _MoveFeedback(),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(10, 0, 10, 8),
          child: _NextMove(),
        ),
        Divider(height: 1, color: p.border),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            children: [
              const _EnginePanel(),
              const SizedBox(height: 8),
              _MoveList(currentKey: currentKey),
            ],
          ),
        ),
      ],
    );
  }
}

/// Stockfish's choice in the shown position, with its line, and how the
/// game's own move compared when it went another way.
class _NextMove extends StatelessWidget {
  const _NextMove();

  @override
  Widget build(BuildContext context) {
    final a = watchAnalysis(context);
    final theme = Theme.of(context);
    final p = PlyPalette.of(context);
    final pos = a.position;
    final here = a.analysisAt(a.ply);
    if (a.preview != null || pos.isGameOver || here?.bestMove == null) {
      return const SizedBox.shrink();
    }
    final muted = theme.textTheme.bodySmall?.copyWith(color: p.muted);
    final sans = uciLineToSan(
      pos,
      here!.pv.isEmpty ? [here.bestMove!] : here.pv,
    );
    if (sans.isEmpty) return const SizedBox.shrink();
    final next = a.ply < a.line.length ? a.line.plies[a.ply] : null;
    final went = next != null && next.uci != here.bestMove
        ? a.reviewAt(a.ply + 1)
        : null;
    final who = pos.turn == Side.white ? 'White' : 'Black';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: p.cardBox(),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Best for $who now: ',
                      style: theme.textTheme.bodyMedium,
                    ),
                    MoveText(
                      sans.first,
                      simple: a.settings.simpleNotation,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '  ${here.eval.label} · ${evalWords(here.eval)}',
                      style: muted,
                    ),
                  ],
                ),
                Text(
                  formatLine(pos, sans.take(6).toList()),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: muted,
                ),
                if (went != null && !a.settings.hideClassifications)
                  Text(
                    '${a.isWhatIf(a.ply + 1) ? 'Your line' : 'The game'} '
                    'went ${went.san} instead (${went.cls.label}, '
                    '${went.after.label}).',
                    style: muted,
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: here.pv.isEmpty ? null : () => a.previewLine(here.pv, 0),
            child: const Text('Show'),
          ),
        ],
      ),
    );
  }
}
