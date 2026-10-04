import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'scenarios.dart';
import 'window_session.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isWindows)
    throw UnsupportedError(
      'The sample app runs on Windows. Policy tests run on any Flutter host.',
    );
  final options = <String, String>{};
  for (final argument in arguments) {
    final split = argument.indexOf('=');
    if (!argument.startsWith('--') || split < 0)
      throw ArgumentError('Use --name=value');
    options[argument.substring(2, split)] = argument.substring(split + 1);
  }
  final mode = options['mode'] ?? 'fixed';
  if (mode != 'baseline' && mode != 'fixed')
    throw ArgumentError('mode must be baseline or fixed');
  final directory = Directory(
    options['state-dir'] ??
        '${Platform.environment['LOCALAPPDATA']}/AuthWindowRestoreLab',
  );
  final session = WindowSession(mode, directory);
  runApp(LabApp(session));
  try {
    await session.start();
    if (options['phase'] case final String phase) {
      final result = options['result'];
      if (result == null)
        throw ArgumentError('An automated phase needs --result=<file>');
      await runScenario(session, phase, File(result));
    }
  } catch (error, stack) {
    if (options['result'] case final String path) {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'passed': false,
          'error': error.toString(),
          'stack': stack.toString(),
        }),
        flush: true,
      );
    }
    exit(1);
  }
}

class LabApp extends StatelessWidget {
  const LabApp(this.session, {super.key});
  final WindowSession session;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Auth window restoration lab',
    theme: ThemeData(colorSchemeSeed: Colors.teal),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Auth #1883 — ${session.mode}',
              style: const TextStyle(fontSize: 26),
            ),
            const SizedBox(height: 16),
            const Text(
              'Move and resize this window, close it, then reopen the same mode.\n'
              'The baseline saves only size. The candidate saves normal bounds and monitor, '
              'and fits the restored window inside the work area.',
            ),
            const SizedBox(height: 16),
            SelectableText('Isolated state: ${session.directory.path}'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: () => unawaited(session.save()),
                  child: const Text('Save now'),
                ),
                OutlinedButton(
                  onPressed: () => unawaited(windowManager.maximize()),
                  child: const Text('Maximize'),
                ),
                OutlinedButton(
                  onPressed: () => unawaited(windowManager.unmaximize()),
                  child: const Text('Restore'),
                ),
                OutlinedButton(
                  onPressed: () => unawaited(session.close()),
                  child: const Text('Save and close'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              'For manual checks: top taskbar, secondary monitor, mixed DPI, '
              'unplugged monitor, maximize/restart/restore, and minimize/close. '
              'This sample never opens Auth data.',
            ),
          ],
        ),
      ),
    ),
  );
}
