import 'package:flutter/material.dart';

import '../analysis/review.dart';
import '../chess/chess_game.dart';
import '../storage/settings.dart';
import 'import_export.dart';
import 'online_game_list.dart';
import 'services.dart';
import 'theme.dart';

/// "Load game from [PGN | FEN | Chess.com | Lichess]" box.
class LoadCard extends StatefulWidget {
  const LoadCard({super.key});

  @override
  State<LoadCard> createState() => _LoadCardState();
}

class _LoadCardState extends State<LoadCard> {
  final _text = TextEditingController();
  bool _busy = false;
  LoadSource? _shownSource;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _online =>
      _shownSource == LoadSource.chessCom || _shownSource == LoadSource.lichess;

  @override
  Widget build(BuildContext context) {
    final s = Services.of(context);
    final p = PlyPalette.of(context);
    final theme = Theme.of(context);
    final source = s.settings.loadSource;
    if (_shownSource != source) {
      _shownSource = source;
      final pr = s.settings.profile;
      _text.text = pr != null && pr.site == source.site ? pr.username : '';
    }
    final hint = switch (source) {
      LoadSource.pgn => 'Paste PGN here',
      LoadSource.fen => 'Paste a FEN position',
      LoadSource.chessCom => 'Chess.com username',
      LoadSource.lichess => 'Lichess username',
    };
    final buttonStyle = TextButton.styleFrom(
      backgroundColor: p.panelHigh,
      foregroundColor: p.text,
      minimumSize: const Size.fromHeight(42),
      shape: const RoundedRectangleBorder(),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        color: p.panel,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 44,
                    alignment: Alignment.center,
                    color: p.panelHigh,
                    child: Text(
                      'Load game from',
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    color: Color.lerp(p.panelHigh, p.text, 0.06),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<LoadSource>(
                        value: source,
                        isExpanded: true,
                        dropdownColor: p.panelHigh,
                        items: [
                          for (final v in LoadSource.values)
                            DropdownMenuItem(
                              value: v,
                              child: Center(child: Text(v.label)),
                            ),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            s.settings.update((x) => x.loadSource = v);
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: TextField(
                controller: _text,
                minLines: source == LoadSource.pgn ? 3 : 1,
                maxLines: source == LoadSource.pgn ? 6 : 1,
                textInputAction: _online ? TextInputAction.search : null,
                onSubmitted: _online ? (_) => _go() : null,
                autocorrect: false,
                style: source == LoadSource.pgn || source == LoadSource.fen
                    ? const TextStyle(fontFamily: 'monospace', fontSize: 12)
                    : null,
                decoration: InputDecoration(hintText: hint, fillColor: p.panel),
              ),
            ),
            if (source == LoadSource.pgn)
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      style: buttonStyle,
                      onPressed: _busy ? null : _go,
                      icon: const Icon(Icons.download),
                      label: const Text('Load'),
                    ),
                  ),
                  const SizedBox(width: 1),
                  Expanded(
                    child: TextButton.icon(
                      style: buttonStyle,
                      onPressed: () => pickPgnFile(context),
                      icon: const Icon(Icons.file_open_outlined),
                      label: const Text('Open file'),
                    ),
                  ),
                ],
              )
            else
              TextButton.icon(
                style: buttonStyle,
                onPressed: _busy ? null : _go,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(_online ? Icons.search : Icons.download),
                label: Text(_online ? 'Search Games' : 'Load'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _go() async {
    final s = Services.of(context);
    final text = _text.text.trim();
    switch (s.settings.loadSource) {
      case LoadSource.pgn:
        if (text.isEmpty) return snack(context, 'Paste a PGN first');
        await importPgnText(context, text);
      case LoadSource.fen:
        if (text.isEmpty) return snack(context, 'Paste a FEN first');
        try {
          final g = ChessGame.fromFen(text);
          s.analysis.load(g, orientation: g.initial.turn);
        } on FormatException catch (e) {
          snack(context, e.message);
        }
      case LoadSource.chessCom || LoadSource.lichess:
        await _search(text);
    }
  }

  Future<void> _search(String user) async {
    final s = Services.of(context);
    final site = s.settings.loadSource.site!;
    setState(() => _busy = true);
    await s.browser.open(site, user);
    if (!mounted) return;
    setState(() => _busy = false);
    final b = s.browser;
    if (b.error != null && (b.feed?.games.isEmpty ?? true)) {
      snack(context, b.error!);
      return;
    }
    await showOnlineGames(context);
  }
}

/// Bottom sheet with the selected profile's recent games.
Future<void> showOnlineGames(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => OnlineGameList(
        controller: scroll,
        onOpened: () => Navigator.pop(ctx),
      ),
    ),
  );
}

/// Section header bar used in the settings sheet.
class _SectionBar extends StatelessWidget {
  const _SectionBar(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    final p = PlyPalette.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: p.background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.enabled = true,
  });
  final int value, min, max;
  final ValueChanged<int> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = PlyPalette.of(context);
    return Container(
      width: 150,
      height: 34,
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        color: p.input,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(child: Text('$value')),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: enabled && value > min
                ? () => onChanged(value - 1)
                : null,
            icon: const Icon(Icons.remove),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: enabled && value < max
                ? () => onChanged(value + 1)
                : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

/// The "Analysis Settings" sheet from the reference design.
Future<void> showAnalysisSettings(BuildContext context) {
  final s = Services.of(context);
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 640),
        child: ListenableBuilder(
          listenable: Listenable.merge([s.settings, s.analysis]),
          builder: (ctx, _) {
            final st = s.settings;
            final a = s.analysis;
            final theme = Theme.of(ctx);
            Widget row(String label, Widget control) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(label, style: theme.textTheme.bodyLarge),
                  ),
                  control,
                ],
              ),
            );
            Widget classRow(
              MoveClass c,
              bool value,
              ClassOptions Function(bool) set,
            ) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  ClassBadge(c, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(c.label, style: theme.textTheme.bodyLarge),
                  ),
                  Switch(
                    value: value,
                    onChanged: (v) => st.update((x) => x.classOptions = set(v)),
                  ),
                ],
              ),
            );
            final o = st.classOptions;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 4, 0),
                  child: Row(
                    children: [
                      const Icon(Icons.memory),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Analysis Settings',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      const _SectionBar('Engine'),
                      row(
                        'Enabled',
                        Switch(
                          value: a.engineOn,
                          onChanged: a.reviewing
                              ? null
                              : (_) => a.toggleEngine(),
                        ),
                      ),
                      row(
                        'Version',
                        Text(
                          s.engine.engineName ?? 'Stockfish 19',
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                      row(
                        'Depth',
                        _NumberField(
                          value: st.liveDepth,
                          min: 8,
                          max: 40,
                          enabled: !st.timeLimitOn,
                          onChanged: (v) => st.update((x) => x.liveDepth = v),
                        ),
                      ),
                      row(
                        'Number of Lines',
                        _NumberField(
                          value: st.multiPv,
                          min: 1,
                          max: 5,
                          onChanged: (v) => st.update((x) => x.multiPv = v),
                        ),
                      ),
                      row(
                        'Time Limit (seconds)',
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: st.timeLimitOn,
                              onChanged: (v) =>
                                  st.update((x) => x.timeLimitOn = v),
                            ),
                            const SizedBox(width: 6),
                            SizedBox(
                              width: 120,
                              child: _NumberField(
                                value: st.timeLimitSec,
                                min: 1,
                                max: 60,
                                enabled: st.timeLimitOn,
                                onChanged: (v) =>
                                    st.update((x) => x.timeLimitSec = v),
                              ),
                            ),
                          ],
                        ),
                      ),
                      row(
                        'Suggestion Arrows',
                        DropdownButton<ArrowMode>(
                          value: st.arrows,
                          items: [
                            for (final m in ArrowMode.values)
                              DropdownMenuItem(value: m, child: Text(m.label)),
                          ],
                          onChanged: (v) {
                            if (v != null) st.update((x) => x.arrows = v);
                          },
                        ),
                      ),
                      row(
                        'Game analysis depth',
                        _NumberField(
                          value: st.reviewDepth,
                          min: 8,
                          max: 24,
                          onChanged: (v) => st.update((x) => x.reviewDepth = v),
                        ),
                      ),
                      const _SectionBar('Classifications'),
                      row(
                        'Hide Classifications',
                        Switch(
                          value: st.hideClassifications,
                          onChanged: (v) =>
                              st.update((x) => x.hideClassifications = v),
                        ),
                      ),
                      classRow(
                        MoveClass.brilliant,
                        o.brilliant,
                        (v) => ClassOptions(
                          brilliant: v,
                          critical: o.critical,
                          theory: o.theory,
                        ),
                      ),
                      classRow(
                        MoveClass.critical,
                        o.critical,
                        (v) => ClassOptions(
                          brilliant: o.brilliant,
                          critical: v,
                          theory: o.theory,
                        ),
                      ),
                      classRow(
                        MoveClass.theory,
                        o.theory,
                        (v) => ClassOptions(
                          brilliant: o.brilliant,
                          critical: o.critical,
                          theory: v,
                        ),
                      ),
                      const _SectionBar('Other'),
                      row(
                        'Simple Move Notation',
                        Switch(
                          value: st.simpleNotation,
                          onChanged: (v) =>
                              st.update((x) => x.simpleNotation = v),
                        ),
                      ),
                      row(
                        'Board Coordinates',
                        Switch(
                          value: st.showCoordinates,
                          onChanged: (v) =>
                              st.update((x) => x.showCoordinates = v),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

/// The "Share Game" dialog: FEN and PGN with copy buttons.
Future<void> showShareGame(BuildContext context) {
  final a = Services.of(context).analysis;
  final fen = a.shownPosition.fen;
  final pgn = a.exportPgn();
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final p = PlyPalette.of(ctx);
      Widget box(String text, {required bool multiline}) => Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 4, 4),
        decoration: BoxDecoration(
          color: p.panelHigh,
          borderRadius: BorderRadius.circular(6),
        ),
        child: multiline
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    height: 240,
                    child: SingleChildScrollView(
                      child: SelectableText(
                        text,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy PGN',
                    onPressed: () => copyText(ctx, text, 'PGN'),
                    icon: const Icon(Icons.copy),
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy FEN',
                    onPressed: () => copyText(ctx, text, 'FEN'),
                    icon: const Icon(Icons.copy),
                  ),
                ],
              ),
      );
      return Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Share Game',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('FEN', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 6),
                      box(fen, multiline: false),
                      const SizedBox(height: 14),
                      Text('PGN', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 6),
                      box(pgn, multiline: true),
                      const SizedBox(height: 10),
                      TextButton.icon(
                        onPressed: () =>
                            savePgnFile(ctx, pgn, a.saved?.title ?? 'ply-game'),
                        icon: const Icon(Icons.save_alt),
                        label: const Text('Save as .pgn file'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
