#ifndef RUNNER_WINDOW_GEOMETRY_H_
#define RUNNER_WINDOW_GEOMETRY_H_

#include <windows.h>

#include <optional>
#include <string>
#include <vector>

namespace window_geometry {

struct Monitor {
  HMONITOR handle;
  std::string id;
  RECT work_area;
  RECT screen;
  UINT dpi;
  bool primary;
};

struct Snapshot {
  RECT bounds;
  RECT normal_bounds;
  std::string monitor_id;
  std::string normal_monitor_id;
  UINT window_dpi;
  UINT placement_flags;
  bool maximized;
  bool minimized;
  std::vector<Monitor> monitors;
};

enum class Change { move, resize };

// The HWND belongs to the caller's top-level window; bounds are physical pixels.
std::optional<Snapshot> Capture(HWND window);
bool SetBounds(HWND window, const RECT& bounds);
bool SimulateChange(HWND window, const RECT& bounds, Change change);

}  // namespace window_geometry

#endif  // RUNNER_WINDOW_GEOMETRY_H_
