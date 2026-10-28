import 'package:flutter/foundation.dart';

import '../storage/settings.dart';
import 'online_games.dart';

/// Recent public games of the selected profile, held in memory only.
class GamesBrowser extends ChangeNotifier {
  GamesBrowser({required this.settings, this.httpGet});

  final Settings settings;

  /// HTTP layer; tests pass a fake.
  final HttpGet? httpGet;

  GameFeed? feed;
  bool loading = false;
  String? error;

  /// Feeds fetched recently, so switching profiles doesn't refetch.
  final _cache = <String, (GameFeed, DateTime)>{};
  static const cacheFor = Duration(minutes: 10);
  int _token = 0;

  /// Loads the first page of [username]'s games on [site]. The profile is
  /// remembered only after the site confirmed the account exists.
  Future<void> open(ChessSite site, String username) async {
    final String name;
    try {
      name = checkUsername(username);
    } on OnlineException catch (e) {
      error = e.message;
      notifyListeners();
      return;
    }
    final key = profileKey(site, name);
    final cached = _cache[key];
    if (cached != null && DateTime.now().difference(cached.$2) < cacheFor) {
      _token++;
      feed = cached.$1;
      error = null;
      loading = false;
      notifyListeners();
      await settings.useProfile(site, feed!.displayName ?? name);
      return;
    }
    final f = GameFeed(site, name, get: httpGet, pageSize: settings.pageSize);
    await _run(f, () async {
      await f.loadMore();
      _cache[key] = (f, DateTime.now());
      await settings.useProfile(site, f.displayName ?? name);
    });
  }

  /// Fetches the next page of the current feed.
  Future<void> more() async {
    final f = feed;
    if (f == null || loading || !f.hasMore) return;
    await _run(f, f.loadMore);
  }

  /// Stops waiting for the current request; a late reply is ignored.
  void cancel() {
    if (!loading) return;
    _token++;
    loading = false;
    notifyListeners();
  }

  /// Drops cached games of a profile (e.g. after deleting its data).
  void forget(String key) {
    _cache.remove(key);
    if (feed?.key == key) feed = null;
    notifyListeners();
  }

  Future<void> _run(GameFeed f, Future<void> Function() task) async {
    final t = ++_token;
    feed = f;
    error = null;
    loading = true;
    notifyListeners();
    try {
      await task();
    } on OnlineException catch (e) {
      if (t == _token) error = e.message;
    } catch (_) {
      if (t == _token) error = 'Could not load games';
    } finally {
      if (t == _token) {
        loading = false;
        notifyListeners();
      }
    }
  }
}
