// Declarations of private macOS APIs used by Kursor.
// Everything here is undocumented; each symbol is used by other shipping mouse
// utilities (LinearMouse, Mac Mouse Fix) on current macOS releases.

#pragma once

#include <stdbool.h>
#include <stdint.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <ApplicationServices/ApplicationServices.h>
#include <IOKit/hidsystem/IOHIDEventSystemClient.h>
#include <IOKit/hidsystem/IOHIDServiceClient.h>

// Full (non-"simple") HID event system client. Needed to change per-service
// properties such as HIDPointerResolution / HIDMouseAcceleration.
IOHIDEventSystemClientRef _Nullable IOHIDEventSystemClientCreate(CFAllocatorRef _Nullable allocator) CF_RETURNS_RETAINED;

// Dock notifications: "com.apple.expose.awake" (Mission Control),
// "com.apple.expose.front.awake" (App Exposé), "com.apple.showdesktop.awake",
// "com.apple.launchpad.toggle".
CGError CoreDockSendNotification(CFStringRef _Nonnull notification, int unknown);

// Raw access to undocumented CGEvent fields/types (Swift's imported enums only
// spell out the public cases).
static inline void KursorEventSetType(CGEventRef _Nonnull event, uint32_t type) {
    CGEventSetType(event, (CGEventType)type);
}
static inline void KursorEventSetInt(CGEventRef _Nonnull event, uint32_t field, int64_t value) {
    CGEventSetIntegerValueField(event, (CGEventField)field, value);
}
static inline void KursorEventSetDouble(CGEventRef _Nonnull event, uint32_t field, double value) {
    CGEventSetDoubleValueField(event, (CGEventField)field, value);
}
static inline int64_t KursorEventGetInt(CGEventRef _Nonnull event, uint32_t field) {
    return CGEventGetIntegerValueField(event, (CGEventField)field);
}

// Symbolic hot keys ("Move left a space" = 79, "Move right a space" = 81, ...).
typedef uint32_t KursorSymbolicHotKey;
bool CGSIsSymbolicHotKeyEnabled(KursorSymbolicHotKey hotKey);
CGError CGSSetSymbolicHotKeyEnabled(KursorSymbolicHotKey hotKey, bool isEnabled);
CGError CGSGetSymbolicHotKeyValue(KursorSymbolicHotKey hotKey,
                                  uint16_t *_Nullable outKeyEquivalent,
                                  uint16_t *_Nullable outVirtualKeyCode,
                                  uint32_t *_Nullable outModifiers);

// Window server id of an Accessibility window element (used by yabai, AltTab, AutoRaise).
AXError _AXUIElementGetWindow(AXUIElementRef _Nonnull element, CGWindowID *_Nonnull outWindowID);
