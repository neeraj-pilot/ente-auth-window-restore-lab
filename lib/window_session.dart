import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:window_manager/window_manager.dart';

import 'placement.dart';
import 'window_probe.dart';

class WindowSession with WindowListener {
  WindowSession(this.mode, this.directory);
  final String mode;
  final Directory directory;
  final probe = WindowProbe();
  Placement? placement;
  Map<String, dynamic>? loaded;
  Timer? _timer;
  Future<void> _pending = Future.value();
  bool _restoring = true;
  bool _closing = false;
  bool get fixed => mode == 'fixed';
  File get stateFile => File('${directory.path}/$mode.json');
  final events = <Map<String, dynamic>>[];

  Future<void> start() async {
    await directory.create(recursive: true);
    if (await stateFile.exists()) {
      try {
        loaded =
            jsonDecode(await stateFile.readAsString()) as Map<String, dynamic>;
        if (fixed) placement = Placement.fromJson(loaded!);
      } on Object catch (error) {
        events.add({'event': 'invalid-state', 'error': error.toString()});
        loaded = null;
      }
    }
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    if (!fixed) windowManager.addListener(this);
    final wasMaximized = fixed
        ? placement?.maximized ?? false
        : loaded?['is_maximized'] == true;
    final options = WindowOptions(
      title: 'Auth #1883 window lab — $mode',
      size: fixed
          ? null
          : Size(
              ((loaded?['windowWidth'] as num?)?.toDouble() ?? 800).clamp(
                200,
                8192,
              ),
              ((loaded?['windowHeight'] as num?)?.toDouble() ?? 1200).clamp(
                400,
                8192,
              ),
            ),
      maximumSize: const Size(8192, 8192),
    );
    await windowManager.waitUntilReadyToShow(options);
    if (fixed) {
      final snapshot = await probe.snapshot();
      await probe.setBounds(restoreBounds(placement, snapshot.monitors));
    }
    await windowManager.show();
    if (wasMaximized) await windowManager.maximize();
    await windowManager.focus();
    _restoring = false;
    if (fixed) windowManager.addListener(this);
    events.add({'event': 'started', 'snapshot': (await probe.snapshot()).json});
    await save();
  }

  Future<void> save() {
    _timer?.cancel();
    final operation = _pending.then((_) async {
      final snapshot = await probe.snapshot();
      Map<String, dynamic>? data;
      if (fixed) {
        placement = updatePlacement(
          placement,
          snapshot.normalBounds,
          snapshot.normalMonitor,
          maximized: snapshot.maximized,
          minimized: snapshot.minimized,
          restoring: _restoring,
        );
        data = placement?.toJson();
      } else {
        // Mirrors Auth's two size reads and lack of position/normal-state guard.
        final width = (await windowManager.getSize()).width;
        final height = (await windowManager.getSize()).height;
        data = {
          'windowWidth': width,
          'windowHeight': height,
          'is_maximized': snapshot.maximized,
        };
      }
      events.add({
        'event': 'capture',
        'snapshot': snapshot.json,
        'saved': data,
      });
      if (data == null) return;
      final temporary = File('${stateFile.path}.tmp');
      await temporary.writeAsString(jsonEncode(data), flush: true);
      await temporary.rename(stateFile.path);
    });
    // Callers still receive the error; the next queued save can try again.
    _pending = operation.catchError((Object error) {
      events.add({'event': 'save-error', 'error': error.toString()});
    });
    return operation;
  }

  void _changed() {
    if (_closing || (fixed && _restoring)) return;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 150), () {
      unawaited(save());
    });
  }

  @override
  void onWindowResize() => _changed();
  @override
  void onWindowMove() {
    if (fixed) _changed();
  }

  @override
  void onWindowMaximize() => _changed();
  @override
  void onWindowUnmaximize() => _changed();
  @override
  void onWindowMinimize() => _changed();
  @override
  void onWindowRestore() => _changed();
  @override
  void onWindowClose() => unawaited(close());

  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    try {
      await save();
    } finally {
      windowManager.removeListener(this);
      await windowManager.setPreventClose(false);
      await windowManager.close();
    }
  }
}
