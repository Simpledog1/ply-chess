import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';

import '../analysis/review.dart';
import '../chess/chess_game.dart';
import '../engine/engine_service.dart';
import '../storage/game_store.dart';
import '../storage/settings.dart';
import 'analysis_controller.dart';
import 'analysis_panels.dart';
import 'board/chess_board.dart';
import 'board/eval_bar.dart';
import 'games_screen.dart' show editGameDetails;
import 'import_export.dart';
import 'move_text.dart';
import 'review_screen.dart';
import 'services.dart';
import 'theme.dart';

/// Rebuilds every widget below that calls [watchAnalysis] when the analysis,
/// settings or engine state changes (const widgets included).
class _Watch extends InheritedNotifier<Listenable> {
  const _Watch({required super.notifier, required super.child});
}

AnalysisController watchAnalysis(BuildContext context) {
  context.dependOnInheritedWidgetOfExactType<_Watch>();
  return Services.of(context).analysis;
}

class AnalyzeScreen extends StatefulWidget {
  const AnalyzeScreen({super.key});

  @override
  State<AnalyzeScreen> createState() => _AnalyzeScreenState();
}

class _AnalyzeScreenState extends State<AnalyzeScreen> {
  Listenable? _changes;

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    _changes ??= Listenable.merge([s.analysis, s.settings, s.engine]);
    return _Watch(
      notifier: _changes,
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth > 700 && c.maxWidth > c.maxHeight;
              if (wide) {
                return Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Center(
                          child: _BoardArea(maxHeight: c.maxHeight - 24),
                        ),
                      ),
                      const SizedBox(width: 16),
                      const SizedBox(width: 380, child: _Panel(wide: true)),
                    ],
                  ),
                );
              }
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                    child: _BoardArea(maxHeight: c.maxHeight * 0.6),
                  ),
                  const Expanded(child: _Panel(wide: false)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

Future<void> addToRevisit(
  BuildContext context,
  String fen, {
  String? gameId,
  int? ply,
}) async {
  final c = TextEditingController();
  final note = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Revisit later'),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Note (optional)'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, c.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (note == null || !context.mounted) return;
  await Services.of(context).store.addPosition(
    SavedPosition(
      id: newId(),
      fen: fen,
      note: note.trim(),
      addedAt: DateTime.now(),
      gameId: gameId,
      ply: ply,
    ),
  );
  if (context.mounted) snack(context, 'Added to positions to revisit');
}

class _BoardArea extends StatelessWidget {
  const _BoardArea({required this.maxHeight});
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final a = watchAnalysis(context);
    return LayoutBuilder(
      builder: (context, c) {
        const barW = 18.0, gap = 4.0, tab = 30.0;
        final double size = math.max(
          160.0,
          math.min(
            c.maxWidth.isFinite ? c.maxWidth - barW - gap : 600.0,
            maxHeight - 2 * tab,
          ),
        );
        final pos = a.shownPosition;
        final last = a.preview != null
            ? a.previewUcis![a.previewIndex]
            : (a.ply > 0 ? a.game.plies[a.ply - 1].uci : null);
        final lastMove = last == null
            ? null
            : (
                Square.fromName(last.substring(0, 2)),
                Square.fromName(last.substring(2, 4)),
              );

        final arrows = <BoardArrow>[];
        if (a.preview == null && s.settings.arrows != ArrowMode.off) {
          final lines = a.liveHere?.lines ?? const [];
          final firsts = lines.isNotEmpty
              ? [for (final l in lines) l.pv.firstOrNull]
              : [a.reviewHere?.bestMove];
          final shown = s.settings.arrows == ArrowMode.all
              ? firsts
              : firsts.take(1);
          for (final (i, u) in shown.indexed) {
            if (u == null || u.length < 4) continue;
            arrows.add(
              BoardArrow(
                Square.fromName(u.substring(0, 2)),
                Square.fromName(u.substring(2, 4)),
                BoardColors.arrow.withValues(alpha: i == 0 ? 0.85 : 0.45),
              ),
            );
          }
        }
        final mr = a.preview == null && !s.settings.hideClassifications
            ? a.lastMoveReview
            : null;
        final badge = mr != null && lastMove != null
            ? (lastMove.$2, ClassBadge(mr.cls, size: 22))
            : null;

        return SizedBox(
          width: size + barW + gap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PlayerTab(side: a.orientation.opposite, top: true, height: tab),
              Row(
                children: [
                  SizedBox(
                    height: size,
                    child: EvalBar(
                      eval: a.currentEval,
                      orientation: a.orientation,
                      width: barW,
                    ),
                  ),
                  const SizedBox(width: gap),
                  SizedBox(
                    width: size,
                    child: ChessBoard(
                      position: pos,
                      orientation: a.orientation,
                      lastMove: lastMove,
                      arrows: arrows,
                      badge: badge,
                      showCoordinates: s.settings.showCoordinates,
                      onMove: a.preview != null || a.reviewing
                          ? null
                          : (m) {
                              final previous = a.userMove(m);
                              if (previous != null) {
                                final at = a.ply - 1;
                                snack(
                                  context,
                                  'Later moves replaced',
                                  action: SnackBarAction(
                                    label: 'Undo',
                                    onPressed: () => a.restore(previous, at),
                                  ),
                                );
                              }
                            },
                    ),
                  ),
                ],
              ),
              _PlayerTab(side: a.orientation, top: false, height: tab),
            ],
          ),
        );
      },
    );
  }
}

/// Player label tab above/below the board, as in the reference design.
class _PlayerTab extends StatelessWidget {
  const _PlayerTab({
    required this.side,
    required this.top,
    required this.height,
  });
  final Side side;
  final bool top;
  final double height;

  @override
  Widget build(BuildContext context) {
    final a = watchAnalysis(context);
    final p = PlyPalette.of(context);
    final h = a.game.headers[side == Side.white ? 'White' : 'Black'];
    final name = (h == null || h == '?')
        ? (side == Side.white ? 'White' : 'Black')
        : h;
    final elo = a.game.headers[side == Side.white ? 'WhiteElo' : 'BlackElo'];
    final edge = materialEdge(a.shownPosition.board, side);
    final toMove = a.shownPosition.turn == side && !a.shownPosition.isGameOver;
    const r = Radius.circular(6);
    return SizedBox(
      height: height,
      child: Row(
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 110, maxWidth: 230),
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.panelHigh,
              borderRadius: top
                  ? const BorderRadius.only(topLeft: r, topRight: r)
                  : const BorderRadius.only(bottomLeft: r, bottomRight: r),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (toMove)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(
                      Icons.circle,
                      size: 7,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                Flexible(
                  child: Text(
                    elo == null || elo == '?' ? name : '$name ($elo)',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Captured material on a light pill so black pieces stay visible.
          if (edge.extra.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: BoardColors.light,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final e in edge.extra.entries)
                    for (var i = 0; i < e.value; i++)
                      PieceImage(
                        Piece(color: side.opposite, role: e.key),
                        size: 15,
                      ),
                ],
              ),
            ),
          if (edge.points > 0)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                '+${edge.points}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _Panel extends StatefulWidget {
  const _Panel({required this.wide});
  final bool wide;

  @override
  State<_Panel> createState() => _PanelState();
}

class _PanelState extends State<_Panel> {
  final _currentKey = GlobalKey();
  final _scroll = ScrollController();
  int _lastPly = -1;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = watchAnalysis(context);
    final p = PlyPalette.of(context);
    if (a.ply != _lastPly) {
      _lastPly = a.ply;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _currentKey.currentContext;
        if (a.ply == 0 && _scroll.hasClients) {
          // Back at the start: show the header and load box again.
          _scroll.animateTo(
            0,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          );
        } else if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 150),
            alignment: 0.5,
          );
        }
      });
    }
    final content = Column(
      children: [
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.all(8),
            children: [
              const _Header(),
              const SizedBox(height: 8),
              const _IconRow(),
              const SizedBox(height: 8),
              const LoadCard(),
              const SizedBox(height: 8),
              const _AnalyseButton(),
              const SizedBox(height: 8),
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
        ),
        const _Controls(),
      ],
    );
    if (!widget.wide) return content;
    return Container(
      decoration: BoxDecoration(
        color: p.panel,
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final a = watchAnalysis(context);
    final title = a.saved?.title;
    final opening = a.openingName;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: plyBlue,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          const Text(
            'Game Analysis',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (title != null || opening != null)
            Text(
              [?title, ?opening].join(' · '),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 12),
            ),
        ],
      ),
    );
  }
}

class _IconRow extends StatelessWidget {
  const _IconRow();

  @override
  Widget build(BuildContext context) {
    final a = watchAnalysis(context);
    final p = PlyPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: p.panelHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'Flip board',
            onPressed: a.flip,
            icon: const Icon(Icons.sync),
          ),
          IconButton(
            tooltip: 'Analysis settings',
            onPressed: () => showAnalysisSettings(context),
            icon: const Icon(Icons.settings),
          ),
          IconButton(
            tooltip: 'Share game',
            onPressed: () => showShareGame(context),
            icon: const Icon(Icons.share),
          ),
          IconButton(
            tooltip: a.savedId == null ? 'Save to Games' : 'Save changes',
            onPressed: () async {
              await a.save();
              if (context.mounted) snack(context, 'Saved to Games');
            },
            icon: Badge(
              isLabelVisible: a.dirty && a.savedId != null,
              smallSize: 7,
              child: Icon(
                a.savedId == null
                    ? Icons.bookmark_add_outlined
                    : Icons.bookmark,
              ),
            ),
          ),
          _MoreMenu(a: a),
        ],
      ),
    );
  }
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({required this.a});
  final AnalysisController a;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More',
      onSelected: (v) async {
        switch (v) {
          case 'details':
            // Save unsaved moves first so editing details cannot discard them.
            final saved = a.dirty || a.saved == null
                ? await a.save()
                : a.saved!;
            if (!context.mounted) return;
            await editGameDetails(context, saved);
          case 'copy':
            await a.save(asNew: true);
            if (context.mounted) snack(context, 'Saved as a new game');
          case 'revisit':
            await addToRevisit(
              context,
              a.position.fen,
              gameId: a.savedId,
              ply: a.ply,
            );
          case 'file':
            await pickPgnFile(context);
          case 'new':
            a.newGame();
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'file', child: Text('Open PGN file')),
        PopupMenuItem(value: 'details', child: Text('Edit game details')),
        PopupMenuItem(value: 'copy', child: Text('Save as new game')),
        PopupMenuItem(
          value: 'revisit',
          child: Text('Revisit this position later'),
        ),
        PopupMenuItem(value: 'new', child: Text('New game')),
      ],
    );
  }
}

class _AnalyseButton extends StatelessWidget {
  const _AnalyseButton();

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final a = watchAnalysis(context);
    final p = PlyPalette.of(context);
    final theme = Theme.of(context);
    final r = a.review;
    final style = FilledButton.styleFrom(
      backgroundColor: p.button,
      foregroundColor: p.text,
      minimumSize: const Size.fromHeight(46),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
    if (a.reviewing) {
      final done = r?.analysedCount ?? 0, total = a.game.length + 1;
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        decoration: BoxDecoration(
          color: p.button,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Analysing at depth ${s.settings.reviewDepth} · '
                    '$done/$total positions',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(value: done / total),
                ],
              ),
            ),
            TextButton(onPressed: a.cancelReview, child: const Text('Stop')),
          ],
        ),
      );
    }
    if (r == null || r.analysedCount == 0) {
      return FilledButton.icon(
        style: style,
        onPressed: a.game.length == 0 ? null : a.startReview,
        icon: const Icon(Icons.query_stats),
        label: const Text('Analyse', style: TextStyle(fontSize: 16)),
      );
    }
    final w = summarize(a.moveReviews, Side.white);
    final b = summarize(a.moveReviews, Side.black);
    Widget side(String name, SideSummary x) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: theme.textTheme.labelMedium),
          Text(
            x.accuracy == null ? '–' : '${x.accuracy!.toStringAsFixed(1)}%',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (!s.settings.hideClassifications)
            Row(
              children: [
                for (final c in [
                  MoveClass.inaccuracy,
                  MoveClass.mistake,
                  MoveClass.blunder,
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      '${x.counts[c]}${classSymbol(c)}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: classColor(c),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: p.button,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!r.complete)
            Text(
              'Partial analysis: ${r.analysedCount}/${r.positions.length} '
              'positions',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          Row(
            children: [
              side('White accuracy', w),
              side('Black accuracy', b),
              Column(
                children: [
                  FilledButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ReviewScreen(),
                      ),
                    ),
                    child: const Text('Report'),
                  ),
                  if (!r.complete || r.depth != s.settings.reviewDepth)
                    TextButton(
                      onPressed: a.startReview,
                      child: Text(r.complete ? 'Re-run' : 'Resume'),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EnginePanel extends StatelessWidget {
  const _EnginePanel();

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final a = watchAnalysis(context);
    final theme = Theme.of(context);
    final p = PlyPalette.of(context);
    final pos = a.position;
    final muted = theme.textTheme.bodySmall?.copyWith(color: p.muted);
    Widget box(Widget child) => Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: p.panelHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );

    if (pos.isGameOver) {
      final text = pos.isCheckmate
          ? 'Checkmate — ${pos.turn == Side.white ? 'Black' : 'White'} wins'
          : pos.isStalemate
          ? 'Stalemate — draw'
          : 'Draw by insufficient material';
      return box(
        Row(
          children: [
            const Icon(Icons.flag_outlined, size: 18),
            const SizedBox(width: 8),
            Text(text),
          ],
        ),
      );
    }
    final header = Row(
      children: [
        Expanded(
          child: Text(
            'Engine',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (a.engineOn && (a.liveHere == null || !a.liveHere!.finished))
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        Switch(
          value: a.engineOn,
          onChanged: a.reviewing ? null : (_) => a.toggleEngine(),
        ),
      ],
    );
    if (a.engineError != null && !a.engineOn) {
      return box(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            Text(
              'Engine unavailable: ${a.engineError}',
              style: muted?.copyWith(color: theme.colorScheme.error),
            ),
          ],
        ),
      );
    }
    if (!a.engineOn) {
      final r = a.reviewHere;
      final best = r?.bestMove == null
          ? ''
          : ' · best ${uciLineToSan(pos, [r!.bestMove!]).firstOrNull ?? r.bestMove}';
      return box(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            Text(
              r == null
                  ? 'Turn on to analyse this position with Stockfish.'
                  : 'Analysis: ${r.eval.label} · depth ${r.depth}$best',
              style: muted,
            ),
            const SizedBox(height: 4),
          ],
        ),
      );
    }
    final r = a.liveHere;
    final starting = s.engine.status == EngineStatus.starting;
    final limit = s.settings.timeLimitOn
        ? '${s.settings.timeLimitSec}s'
        : '${s.settings.liveDepth}';
    final depthText = r == null
        ? (starting ? 'Starting engine…' : 'Thinking…')
        : r.complete
        ? 'depth ${r.depth}'
        : r.finished
        ? 'depth ${r.depth} · stopped (partial)'
        : 'depth ${r.depth}/$limit';
    return box(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          Text(
            '${s.engine.engineName ?? 'Stockfish'} · $depthText',
            style: muted,
          ),
          if (r != null)
            for (final line in r.lines)
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 8),
                child: _PvLine(
                  eval: line.eval.label,
                  pv: line.pv,
                  from: pos,
                  simple: s.settings.simpleNotation,
                ),
              ),
          const SizedBox(height: 4),
          Text(
            '+ favours White, − favours Black',
            style: muted?.copyWith(fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _PvLine extends StatelessWidget {
  const _PvLine({
    required this.eval,
    required this.pv,
    required this.from,
    required this.simple,
  });
  final String eval;
  final List<String> pv;
  final Position from;
  final bool simple;

  @override
  Widget build(BuildContext context) {
    final a = watchAnalysis(context);
    final sans = uciLineToSan(from, pv, max: 12);
    final theme = Theme.of(context);
    var n = from.fullmoves;
    var white = from.turn == Side.white;
    final items = <Widget>[
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        margin: const EdgeInsets.only(right: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          eval,
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    ];
    for (var i = 0; i < sans.length; i++) {
      final prefix = white ? '$n. ' : (i == 0 ? '$n… ' : '');
      if (!white) n++;
      white = !white;
      items.add(
        InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => a.previewLine(pv, i),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
            child: MoveText(
              sans[i],
              simple: simple,
              prefix: prefix,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ),
      );
    }
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: items);
  }
}

class _PreviewBanner extends StatelessWidget {
  const _PreviewBanner();

  @override
  Widget build(BuildContext context) {
    final a = watchAnalysis(context);
    final theme = Theme.of(context);
    final sans = a.previewSans!;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Engine line · ${a.previewIndex + 1}/${sans.length}',
                  style: theme.textTheme.labelLarge,
                ),
              ),
              IconButton(
                tooltip: 'Previous',
                onPressed: () => a.previewStep(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: 'Next',
                onPressed: () => a.previewStep(1),
                icon: const Icon(Icons.chevron_right),
              ),
              TextButton(onPressed: a.playPreview, child: const Text('Play')),
              IconButton(
                tooltip: 'Close',
                onPressed: a.closePreview,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Wrap(
            children: [
              for (var i = 0; i < sans.length; i++)
                InkWell(
                  onTap: () => a.previewStep(i - a.previewIndex),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    decoration: i == a.previewIndex
                        ? BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.3,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          )
                        : null,
                    child: MoveText(
                      sans[i],
                      simple: a.settings.simpleNotation,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MoveCard extends StatelessWidget {
  const _MoveCard(this.m);
  final MoveReview m;

  @override
  Widget build(BuildContext context) {
    final a = watchAnalysis(context);
    final theme = Theme.of(context);
    final p = PlyPalette.of(context);
    final color = classColor(m.cls);
    final moveNo =
        '${a.game.positionAt(m.ply).fullmoves}${m.mover == Side.white ? '.' : '…'} ';
    return Container(
      decoration: BoxDecoration(
        color: p.panelHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClassBadge(m.cls, size: 22),
              const SizedBox(width: 8),
              MoveText(
                m.san,
                simple: a.settings.simpleNotation,
                prefix: moveNo,
                suffix: classSymbol(m.cls),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(width: 8),
              Text(
                m.cls.label,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '${m.before.label} → ${m.after.label}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(m.explanation, style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                m.cls == MoveClass.theory
                    ? 'Opening book'
                    : 'Engine finding · Stockfish depth ${m.depth}',
                style: theme.textTheme.labelSmall?.copyWith(color: p.muted),
              ),
              for (final t in m.tags)
                Chip(
                  label: Text(t.label),
                  labelStyle: theme.textTheme.labelSmall,
                  padding: EdgeInsets.zero,
                ),
            ],
          ),
          if (m.cls.isError)
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => a.goTo(m.ply),
                  icon: const Icon(Icons.lightbulb_outline, size: 18),
                  label: const Text('Show best move'),
                ),
                TextButton.icon(
                  onPressed: () => addToRevisit(
                    context,
                    a.game.positionAt(m.ply).fen,
                    gameId: a.savedId,
                    ply: m.ply,
                  ),
                  icon: const Icon(Icons.push_pin_outlined, size: 18),
                  label: const Text('Revisit'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _MoveList extends StatelessWidget {
  const _MoveList({required this.currentKey});
  final GlobalKey currentKey;

  @override
  Widget build(BuildContext context) {
    final a = watchAnalysis(context);
    final theme = Theme.of(context);
    final p = PlyPalette.of(context);
    final hide = a.settings.hideClassifications;
    final g = a.game;
    if (g.length == 0) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          'Play moves on the board, or load a game above.',
          style: theme.textTheme.bodySmall?.copyWith(color: p.muted),
        ),
      );
    }
    final items = <Widget>[];
    for (var i = 0; i < g.length; i++) {
      final pos = g.positionAt(i);
      if (pos.turn == Side.white || i == 0) {
        items.add(
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 3),
            child: Text(
              '${pos.fullmoves}${pos.turn == Side.white ? '.' : '…'}',
              style: theme.textTheme.bodySmall?.copyWith(color: p.muted),
            ),
          ),
        );
      }
      final mr = hide || i >= a.moveReviews.length ? null : a.moveReviews[i];
      final current = a.ply == i + 1;
      final highlight =
          mr != null &&
          (mr.cls.isError ||
              mr.cls == MoveClass.brilliant ||
              mr.cls == MoveClass.critical);
      items.add(
        InkWell(
          key: current ? currentKey : null,
          borderRadius: BorderRadius.circular(4),
          onTap: () => a.goTo(i + 1),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: current
                ? BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(4),
                  )
                : null,
            child: MoveText(
              g.plies[i].san,
              simple: a.settings.simpleNotation,
              suffix: mr == null ? '' : classSymbol(mr.cls),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: current ? FontWeight.w700 : null,
                color: highlight ? classColor(mr.cls) : null,
              ),
            ),
          ),
        ),
      );
    }
    final result = g.result;
    if (result != '*') {
      items.add(
        Padding(
          padding: const EdgeInsets.only(left: 6, top: 2),
          child: Text(result, style: theme.textTheme.bodyMedium),
        ),
      );
    }
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: items);
  }
}

class _Controls extends StatelessWidget {
  const _Controls();

  @override
  Widget build(BuildContext context) {
    final a = watchAnalysis(context);
    final p = PlyPalette.of(context);
    return Container(
      color: p.panelHigh,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            tooltip: 'First move',
            onPressed: a.ply > 0 ? () => a.goTo(0) : null,
            icon: const Icon(Icons.first_page, size: 30),
          ),
          IconButton(
            tooltip: 'Previous move',
            onPressed: a.ply > 0 ? () => a.goTo(a.ply - 1) : null,
            icon: const Icon(Icons.arrow_back, size: 28),
          ),
          IconButton(
            tooltip: a.autoplaying ? 'Pause' : 'Play through the game',
            onPressed: a.game.length == 0 ? null : a.toggleAutoplay,
            icon: Icon(
              a.autoplaying ? Icons.pause : Icons.play_arrow_outlined,
              size: 30,
            ),
          ),
          IconButton(
            tooltip: 'Next move',
            onPressed: a.ply < a.game.length ? () => a.goTo(a.ply + 1) : null,
            icon: const Icon(Icons.arrow_forward, size: 28),
          ),
          IconButton(
            tooltip: 'Last move',
            onPressed: a.ply < a.game.length
                ? () => a.goTo(a.game.length)
                : null,
            icon: const Icon(Icons.last_page, size: 30),
          ),
        ],
      ),
    );
  }
}
