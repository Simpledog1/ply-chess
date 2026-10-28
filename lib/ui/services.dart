import 'package:flutter/widgets.dart';

import '../engine/engine_service.dart';
import '../online/games_browser.dart';
import '../storage/game_store.dart';
import '../storage/settings.dart';
import 'analysis_controller.dart';

/// App-wide objects, available to every screen via [Services.of].
class Services extends InheritedWidget {
  const Services({
    super.key,
    required this.store,
    required this.settings,
    required this.engine,
    required this.analysis,
    required this.browser,
    required this.tab,
    required super.child,
  });

  final GameStore store;
  final Settings settings;
  final EngineService engine;
  final AnalysisController analysis;

  /// Recent games of the selected Lichess / Chess.com profile.
  final GamesBrowser browser;

  /// Selected bottom-navigation tab (0 Analyze, 1 Games, 2 Insights, 3 Settings).
  final ValueNotifier<int> tab;

  static Services of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Services>()!;

  /// Opens a saved game on the Analyze tab.
  void open(SavedGame g, {int atPly = 0}) {
    analysis.loadSaved(g, atPly: atPly);
    tab.value = 0;
  }

  @override
  bool updateShouldNotify(Services old) => false;
}
