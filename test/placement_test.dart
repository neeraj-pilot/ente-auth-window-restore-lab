import 'dart:convert';
import 'dart:ui';

import 'package:auth_window_restore_lab/placement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const primary = Monitor(
    'primary',
    Rect.fromLTWH(0, 0, 1920, 1040),
    1,
    primary: true,
  );
  const normal = Placement('primary', Rect.fromLTWH(180, 150, 500, 420), false);
  test('normal bounds survive serialization and restart', () {
    final decoded = Placement.fromJson(jsonDecode(jsonEncode(normal.toJson())));
    expect(restoreBounds(decoded, [primary]), normal.logicalBounds);
  });
  for (final area in const [
    Rect.fromLTWH(0, 48, 1920, 1032),
    Rect.fromLTWH(0, 0, 1920, 1032),
    Rect.fromLTWH(48, 0, 1872, 1080),
    Rect.fromLTWH(0, 0, 1872, 1080),
  ]) {
    test('oversized defaults fit taskbar work area $area', () {
      final restored = restoreBounds(null, [
        Monitor('primary', area, 1, primary: true),
      ]);
      expect(restored.top, greaterThanOrEqualTo(area.top));
      expect(restored.bottom, lessThanOrEqualTo(area.bottom));
      expect(restored.left, greaterThanOrEqualTo(area.left));
      expect(restored.right, lessThanOrEqualTo(area.right));
    });
  }
  test('secondary monitor with negative origin restores in its own scale', () {
    const secondary = Monitor(
      'second',
      Rect.fromLTWH(-2560, 60, 2560, 1380),
      1.5,
    );
    const bounds = Rect.fromLTWH(-2260, 210, 750, 630);
    final saved = captureBounds(bounds, secondary, false);
    expect(restoreBounds(saved, [primary, secondary]), bounds);
  });
  test(
    'DPI and monitor-layout changes retain logical size and local offset',
    () {
      const moved = Monitor(
        'primary',
        Rect.fromLTWH(1920, 80, 2560, 1360),
        2,
        primary: true,
      );
      expect(
        restoreBounds(normal, [moved]),
        const Rect.fromLTWH(2280, 380, 1000, 840),
      );
    },
  );
  test('removed monitor falls back to primary and fits its work area', () {
    const lost = Placement(
      'removed',
      Rect.fromLTWH(2000, 2000, 3000, 2000),
      false,
    );
    expect(restoreBounds(lost, [primary]), primary.workArea);
  });
  test(
    'maximize preserves normal bounds; minimize and startup preserve state',
    () {
      final maximized = updatePlacement(
        normal,
        normal.logicalBounds,
        primary,
        maximized: true,
        minimized: false,
        restoring: false,
      )!;
      expect(maximized.logicalBounds, normal.logicalBounds);
      expect(maximized.maximized, isTrue);
      for (final flags in [(true, false), (false, true)]) {
        final next = updatePlacement(
          maximized,
          const Rect.fromLTWH(-32000, -32000, 160, 28),
          primary,
          maximized: false,
          minimized: flags.$1,
          restoring: flags.$2,
        );
        expect(next, same(maximized));
      }
    },
  );
  test('maximized capture uses current native normal bounds and monitor', () {
    const secondary = Monitor(
      'second',
      Rect.fromLTWH(-2560, 60, 2560, 1380),
      1.5,
    );
    const latest = Rect.fromLTWH(-2260, 210, 750, 630);
    final result = updatePlacement(
      normal,
      latest,
      secondary,
      maximized: true,
      minimized: false,
      restoring: false,
    )!;
    expect(result.monitorId, 'second');
    expect(result.maximized, isTrue);
    expect(restoreBounds(result, [primary, secondary]), latest);
  });
  test(
    'restoring a maximized window captures its subsequent normal bounds',
    () {
      final result = updatePlacement(
        normal.withMaximized(true),
        normal.logicalBounds,
        primary,
        maximized: false,
        minimized: false,
        restoring: false,
      )!;
      expect(result.maximized, isFalse);
      expect(result.logicalBounds, normal.logicalBounds);
    },
  );
  test('invalid persisted geometry is rejected', () {
    for (final invalid in [double.nan, double.infinity, -1.0, 0.0]) {
      expect(
        () => readRect({'x': 0, 'y': 0, 'width': invalid, 'height': 400}),
        throwsFormatException,
      );
    }
  });
}
