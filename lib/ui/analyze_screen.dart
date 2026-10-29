import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../analysis/eval.dart';
import '../analysis/lessons.dart';
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
import 'move_words.dart';
import 'online_game_list.dart';
import 'eval_graph.dart';
import 'services.dart';
import 'theme.dart';

part 'analyze_desktop.dart';
part 'analyze_review.dart';

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
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  /// Keyboard navigation: ←/→ move, Home/End (or ↑/↓) jump, F flip,
  /// Space play/pause, E engine on/off, Backspace take back a what-if move,
  /// Esc back to the game. Ignored while typing or in dialogs.
  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return false;
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    final s = Services.of(context);
    if (s.tab.value != 0) return false;
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus != null &&
        (focus.widget is EditableText ||
            focus.findAncestorWidgetOfExactType<EditableText>() != null)) {
      return false;
    }
    final a = s.analysis;
    switch (e.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        a.goTo(a.ply - 1);
      case LogicalKeyboardKey.arrowRight:
        a.goTo(a.ply + 1);
      case LogicalKeyboardKey.home || LogicalKeyboardKey.arrowUp:
        a.goTo(0);
      case LogicalKeyboardKey.end || LogicalKeyboardKey.arrowDown:
        a.goTo(a.line.length);
      case LogicalKeyboardKey.keyF when e is KeyDownEvent:
        a.flip();
      case LogicalKeyboardKey.space when e is KeyDownEvent:
        if (a.line.length > 0) a.toggleAutoplay();
      case LogicalKeyboardKey.keyE when e is KeyDownEvent:
        if (!a.reviewing) a.toggleEngine();
      case LogicalKeyboardKey.backspace when a.variation != null:
        a.undoWhatIf();
      case LogicalKeyboardKey.escape when a.preview != null:
        a.closePreview();
      case LogicalKeyboardKey.escape when a.variation != null:
        a.backToGame();
      default:
        return false;
    }
    return true;
  }

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
              if (c.maxWidth >= desktopWidth) {
                return _DesktopLayout(width: c.maxWidth);
              }
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
            : (a.ply > 0 ? a.line.plies[a.ply - 1].uci : null);
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
                  Container(
                    width: size,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: const [
                        BoxShadow(
                          blurRadius: 18,
                          offset: Offset(0, 6),
                          color: Color(0x40000000),
                        ),
                      ],
                    ),
                    child: ChessBoard(
                      position: pos,
                      orientation: a.orientation,
                      lastMove: lastMove,
                      arrows: arrows,
                      badge: badge,
                      showCoordinates: s.settings.showCoordinates,
                      // What-if moves never touch the game, so they are
                      // fine during a review; free-play edits are not.
                      onMove: a.preview != null || (a.reviewing && a.freePlay)
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
  final _feedbackKey = GlobalKey();
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
        // Keep the rating of the shown move in view while stepping.
        final ctx = _feedbackKey.currentContext;
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
            alignment: 0.0,
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
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                decoration: p.cardBox(),
                child: const Row(
                  children: [
                    Expanded(child: _GameTitle()),
                    _IconRow(compact: true),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const LoadCard(),
              const SizedBox(height: 8),
              const _AnalyseButton(),
              const SizedBox(height: 8),
              if (a.variation != null) ...[
                const _WhatIfBar(),
                const SizedBox(height: 8),
              ],
              KeyedSubtree(key: _feedbackKey, child: const _MoveFeedback()),
              const SizedBox(height: 8),
              const _EnginePanel(),
              const SizedBox(height: 8),
              _MoveList(currentKey: _currentKey),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                child: Text(
                  'Game review',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: _GameReview(),
              ),
            ],
          ),
        ),
        const _Controls(),
      ],
    );
    if (!widget.wide) return content;
    return Container(
      decoration: p.panelBox(),
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }
}

/// Saves the current game to local history, offering to turn history on
/// first (it is off by default).
Future<void> saveToHistory(BuildContext context) async {
  final s = Services.of(context);
  if (!s.settings.saveHistory) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Turn on local history?'),
        content: const Text(
          'Local history is off, so games and analysis are kept only until '
          'Ply closes. Turning it on saves reviewed games on this PC (never '
          'online). You can turn it off or delete the data in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Turn on and save'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await s.settings.update((x) => x.saveHistory = true);
  }
  await s.analysis.save();
  if (context.mounted) snack(context, 'Saved to History');
}

class _IconRow extends StatelessWidget {
  const _IconRow({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final a = watchAnalysis(context);
    final p = PlyPalette.of(context);
    return Container(
      decoration: compact
          ? null
          : BoxDecoration(
              color: p.panelHigh,
              borderRadius: BorderRadius.circular(8),
            ),
      child: Row(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
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
            tooltip: a.savedId == null ? 'Save to History' : 'Save changes',
            onPressed: () => saveToHistory(context),
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
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'file', child: Text('Open PGN file')),
        // These write to local history, so they only appear when it is on.
        if (a.settings.saveHistory) ...const [
          PopupMenuItem(value: 'details', child: Text('Edit game details')),
          PopupMenuItem(value: 'copy', child: Text('Save as new game')),
          PopupMenuItem(
            value: 'revisit',
            child: Text('Revisit this position later'),
          ),
        ],
        const PopupMenuItem(value: 'new', child: Text('New game')),
      ],
    );
  }
}

/// The main action: analyse the game; then its progress and status.
class _AnalyseButton extends StatelessWidget {
  const _AnalyseButton();

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final a = watchAnalysis(context);
    final p = PlyPalette.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: p.muted);
    final r = a.review;
    if (a.reviewing) {
      final done = r?.analysedCount ?? 0, total = a.game.length + 1;
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        decoration: p.cardBox(accent: theme.colorScheme.primary),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Analysing the game · $done of $total positions',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(value: done / total),
                  const SizedBox(height: 4),
                  Text(
                    'Stockfish depth ${a.reviewingDepth}. You can keep '
                    'browsing the moves meanwhile.',
                    style: muted,
                  ),
                ],
              ),
            ),
            TextButton(onPressed: a.cancelReview, child: const Text('Stop')),
          ],
        ),
      );
    }
    if (r == null || r.analysedCount == 0) {
      final none = a.game.length == 0;
      return Tooltip(
        message: none
            ? 'Open a game first'
            : 'Stockfish checks every position at depth '
                  '${s.settings.reviewDepth} and rates each move',
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            textStyle: theme.textTheme.titleSmall,
          ),
          onPressed: none ? null : a.startReview,
          icon: const Icon(Icons.query_stats),
          label: const Text('Analyse game'),
        ),
      );
    }
    // A finished analysis needs no button; the review section says so.
    if (r.complete) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: p.cardBox(),
      child: Row(
        children: [
          Icon(Icons.timelapse, size: 18, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Partial analysis · ${r.analysedCount} of '
              '${r.positions.length} positions',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          TextButton(onPressed: a.startReview, child: const Text('Resume')),
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
      decoration: p.cardBox(),
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
            'Live engine',
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
        Tooltip(
          message: a.reviewing
              ? 'Available when the game analysis is done'
              : 'Live Stockfish analysis of the shown position (E)',
          child: Switch(
            value: a.engineOn,
            onChanged: a.reviewing ? null : (_) => a.toggleEngine(),
          ),
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
                  ? 'Turn on to see Stockfish\'s best lines for this position.'
                  : 'This position: ${r.eval.label} (${evalWords(r.eval)}) · '
                        'depth ${r.depth}$best',
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

/// The game's moves as a two-column table (White, Black). The shown move is
/// highlighted; rated moves carry a small symbol, coloured for errors and
/// standout moves, with the rating as tooltip. Clicking a move shows it.
class _MoveList extends StatelessWidget {
  const _MoveList({required this.currentKey});
  final GlobalKey currentKey;

  @override
  Widget build(BuildContext context) {
    final a = watchAnalysis(context);
    final theme = Theme.of(context);
    final p = PlyPalette.of(context);
    final g = a.game;
    if (g.length == 0) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          'No moves yet. Open a game, or play moves on the board.',
          style: theme.textTheme.bodySmall?.copyWith(color: p.muted),
        ),
      );
    }
    final hide = a.settings.hideClassifications;
    // On a what-if line the game's move it branched from stays marked.
    final shown = a.onWhatIf ? a.branch : a.ply;

    Widget cell(int i) {
      final mr = hide || i >= a.moveReviews.length ? null : a.moveReviews[i];
      final current = shown == i + 1;
      final notable =
          mr != null &&
          (mr.cls.isError ||
              mr.cls == MoveClass.brilliant ||
              mr.cls == MoveClass.critical);
      final text = MoveText(
        g.plies[i].san,
        simple: a.settings.simpleNotation,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: current ? FontWeight.w700 : null,
        ),
      );
      final row = Row(
        children: [
          Flexible(child: text),
          if (notable) ...[
            const SizedBox(width: 4),
            Text(
              classSymbol(mr.cls),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: classColor(mr.cls),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      );
      final box = Container(
        key: current ? currentKey : null,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: current
            ? BoxDecoration(
                color: theme.colorScheme.primary.withValues(
                  alpha: a.onWhatIf ? 0.10 : 0.24,
                ),
                borderRadius: BorderRadius.circular(6),
                border: a.onWhatIf
                    ? Border.all(
                        color: theme.colorScheme.primary.withValues(alpha: 0.6),
                      )
                    : null,
              )
            : null,
        child: row,
      );
      return Semantics(
        button: true,
        selected: current,
        label: mr?.cls.label,
        child: Tooltip(
          message: mr == null ? '' : mr.cls.label,
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => a.goToGame(i + 1),
            child: box,
          ),
        ),
      );
    }

    final rows = <Widget>[];
    // A game from a position with Black to move starts with "1… e5".
    final offset = g.initial.turn == Side.black ? 1 : 0;
    for (var r = 0; r * 2 - offset < g.length; r++) {
      final w = r * 2 - offset, b = w + 1;
      rows.add(
        Container(
          color: r.isOdd ? p.panelHigh.withValues(alpha: 0.5) : null,
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: Text(
                  '${g.initial.fullmoves + r}.',
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodySmall?.copyWith(color: p.muted),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(child: w >= 0 ? cell(w) : const SizedBox()),
              const SizedBox(width: 4),
              Expanded(child: b < g.length ? cell(b) : const SizedBox()),
            ],
          ),
        ),
      );
    }
    final result = g.result;
    if (result != '*') {
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(42, 6, 0, 2),
          child: Text(result, style: theme.textTheme.bodyMedium),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Column(children: rows),
    );
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
            onPressed: a.line.length == 0 ? null : a.toggleAutoplay,
            icon: Icon(
              a.autoplaying ? Icons.pause : Icons.play_arrow_outlined,
              size: 30,
            ),
          ),
          IconButton(
            tooltip: 'Next move',
            onPressed: a.ply < a.line.length ? () => a.goTo(a.ply + 1) : null,
            icon: const Icon(Icons.arrow_forward, size: 28),
          ),
          IconButton(
            tooltip: 'Last move',
            onPressed: a.ply < a.line.length
                ? () => a.goTo(a.line.length)
                : null,
            icon: const Icon(Icons.last_page, size: 30),
          ),
        ],
      ),
    );
  }
}
