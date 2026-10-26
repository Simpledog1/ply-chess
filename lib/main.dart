import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'analysis/openings.dart';
import 'engine/engine_service.dart';
import 'storage/game_store.dart';
import 'storage/settings.dart';
import 'ui/analysis_controller.dart';
import 'ui/analyze_screen.dart';
import 'ui/board/chess_board.dart';
import 'ui/games_screen.dart';
import 'ui/insights_screen.dart';
import 'ui/services.dart';
import 'ui/settings_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationDocumentsDirectory();
  final settings = Settings(dir);
  await settings.load();
  final store = GameStore(dir);
  await store.load();
  final engine = EngineService(
    threads: settings.threads,
    hashMb: settings.hashMb,
  );
  final analysis = AnalysisController(
    engine: engine,
    store: store,
    settings: settings,
  );
  LicenseRegistry.addLicense(bundledLicenses);
  unawaited(precachePieces());
  // Opening names / theory detection load in a background isolate.
  unawaited(OpeningBook.load().then(analysis.setBook));
  runApp(
    Services(
      store: store,
      settings: settings,
      engine: engine,
      analysis: analysis,
      tab: ValueNotifier(0),
      child: const PlyApp(),
    ),
  );
}

/// Licenses for components that are not Dart packages (those are collected
/// automatically by Flutter).
Stream<LicenseEntry> bundledLicenses() async* {
  final gpl3 = await rootBundle.loadString('assets/licenses/GPL-3.0.txt');
  final gpl2 = await rootBundle.loadString('assets/licenses/GPL-2.0.txt');
  yield LicenseEntryWithLineBreaks(
    ['Stockfish 19'],
    '''
Stockfish 19, a UCI chess engine. Copyright (C) 2004-2026 The Stockfish developers (see AUTHORS file).
Ply bundles the unmodified official binary "stockfish-android-arm64-universal" from
https://github.com/official-stockfish/Stockfish/releases/tag/sf_19 . The complete corresponding
source code is available at that release (tag sf_19) and is included in the release archive.
Stockfish is free software under the GNU General Public License version 3.

$gpl3''',
  );
  yield LicenseEntryWithLineBreaks(
    ['Cburnett chess pieces'],
    '''
Chess piece artwork by Colin M. L. Burnett (Cburnett), unmodified SVG files from the Lichess
repository (lichess-org/lila, public/piece/cburnett), distributed under the GNU General Public
License version 2 or later. The originals on Wikimedia Commons are also available under
GFDL 1.2+, CC BY-SA 3.0 and BSD licenses.

$gpl2''',
  );
  yield const LicenseEntryWithLineBreaks(
    ['Lichess chess-openings'],
    '''
Opening names from https://github.com/lichess-org/chess-openings (commit a6189a30),
dedicated to the public domain under CC0 1.0 Universal.''',
  );
}

class PlyApp extends StatelessWidget {
  const PlyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Services.of(context).settings;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        title: 'Ply',
        debugShowCheckedModeBanner: false,
        theme: plyTheme(Brightness.light),
        darkTheme: plyTheme(Brightness.dark),
        themeMode: settings.themeMode,
        home: const HomeShell(),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  static const _pages = [
    AnalyzeScreen(),
    GamesScreen(),
    InsightsScreen(),
    SettingsScreen(),
  ];
  static const _dest = [
    (Icons.grid_view_outlined, Icons.grid_view_rounded, 'Analyze'),
    (Icons.folder_outlined, Icons.folder, 'Games'),
    (Icons.insights_outlined, Icons.insights, 'Insights'),
    (Icons.tune_outlined, Icons.tune, 'Settings'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Don't burn battery on live analysis nobody is looking at.
    final a = Services.of(context).analysis;
    if (state == AppLifecycleState.paused && a.engineOn) a.toggleEngine();
  }

  @override
  Widget build(BuildContext context) {
    final tab = Services.of(context).tab;
    return ValueListenableBuilder<int>(
      valueListenable: tab,
      builder: (context, i, _) {
        final wide = MediaQuery.sizeOf(context).width >= 840;
        final body = IndexedStack(index: i, children: _pages);
        return PopScope(
          canPop: i == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) tab.value = 0;
          },
          child: Scaffold(
            body: wide
                ? Row(
                    children: [
                      NavigationRail(
                        selectedIndex: i,
                        onDestinationSelected: (v) => tab.value = v,
                        labelType: NavigationRailLabelType.all,
                        destinations: [
                          for (final d in _dest)
                            NavigationRailDestination(
                              icon: Icon(d.$1),
                              selectedIcon: Icon(d.$2),
                              label: Text(d.$3),
                            ),
                        ],
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: body),
                    ],
                  )
                : body,
            bottomNavigationBar: wide
                ? null
                : NavigationBar(
                    selectedIndex: i,
                    height: 64,
                    onDestinationSelected: (v) => tab.value = v,
                    destinations: [
                      for (final d in _dest)
                        NavigationDestination(
                          icon: Icon(d.$1),
                          selectedIcon: Icon(d.$2),
                          label: d.$3,
                        ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}
