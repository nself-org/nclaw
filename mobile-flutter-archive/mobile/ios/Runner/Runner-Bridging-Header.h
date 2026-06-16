#import "GeneratedPluginRegistrant.h"

// libnclaw mobile FFI (C-ABI) exports — implemented in core/src/mobile_ffi.rs
// and linked via libnclaw.xcframework. Declared here so Swift can call them.
#include <stdbool.h>
void nclaw_set_low_power(bool flag);
void nclaw_set_battery_pct(unsigned char pct);
void nclaw_set_thermal_level(unsigned char level);
