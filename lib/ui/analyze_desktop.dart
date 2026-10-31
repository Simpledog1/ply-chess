part of 'analyze_screen.dart';

/// Three columns for desktop windows: recent games | board | analysis.
/// Everything about the open game (move rating, moves, review) stays on
/// this one screen.
class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({required this.width});
  final double width;

  @override
  Widget build(BuildContext context) {
    final p = PlyPalette.of(context);
    final roomy = width >= 1400;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: roomy ? 300 : 256,
            decoration: p.panelBox(),
            clipBehavior: Clip.antiAlias,
            child: const _GamesPanel(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) =>
                        Center(child: _BoardArea(maxHeight: c.maxHeight)),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: p.panelBox(radius: 10),
                  clipBehavior: Clip.antiAlias,
                  child: const _Controls(),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: roomy ? 430 : 370,
            decoration: p.panelBox(),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Row(
            children: [
              Icon(Icons.history, size: 18, color: p.muted),
              const SizedBox(width: 8),
              Text('Recent games', style: theme.textTheme.titleSmall),
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

/// Right column: game title and actions, the Analyse button, the rating of
/// the shown move, the move list and the game review (collapsible).
class _SidePanel extends StatefulWidget {
  const _SidePanel();

  @override
  State<_SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<_SidePanel> {
  final _currentKey = GlobalKey();
  String _lastShown = '';

  /// Null until the user toggles it: open by default on taller windows.
  bool? _reviewOpenChoice;

  @override
  Widget build(BuildContext context) {
    final a = watchAnalysis(context);
    // Scroll the shown move (game or what-if) into view when it changes.
    final shown = '${a.ply} ${a.onWhatIf} ${a.variation?.length}';
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
    final p = PlyPalette.of(context);
    final theme = Theme.of(context);
    final engineBox = a.engineOn || a.engineError != null;
    final reviewOpen =
        _reviewOpenChoice ?? MediaQuery.sizeOf(context).height >= 860;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 6),
          child: Row(
            children: [
              const Expanded(child: _GameTitle()),
              const _IconRow(compact: true),
            ],
          ),
        ),
        if (a.reviewing || !(a.review?.complete ?? false))
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: _AnalyseButton(),
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: _MoveFeedback(),
        ),
        Divider(height: 1, color: p.border),
        Expanded(
          flex: 5,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            children: [
              if (engineBox) ...[
                const _EnginePanel(),
                const SizedBox(height: 8),
              ],
              _MoveList(currentKey: _currentKey),
              if (!engineBox) ...[
                const SizedBox(height: 6),
                const _EnginePanel(),
              ],
            ],
          ),
        ),
        Divider(height: 1, color: p.border),
        InkWell(
          onTap: () => setState(() => _reviewOpenChoice = !reviewOpen),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            child: Row(
              children: [
                Icon(Icons.assessment_outlined, size: 18, color: p.muted),
                const SizedBox(width: 8),
                Text('Game review', style: theme.textTheme.titleSmall),
                if (a.review?.complete ?? false) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.check_circle,
                    size: 14,
                    color: classColor(MoveClass.best),
                  ),
                ],
                const Spacer(),
                Icon(
                  reviewOpen ? Icons.expand_more : Icons.expand_less,
                  semanticLabel: reviewOpen
                      ? 'Collapse game review'
                      : 'Expand game review',
                ),
              ],
            ),
          ),
        ),
        if (reviewOpen)
          Expanded(
            flex: 6,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: const [_GameReview()],
            ),
          ),
      ],
    );
  }
}
