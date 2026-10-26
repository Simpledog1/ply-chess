import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chess/chess_game.dart';
import '../storage/game_store.dart';
import 'services.dart';

void snack(BuildContext context, String text, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), action: action));
}

Future<void> copyText(BuildContext context, String text, String what) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) snack(context, '$what copied');
}

/// Bottom sheet with every way to get a game or position into Ply.
Future<void> showImportSheet(BuildContext context, {bool saveSingle = false}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.content_paste),
            title: const Text('Paste PGN'),
            onTap: () {
              Navigator.pop(ctx);
              pastePgn(context, saveSingle: saveSingle);
            },
          ),
          ListTile(
            leading: const Icon(Icons.file_open_outlined),
            title: const Text('Open PGN file'),
            onTap: () {
              Navigator.pop(ctx);
              pickPgnFile(context, saveSingle: saveSingle);
            },
          ),
          ListTile(
            leading: const Icon(Icons.grid_on),
            title: const Text('Load FEN position'),
            onTap: () {
              Navigator.pop(ctx);
              loadFen(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.restart_alt),
            title: const Text('New game from start'),
            onTap: () {
              Navigator.pop(ctx);
              Services.of(context).analysis.newGame();
              Services.of(context).tab.value = 0;
            },
          ),
        ],
      ),
    ),
  );
}

Future<String?> _textDialog(
  BuildContext context, {
  required String title,
  required String hint,
  int lines = 8,
  String? initial,
}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 480,
        child: TextField(
          controller: c,
          autofocus: true,
          minLines: lines == 1 ? 1 : 4,
          maxLines: lines,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            final d = await Clipboard.getData(Clipboard.kTextPlain);
            if (d?.text != null) c.text = d!.text!;
          },
          child: const Text('Paste'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, c.text),
          child: const Text('Load'),
        ),
      ],
    ),
  );
}

Future<void> pastePgn(BuildContext context, {bool saveSingle = false}) async {
  final text = await _textDialog(
    context,
    title: 'Paste PGN',
    hint: '[Event "..."]\n\n1. e4 e5 2. Nf3 ...',
  );
  if (text == null || !context.mounted) return;
  await importPgnText(context, text, saveSingle: saveSingle);
}

Future<void> pickPgnFile(
  BuildContext context, {
  bool saveSingle = false,
}) async {
  try {
    final files = await FilePicker.pickFiles(dialogTitle: 'Open PGN');
    if (files.isEmpty || !context.mounted) return;
    final bytes = await files.first.readAsBytes();
    if (bytes.length > 20 * 1024 * 1024) {
      if (context.mounted) snack(context, 'File is too large (over 20 MB)');
      return;
    }
    if (!context.mounted) return;
    await importPgnText(
      context,
      utf8.decode(bytes, allowMalformed: true),
      saveSingle: saveSingle,
    );
  } catch (e) {
    if (context.mounted) snack(context, 'Could not read file: $e');
  }
}

/// Imports PGN text. A single game opens on the board (unsaved unless
/// [saveSingle]); several games are saved to the library and the first opens.
Future<void> importPgnText(
  BuildContext context,
  String text, {
  bool saveSingle = false,
}) async {
  final s = Services.of(context);
  final r = ChessGame.parseMany(text);
  if (r.games.isEmpty) {
    await _showErrors(context, 'Nothing imported', r.errors);
    return;
  }
  if (r.games.length == 1 && !saveSingle) {
    s.analysis.load(
      r.games.single,
      orientation: GameStore.detectColor(r.games.single, s.settings.usernames),
    );
    s.tab.value = 0;
  } else {
    final now = DateTime.now();
    final saved = [
      for (final (i, g) in r.games.indexed)
        SavedGame(
          id: newId(),
          pgn: g.toPgn(),
          addedAt: now.add(Duration(microseconds: i)),
          myColor: GameStore.detectColor(g, s.settings.usernames),
        ),
    ];
    await s.store.addAll(saved);
    if (!context.mounted) return;
    snack(
      context,
      'Saved ${saved.length} game${saved.length == 1 ? '' : 's'} to Games',
    );
    if (!saveSingle) s.open(saved.first);
  }
  if (r.errors.isNotEmpty && context.mounted) {
    await _showErrors(context, '${r.errors.length} game(s) skipped', r.errors);
  }
}

Future<void> _showErrors(
  BuildContext context,
  String title,
  List<String> errors,
) => showDialog<void>(
  context: context,
  builder: (ctx) => AlertDialog(
    title: Text(title),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(child: Text(errors.take(50).join('\n'))),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
    ],
  ),
);

Future<void> loadFen(BuildContext context) async {
  final text = await _textDialog(
    context,
    title: 'Load FEN',
    hint: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
    lines: 3,
  );
  if (text == null || !context.mounted) return;
  try {
    final s = Services.of(context);
    final g = ChessGame.fromFen(text);
    s.analysis.load(g, orientation: g.initial.turn);
    s.tab.value = 0;
  } on FormatException catch (e) {
    snack(context, e.message);
  }
}

Future<void> savePgnFile(BuildContext context, String pgn, String name) async {
  try {
    final safe = name.replaceAll(RegExp(r'[^\w\- ]+'), '_').trim();
    final uri = await FilePicker.saveFile(
      fileName: '${safe.isEmpty ? 'game' : safe}.pgn',
      bytes: Uint8List.fromList(utf8.encode(pgn)),
      mimeType: 'application/x-chess-pgn',
      dialogTitle: 'Export PGN',
    );
    if (uri != null && context.mounted) snack(context, 'PGN exported');
  } catch (e) {
    if (context.mounted) snack(context, 'Export failed: $e');
  }
}
