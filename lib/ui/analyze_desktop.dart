part of 'analyze_screen.dart';

/// Three columns for desktop windows: recent games | board | analysis.
class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = PlyPalette.of(context);
    final panel = BoxDecoration(
      color: p.panel,
      borderRadius: BorderRadius.circular(10),
    );
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 300,
            decoration: panel,
            clipBehavior: Clip.antiAlias,
            child: const _GamesPanel(),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: Center(child: _BoardArea(maxHeight: height - 90)),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: const _Controls(),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 390,
            decoration: panel,
            clipBehavior: Clip.antiAlias,
            child: const _SidePanel(),
          ),
        ],
      ),
    );
  }
}

class _GamesPanel extends StatelessWidget {
  const _GamesPanel();

  @override
  Widget build(BuildContext context) {
    final p = PlyPalette.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: p.panelHigh,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Text('Recent games', style: theme.textTheme.titleSmall),
        ),
        const Expanded(child: OnlineGameList()),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(6),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 4,
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
              TextButton.icon(
                onPressed: () => loadFen(context),
                icon: const Icon(Icons.grid_on, size: 18),
                label: const Text('FEN'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SidePanel extends StatefulWidget {
  const _SidePanel();

  @override
  State<_SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<_SidePanel> {
  final _currentKey = GlobalKey();
  int _lastPly = -1;

  @override
  Widget build(BuildContext context) {
    final a = watchAnalysis(context);
    if (a.ply != _lastPly) {
      _lastPly = a.ply;
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
    final p = PlyPalette.of(context);
    final theme = Theme.of(context);
    final title = [
      ?a.saved?.title ?? _players(a.game),
      ?a.openingName,
    ].join(' · ');
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: p.panelHigh,
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title.isEmpty ? 'Analysis' : title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                const _IconRow(compact: true),
              ],
            ),
          ),
          const Padding(padding: EdgeInsets.all(8), child: _AnalyseButton()),
          TabBar(
            tabs: [
              const Tab(text: 'Moves', height: 36),
              Tab(
                height: 36,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Review'),
                    if (a.review?.complete ?? false) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.check_circle,
                        size: 14,
                        color: classColor(MoveClass.best),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                ListView(
                  padding: const EdgeInsets.all(8),
                  children: [
                    if (a.preview != null)
                      const _PreviewBanner()
                    else
                      const _EnginePanel(),
                    if (a.lastMoveReview != null &&
                        a.preview == null &&
                        !a.settings.hideClassifications) ...[
                      const SizedBox(height: 8),
                      _MoveCard(a.lastMoveReview!),
                    ],
                    const SizedBox(height: 8),
                    _MoveList(currentKey: _currentKey),
                  ],
                ),
                const _ReviewSummary(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String? _players(ChessGame g) {
    final w = g.headers['White'], b = g.headers['Black'];
    if (w == null || w == '?' || b == null || b == '?') return null;
    return '$w vs $b';
  }
}

/// Key mistakes and learning points of the reviewed game.
class _ReviewSummary extends StatelessWidget {
  const _ReviewSummary();

  @override
  Widget build(BuildContext context) {
    final a = watchAnalysis(context);
    final theme = Theme.of(context);
    final p = PlyPalette.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: p.muted);
    final r = a.review;
    if (r == null || r.analysedCount == 0) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          a.game.length == 0
              ? 'Load a game, then press Analyse.'
              : 'Press Analyse to have Stockfish review every move. The '
                    'mistakes and learning points appear here.',
          style: muted,
          textAlign: TextAlign.center,
        ),
      );
    }
    final me =
        a.saved?.myColor ?? GameStore.detectColor(a.game, a.settings.myNames);
    final moves = a.moveReviews;
    final mistakes = criticalMoments([
      for (final m in moves)
        if (m != null && (me == null || m.mover == me)) m,
    ], limit: 6);
    final lessons = groupLessons(findLessons(a.game, r, moves, side: me));
    String moveName(MoveReview m) =>
        '${a.game.positionAt(m.ply).fullmoves}${m.mover == Side.white ? '.' : '…'} ${m.san}';

    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        if (!r.complete)
          Text(
            'Partial analysis (${r.analysedCount}/${r.positions.length} '
            'positions): results cover the analysed part only.',
            style: muted?.copyWith(color: theme.colorScheme.error),
          ),
        Text(
          me == null
              ? 'Both sides · Stockfish depth ${r.depth}'
              : 'Your moves as ${me == Side.white ? 'White' : 'Black'} · '
                    'Stockfish depth ${r.depth}',
          style: muted,
        ),
        const SizedBox(height: 8),
        Text('Key mistakes', style: theme.textTheme.titleSmall),
        if (mistakes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'No inaccuracies, mistakes or blunders found at this depth.',
              style: muted,
            ),
          ),
        for (final m in mistakes) _MistakeCard(m: m, title: moveName(m)),
        const SizedBox(height: 12),
        Text('Learning points', style: theme.textTheme.titleSmall),
        Text(
          'From this game only; each links to the moves it comes from.',
          style: muted,
        ),
        if (lessons.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text('Nothing specific stood out.', style: muted),
          ),
        for (final (kind, items) in lessons)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${kind.label}${items.length > 1 ? ' ×${items.length}' : ''}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                for (final l in items)
                  InkWell(
                    onTap: () => a.goTo(l.ply + 1),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(l.text, style: theme.textTheme.bodySmall),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        if (r.complete && r.depth < a.settings.deepReviewDepth && !a.reviewing)
          OutlinedButton.icon(
            onPressed: () => a.startReview(depth: a.settings.deepReviewDepth),
            icon: const Icon(Icons.manage_search),
            label: Text(
              'Deeper review (depth ${a.settings.deepReviewDepth}, slower)',
            ),
          ),
      ],
    );
  }
}

class _MistakeCard extends StatelessWidget {
  const _MistakeCard({required this.m, required this.title});
  final MoveReview m;
  final String title;

  @override
  Widget build(BuildContext context) {
    final a = watchAnalysis(context);
    final theme = Theme.of(context);
    final p = PlyPalette.of(context);
    final small = theme.textTheme.bodySmall;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 4),
      decoration: BoxDecoration(
        color: p.panelHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: classColor(m.cls), width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClassBadge(m.cls, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '$title${classSymbol(m.cls)}  ${m.cls.label}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text('${m.before.label} → ${m.after.label}', style: small),
            ],
          ),
          if (m.bestSan != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Best: ${m.bestLine}', style: small),
            ),
          if (m.replyLine.isNotEmpty)
            Text('After ${m.san}: ${m.replyLine}', style: small),
          Text(
            m.tags.isEmpty
                ? 'Winning chances ${m.winBefore.round()}% → ${m.winAfter.round()}%'
                : m.tags.map((t) => t.label).join(' · '),
            style: small?.copyWith(color: p.muted),
          ),
          Wrap(
            children: [
              TextButton(
                onPressed: () => a.goTo(m.ply + 1),
                child: const Text('Show move'),
              ),
              TextButton(
                onPressed: () => a.goTo(m.ply),
                child: const Text('Find the best move'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
