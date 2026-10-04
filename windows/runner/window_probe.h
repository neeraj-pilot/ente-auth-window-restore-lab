#ifndef RUNNER_WINDOW_PROBE_H_
#define RUNNER_WINDOW_PROBE_H_

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> CreateWindowProbe(
    flutter::BinaryMessenger* messenger, HWND window);

#endif  // RUNNER_WINDOW_PROBE_H_
