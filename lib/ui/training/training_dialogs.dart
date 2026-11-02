part of 'training_screen.dart';

/// Theme tags offered for downloads (the Lichess API "angle").
const _downloadThemes = [
  'mix',
  'fork',
  'pin',
  'skewer',
  'discoveredAttack',
  'doubleCheck',
  'defensiveMove',
  'quietMove',
  'backRankMate',
  'sacrifice',
  'mate',
  'deflection',
  'endgame',
];

Future<void> showPuzzleDownloads(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _DownloadDialog());

class _DownloadDialog extends StatefulWidget {
  const _DownloadDialog();

  @override
  State<_DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<_DownloadDialog> {
  int _count = 200;
  final _themes = <String>{'mix'};
  String? _result;
  bool _importing = false;

  @override
  Widget build(BuildContext context) {
    final t = _watch(context);
    final theme = Theme.of(context);
    final p = PlyPalette.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: p.muted);
    return ListenableBuilder(
      listenable: t,
      builder: (context, _) {
        final busy = t.downloading || _importing;
        final pr = t.progress;
        return AlertDialog(
          title: const Text('Get more puzzles'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Your library: ${t.catalogue.size} puzzles '
                    '(${t.catalogue.userSize} downloaded or imported). '
                    'Puzzles you download stay on this PC and work offline.',
                    style: muted,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Download from Lichess',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 100, label: Text('100')),
                      ButtonSegment(value: 200, label: Text('200')),
                      ButtonSegment(value: 500, label: Text('500')),
                    ],
                    selected: {_count},
                    onSelectionChanged: busy
                        ? null
                        : (v) => setState(() => _count = v.first),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final th in _downloadThemes)
                        FilterChip(
                          label: Text(th == 'mix' ? 'Mixed' : themeName(th)),
                          selected: _themes.contains(th),
                          onSelected: busy
                              ? null
                              : (on) => setState(() {
                                  if (th == 'mix') {
                                    _themes
                                      ..clear()
                                      ..add('mix');
                                  } else {
                                    _themes.remove('mix');
                                    on ? _themes.add(th) : _themes.remove(th);
                                    if (_themes.isEmpty) _themes.add('mix');
                                  }
                                }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (t.downloading && pr != null) ...[
                    LinearProgressIndicator(value: pr.fetched / pr.wanted),
                    Text(
                      '${pr.fetched} of ${pr.wanted} fetched…',
                      style: muted,
                    ),
                  ],
                  if (t.downloadError != null)
                    Text(
                      t.downloadError!,
                      style: muted?.copyWith(color: theme.colorScheme.error),
                    ),
                  if (_result != null) Text(_result!),
                  const SizedBox(height: 16),
                  Text(
                    'Import a Lichess puzzle file',
                    style: theme.textTheme.titleSmall,
                  ),
                  Text(
                    'A decompressed lichess_db_puzzle.csv from '
                    'database.lichess.org (CC0). Ply keeps a random sample '
                    'of up to 20,000 valid puzzles.',
                    style: muted,
                  ),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    onPressed: busy ? null : _import,
                    icon: _importing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.file_open_outlined, size: 18),
                    label: const Text('Choose a CSV file…'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            if (t.downloading)
              TextButton(
                onPressed: t.cancelDownload,
                child: const Text('Cancel download'),
              ),
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => _result = null);
                      final r = await t.download(
                        count: _count,
                        themes: _themes.toList(),
                      );
                      if (mounted && r != null) {
                        setState(() => _result = 'Done: ${r.summary}.');
                      }
                    },
              icon: const Icon(Icons.cloud_download_outlined),
              label: const Text('Download'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _import() async {
    final t = _watch(context);
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Lichess puzzle CSV',
      type: FileType.custom,
      allowedExtensions: const ['csv'],
    );
    final path = files.isEmpty ? null : files.first.path;
    if (path == null) return;
    setState(() {
      _importing = true;
      _result = null;
    });
    try {
      final r = await t.importCsv(path);
      if (mounted) setState(() => _result = 'Imported: ${r.summary}.');
    } catch (e) {
      if (mounted) setState(() => _result = 'Could not read the file: $e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }
}

Future<void> showTrainingSettings(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _SettingsDialog());

class _SettingsDialog extends StatelessWidget {
  const _SettingsDialog();

  @override
  Widget build(BuildContext context) {
    final t = _watch(context);
    return ListenableBuilder(
      listenable: t,
      builder: (context, _) {
        final p = t.profile;
        if (p == null) return const SizedBox.shrink();
        return AlertDialog(
          title: const Text('Training settings'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Size of new collections'),
                  const SizedBox(height: 6),
                  _SizePicker(
                    value: p.preferredSize,
                    onChanged: (v) => t.updatePreferences(size: v),
                  ),
                  const SizedBox(height: 12),
                  const Text('After a wrong move'),
                  _WrongMovePicker(
                    value: p.wrongMove,
                    onChanged: (v) => t.updatePreferences(wrongMove: v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Allow hints'),
                    value: p.hintsEnabled,
                    onChanged: (v) => t.updatePreferences(hints: v),
                  ),
                  Text(
                    'Rating source: ${p.ratingSource.label}'
                    '${p.chessRating == null ? '' : ' (${p.chessRating})'}. '
                    'Puzzle level: about ${p.estimate.round()} '
                    '(confidence: ${confidenceLabel(p.deviation)}). '
                    'Changes apply to the next puzzle; the current '
                    'collection keeps its puzzles.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }
}
