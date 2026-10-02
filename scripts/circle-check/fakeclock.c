// fakeclock: sets the wall clock of a simulator app (scripts/circle-check.sh). Loaded with
// SIMCTL_CHILD_DYLD_INSERT_LIBRARIES; the frozen time comes from SIMCTL_CHILD_CIRCLE_CLOCK (Unix seconds).
// Only wall time (CLOCK_REALTIME, gettimeofday, time, CFAbsoluteTimeGetCurrent) is pinned: animations and
// timers run on mach time and keep moving. Simulator only; never shipped.
#include <stdlib.h>
#include <time.h>
#include <sys/time.h>
#include <CoreFoundation/CoreFoundation.h>

#define DYLD_INTERPOSE(_new, _old) \
  __attribute__((used)) static struct { const void *n; const void *o; } _interpose_##_old \
  __attribute__((section("__DATA,__interpose"))) = { (const void *)(unsigned long)&_new, (const void *)(unsigned long)&_old };

// The clock starts at CIRCLE_CLOCK and runs at real speed from the moment the library loads (a frozen clock stalled
// SwiftUI's springs and implicit animations at their first frame until the next 1 s tick — Frank, step 2). With
// CIRCLE_CLOCK_FROZEN=1 it stays put.
static double start_wall = 0, start_mono = 0;
static int frozen = 0;
static double mono(void) { struct timespec m; clock_gettime(CLOCK_MONOTONIC_RAW, &m); return m.tv_sec + m.tv_nsec / 1e9; }
__attribute__((constructor)) static void fc_init(void) {
  const char *s = getenv("CIRCLE_CLOCK"); start_wall = s ? atof(s) : 0;
  const char *f = getenv("CIRCLE_CLOCK_FROZEN"); frozen = f && f[0] == '1';
  start_mono = mono();
}
static double pinned(void) {
  if (start_wall <= 0) return 0;
  return frozen ? start_wall : start_wall + (mono() - start_mono);
}
static int fc_clock_gettime(clockid_t id, struct timespec *ts) {
  if (id == CLOCK_REALTIME && pinned() > 0 && ts) { double t = pinned(); ts->tv_sec = (time_t)t; ts->tv_nsec = (long)((t - (double)ts->tv_sec) * 1e9); return 0; }
  return clock_gettime(id, ts);
}
static uint64_t fc_clock_gettime_nsec_np(clockid_t id) {
  if (id == CLOCK_REALTIME && pinned() > 0) return (uint64_t)(pinned() * 1e9);
  return clock_gettime_nsec_np(id);
}
static int fc_gettimeofday(struct timeval *tv, void *tz) {
  if (pinned() > 0 && tv) { double t = pinned(); tv->tv_sec = (time_t)t; tv->tv_usec = (int)((t - (double)tv->tv_sec) * 1e6); return 0; }
  return gettimeofday(tv, tz);
}
static time_t fc_time(time_t *out) {
  if (pinned() > 0) { time_t t = (time_t)pinned(); if (out) *out = t; return t; }
  return time(out);
}
static CFAbsoluteTime fc_CFAbsoluteTimeGetCurrent(void) {
  if (pinned() > 0) return pinned() - kCFAbsoluteTimeIntervalSince1970;
  return CFAbsoluteTimeGetCurrent();
}
DYLD_INTERPOSE(fc_clock_gettime, clock_gettime)
DYLD_INTERPOSE(fc_clock_gettime_nsec_np, clock_gettime_nsec_np)
DYLD_INTERPOSE(fc_gettimeofday, gettimeofday)
DYLD_INTERPOSE(fc_time, time)
DYLD_INTERPOSE(fc_CFAbsoluteTimeGetCurrent, CFAbsoluteTimeGetCurrent)
