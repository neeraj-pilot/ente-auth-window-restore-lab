#include "window_probe.h"

#include <flutter/standard_method_codec.h>

#include <cmath>
#include <string>

#include "window_geometry.h"

namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
using List = flutter::EncodableList;

Map Rectangle(const RECT& rect) {
  return {{Value("x"), Value(static_cast<double>(rect.left))},
          {Value("y"), Value(static_cast<double>(rect.top))},
          {Value("width"), Value(static_cast<double>(rect.right - rect.left))},
          {Value("height"), Value(static_cast<double>(rect.bottom - rect.top))}};
}

Map Encode(const window_geometry::Snapshot& snapshot) {
  List monitors;
  for (const auto& monitor : snapshot.monitors) {
    monitors.emplace_back(Map{
        {Value("id"), Value(monitor.id)},
        {Value("workArea"), Value(Rectangle(monitor.work_area))},
        {Value("screen"), Value(Rectangle(monitor.screen))},
        {Value("dpi"), Value(static_cast<int>(monitor.dpi))},
        {Value("primary"), Value(monitor.primary)}});
  }
  return {{Value("bounds"), Value(Rectangle(snapshot.bounds))},
          {Value("normalBounds"), Value(Rectangle(snapshot.normal_bounds))},
          {Value("monitorId"), Value(snapshot.monitor_id)},
          {Value("normalMonitorId"), Value(snapshot.normal_monitor_id)},
          {Value("windowDpi"), Value(static_cast<int>(snapshot.window_dpi))},
          {Value("placementFlags"),
           Value(static_cast<int>(snapshot.placement_flags))},
          {Value("maximized"), Value(snapshot.maximized)},
          {Value("minimized"), Value(snapshot.minimized)},
          {Value("monitors"), Value(monitors)}};
}

RECT DecodeBounds(const Map& args) {
  const auto number = [&args](const char* key) {
    return std::lround(std::get<double>(args.at(Value(key))));
  };
  const LONG x = number("x");
  const LONG y = number("y");
  return RECT{x, y, x + number("width"), y + number("height")};
}
}  // namespace

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> CreateWindowProbe(
    flutter::BinaryMessenger* messenger, HWND window) {
  auto channel = std::make_unique<flutter::MethodChannel<Value>>(
      messenger, "auth_window_restore_lab/window",
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([window](const auto& call, auto result) {
    const auto& method = call.method_name();
    if (method == "snapshot") {
      const auto snapshot = window_geometry::Capture(window);
      if (!snapshot) {
        result->Error("win32", "Cannot query window/monitor geometry");
        return;
      }
      result->Success(Value(Encode(*snapshot)));
    } else if (method == "setBounds" || method == "syntheticMove" ||
               method == "syntheticResize") {
      const RECT bounds = DecodeBounds(std::get<Map>(*call.arguments()));
      const bool changed =
          method == "setBounds"
              ? window_geometry::SetBounds(window, bounds)
              : window_geometry::SimulateChange(
                    window, bounds,
                    method == "syntheticMove" ? window_geometry::Change::move
                                              : window_geometry::Change::resize);
      if (!changed) {
        result->Error("win32", "Cannot set window geometry");
        return;
      }
      result->Success();
    } else {
      result->NotImplemented();
    }
  });
  return channel;
}
