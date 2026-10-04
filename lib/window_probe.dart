import 'package:flutter/services.dart';

import 'placement.dart';

class Snapshot {
  Snapshot(this.json);
  final Map<String, dynamic> json;
  Rect get bounds => readRect(json['bounds'] as Map);
  Rect get normalBounds => readRect(json['normalBounds'] as Map);
  Monitor get normalMonitor =>
      monitors.firstWhere((m) => m.id == json['normalMonitorId']);
  bool get maximized => json['maximized'] as bool;
  bool get minimized => json['minimized'] as bool;
  List<Monitor> get monitors => (json['monitors'] as List)
      .map((m) => Monitor.fromJson(m as Map))
      .toList();
  Monitor get monitor => monitors.firstWhere((m) => m.id == json['monitorId']);
}

class WindowProbe {
  static const _channel = MethodChannel('auth_window_restore_lab/window');
  Future<Snapshot> snapshot() async => Snapshot(
    Map<String, dynamic>.from((await _channel.invokeMethod<Map>('snapshot'))!),
  );
  Future<void> setBounds(Rect bounds) =>
      _channel.invokeMethod<void>('setBounds', rectJson(bounds));
  Future<void> syntheticMove(Rect bounds) =>
      _channel.invokeMethod<void>('syntheticMove', rectJson(bounds));
  Future<void> syntheticResize(Rect bounds) =>
      _channel.invokeMethod<void>('syntheticResize', rectJson(bounds));
}
