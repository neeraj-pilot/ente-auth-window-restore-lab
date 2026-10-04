import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:window_manager/window_manager.dart';

import 'placement.dart';
import 'window_probe.dart';
import 'window_session.dart';

Future<Snapshot> waitFor(
  WindowSession session,
  bool Function(Snapshot) matches,
) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    final snapshot = await session.probe.snapshot();
    if (matches(snapshot)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final again = await session.probe.snapshot();
      if (matches(again)) return again;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('Window did not settle within the polling budget');
}

Future<void> waitForSaved(WindowSession session, Rect target) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    final saved = Placement.fromJson(
      jsonDecode(await session.stateFile.readAsString()),
    );
    final snapshot = await session.probe.snapshot();
    if (!saved.maximized &&
        nearBounds(restoreBounds(saved, snapshot.monitors), target))
      return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError(
    'Synthetic window event did not persist the requested bounds',
  );
}

Future<void> runScenario(
  WindowSession session,
  String phase,
  File resultFile,
) async {
  final result = <String, dynamic>{
    'mode': session.mode,
    'phase': phase,
    'loaded': session.loaded,
    'coverage': 'programmatic HWND checks; event phases use synthetic dispatch',
  };
  var hold = false;
  try {
    final initial = await session.probe.snapshot();
    final area = initial.monitor.workArea;
    result['startup'] = initial.json;
    if (phase == 'write' ||
        phase == 'move-maximize' ||
        phase == 'close-ready') {
      final scale = session.fixed ? 1.0 : initial.monitor.scale;
      final target = fitToWorkArea(
        phase == 'write'
            ? Rect.fromLTWH(
                area.left + 180,
                area.top + 150,
                500 * scale,
                420 * scale,
              )
            : Rect.fromLTWH(area.left + 300, area.top + 100, 460, 380),
        area,
      );
      if (!session.fixed &&
          (target.width < 200 * scale || target.height < 400 * scale)) {
        throw StateError('Runner work area is below baseline minimum size');
      }
      result['target'] = rectJson(target);
      await session.probe.setBounds(target);
      if (phase == 'move-maximize') {
        // No save or settling delay: exercise stale cached geometry at maximize.
        await windowManager.maximize();
        await waitFor(session, (s) => s.maximized);
      } else {
        await waitFor(session, (s) => nearBounds(s.bounds, target));
      }
      hold = phase == 'close-ready';
    } else if (phase == 'event-move' || phase == 'event-resize') {
      final target = fitToWorkArea(
        phase == 'event-move'
            ? initial.bounds.shift(const Offset(90, -40))
            : Rect.fromLTWH(initial.bounds.left, initial.bounds.top, 460, 380),
        area,
      );
      if (nearBounds(initial.bounds, target)) {
        throw StateError('Runner work area is too small for this event test');
      }
      result['target'] = rectJson(target);
      if (phase == 'event-move') {
        await session.probe.syntheticMove(target);
      } else {
        await session.probe.syntheticResize(target);
      }
      await waitFor(session, (s) => nearBounds(s.bounds, target));
      await waitForSaved(session, target);
      hold = true;
    } else if (phase == 'maximize') {
      await windowManager.maximize();
      await waitFor(session, (s) => s.maximized);
    } else if (phase == 'minimize') {
      final before = session.placement;
      await windowManager.minimize();
      await waitFor(session, (s) => s.minimized);
      await session.save();
      if (jsonEncode(before?.toJson()) !=
          jsonEncode(session.placement?.toJson())) {
        throw StateError('Minimizing changed the saved normal placement');
      }
      result['whileMinimized'] = (await session.probe.snapshot()).json;
      await windowManager.restore();
      await waitFor(session, (s) => !s.minimized && !s.maximized);
    } else if (phase == 'read-maximized') {
      if (!initial.maximized)
        throw StateError('Maximized state was not restored');
      await windowManager.unmaximize();
      await waitFor(session, (s) => !s.maximized && !s.minimized);
    } else if (phase != 'read' && phase != 'default') {
      throw ArgumentError('Unknown phase: $phase');
    }
    // Event phases must reach disk without either explicit save or close flush.
    if (!hold) await session.save();
    final actual = await session.probe.snapshot();
    result['actual'] = actual.json;
    result['stored'] = jsonDecode(await session.stateFile.readAsString());
    if (session.fixed &&
        !actual.maximized &&
        !actual.minimized &&
        !nearBounds(
          fitToWorkArea(actual.bounds, actual.monitor.workArea),
          actual.bounds,
        )) {
      throw StateError('Normal window extends outside the monitor work area');
    }
    if (phase == 'close-ready') {
      final beforeClose = Placement.fromJson(
        result['stored'] as Map<String, dynamic>,
      );
      if (nearBounds(
        restoreBounds(beforeClose, actual.monitors),
        actual.bounds,
      )) {
        throw StateError('Close test geometry was persisted before WM_CLOSE');
      }
    }
    result['waitingFor'] = hold
        ? (phase == 'close-ready' ? 'close' : 'kill')
        : null;
    result['passed'] = true;
  } catch (error, stack) {
    result['passed'] = false;
    result['error'] = error.toString();
    result['stack'] = stack.toString();
  }
  result['events'] = session.events;
  await resultFile.parent.create(recursive: true);
  final temporary = File('${resultFile.path}.tmp');
  await temporary.writeAsString(
    const JsonEncoder.withIndent('  ').convert(result),
    flush: true,
  );
  await temporary.rename(resultFile.path);
  if (hold && result['passed'] == true) {
    await Completer<void>().future; // The PowerShell harness owns termination.
  } else {
    await session.close();
  }
}
