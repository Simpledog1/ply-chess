import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'uci.dart';

/// Runs the engine binary as a child process and speaks UCI over stdio.
class ProcessTransport implements EngineTransport {
  ProcessTransport._(this._process)
    : lines = _process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .asBroadcastStream() {
    _process.stderr.drain<void>();
  }

  final Process _process;
  @override
  final Stream<String> lines;

  static Future<ProcessTransport> start(String path) async =>
      ProcessTransport._(
        await Process.start(
          path,
          const [],
          // On Windows a console program started from a GUI app would get its
          // own console window; a detached process with pipes gets none.
          // Stockfish still exits when Ply closes (its stdin reaches EOF).
          mode: Platform.isWindows
              ? ProcessStartMode.detachedWithStdio
              : ProcessStartMode.normal,
        ),
      );

  @override
  void send(String command) {
    try {
      _process.stdin.writeln(command);
    } catch (_) {
      // Process already gone; the closed stdout stream reports the failure.
    }
  }

  @override
  Future<void> close() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    _process.kill();
  }
}

enum EngineStatus { idle, starting, ready, failed }

/// Owns the single Stockfish instance used by the app. Starts it lazily and
/// restarts it after a crash.
class EngineService extends ChangeNotifier {
  EngineService({this.threads = 2, this.hashMb = 64, this.connect});

  /// Opens the engine connection; defaults to starting the bundled binary.
  /// Tests pass a scripted engine.
  final Future<EngineTransport> Function()? connect;

  static const _channel = MethodChannel('ply/engine');

  int threads;
  int hashMb;
  EngineStatus status = EngineStatus.idle;
  String? error;
  String? engineName;
  UciEngine? _engine;
  Future<UciEngine>? _starting;

  /// Path of the bundled engine. On Android the binary ships as
  /// `libstockfish.so` in the APK's native library directory, which is the
  /// only app location Android allows executing from. Elsewhere (desktop
  /// development, tests) set the `STOCKFISH_PATH` environment variable.
  static Future<String> locateBinary() async {
    if (Platform.isAndroid) {
      final dir = await _channel.invokeMethod<String>('nativeLibraryDir');
      final path = '$dir/libstockfish.so';
      if (!File(path).existsSync()) {
        throw EngineException(
          'Stockfish is not bundled for this device\'s CPU architecture.',
        );
      }
      return path;
    }
    final override = Platform.environment['STOCKFISH_PATH'];
    if (override != null && File(override).existsSync()) return override;
    if (Platform.isWindows) {
      // The installer puts the engine in a "stockfish" folder beside Ply.exe.
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final bundled = '$exeDir\\stockfish\\stockfish.exe';
      if (File(bundled).existsSync()) return bundled;
      throw EngineException(
        'Stockfish is missing from the Ply folder ($bundled). '
        'Reinstall Ply to restore it.',
      );
    }
    throw EngineException('Set STOCKFISH_PATH to a Stockfish binary.');
  }

  Future<UciEngine> get engine {
    final e = _engine;
    if (e != null && e.isAlive) return Future.value(e);
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  Future<UciEngine> _start() async {
    status = EngineStatus.starting;
    error = null;
    notifyListeners();
    try {
      final transport = connect != null
          ? await connect!()
          : await ProcessTransport.start(await locateBinary());
      final e = UciEngine(transport);
      await e.init(threads: threads, hashMb: hashMb);
      _engine = e;
      engineName = e.name;
      status = EngineStatus.ready;
      notifyListeners();
      return e;
    } catch (err) {
      status = EngineStatus.failed;
      error = err is EngineException
          ? err.message
          : 'Could not start engine: $err';
      notifyListeners();
      rethrow;
    }
  }

  void stop() => _engine?.stop();

  /// Applies new Threads/Hash settings by restarting the engine.
  Future<void> configure({required int threads, required int hashMb}) async {
    if (threads == this.threads && hashMb == this.hashMb) return;
    this.threads = threads;
    this.hashMb = hashMb;
    final old = _engine;
    _engine = null;
    status = EngineStatus.idle;
    notifyListeners();
    await old?.dispose();
  }

  @override
  void dispose() {
    _engine?.dispose();
    super.dispose();
  }
}
