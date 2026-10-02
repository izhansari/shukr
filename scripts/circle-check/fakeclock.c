// fakeclock: pins the wall clock of a simulator app (scripts/circle-check.sh). Loaded with
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

static double pinned(void) {
  static double t = -1;
  if (t < 0) { const char *s = getenv("CIRCLE_CLOCK"); t = s ? atof(s) : 0; }
  return t;
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
