import 'dart:convert';
import 'dart:io';

import 'package:auth_window_restore_lab/placement.dart';
import 'package:auth_window_restore_lab/window_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const probe = MethodChannel('auth_window_restore_lab/window');
  const manager = MethodChannel('window_manager');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  late WindowSession session;
  late Map<String, dynamic> snapshot;
  final calls = <String>[];

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('window-lab-test-');
    calls.clear();
    snapshot = {
      'bounds': rectJson(const Rect.fromLTWH(70, 70, 500, 420)),
      'normalBounds': rectJson(const Rect.fromLTWH(70, 70, 500, 420)),
      'monitorId': 'primary',
      'normalMonitorId': 'primary',
      'maximized': false,
      'minimized': false,
      'monitors': [
        {
          'id': 'primary',
          'workArea': rectJson(const Rect.fromLTWH(0, 0, 1920, 1040)),
          'dpi': 96,
          'primary': true,
        },
      ],
    };
    messenger.setMockMethodCallHandler(probe, (call) async {
      if (call.method == 'snapshot') return snapshot;
      if (call.method == 'setBounds') {
        snapshot['bounds'] = call.arguments;
        snapshot['normalBounds'] = call.arguments;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(manager, (call) async {
      calls.add(call.method);
      if (call.method == 'isMinimized' ||
          call.method == 'isFullScreen' ||
          call.method == 'isMaximized')
        return false;
      return null;
    });
    session = WindowSession('fixed', directory);
    await session.start();
  });

  tearDown(() async {
    await session.close();
    messenger.setMockMethodCallHandler(probe, null);
    messenger.setMockMethodCallHandler(manager, null);
    await directory.delete(recursive: true);
  });

  test('save after immediate maximize reads native normal geometry', () async {
    const latest = Rect.fromLTWH(300, 180, 460, 380);
    snapshot['normalBounds'] = rectJson(latest);
    snapshot['bounds'] = rectJson(const Rect.fromLTWH(0, 0, 1920, 1040));
    snapshot['maximized'] = true;
    await session.save();
    final saved = Placement.fromJson(
      jsonDecode(await session.stateFile.readAsString()),
    );
    expect(saved.logicalBounds, latest);
    expect(saved.maximized, isTrue);
  });

  test('failed write does not poison the next save', () async {
    final obstacle = await Directory('${session.stateFile.path}.tmp').create();
    await expectLater(session.save(), throwsA(isA<FileSystemException>()));
    await obstacle.delete();
    const latest = Rect.fromLTWH(300, 180, 460, 380);
    snapshot['normalBounds'] = rectJson(latest);
    await session.save();
    final saved = Placement.fromJson(
      jsonDecode(await session.stateFile.readAsString()),
    );
    expect(saved.logicalBounds, latest);
    expect(
      session.events.any((event) => event['event'] == 'save-error'),
      isTrue,
    );
  });

  test('close requests native closure even when flushing fails', () async {
    await Directory('${session.stateFile.path}.tmp').create();
    calls.clear();
    await expectLater(session.close(), throwsA(isA<FileSystemException>()));
    expect(calls, ['setPreventClose', 'close']);
  });
}
