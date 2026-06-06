#pragma once
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void FcitxAddonManager;
typedef void FcitxInstance;
typedef void FcitxInputContext;
typedef void FcitxEventSourceIO;

FcitxInstance*     shim_get_instance(FcitxAddonManager* mgr);

// Register FocusIn/Destroyed watchers that maintain s_target_ic.
// skip_program: ICs whose program() matches this string are not tracked
// (used to ignore the picker's own text inputs on the first pass).
void               shim_setup_ic_tracking(FcitxInstance* inst,
                                          const char* skip_program);

// Snapshot s_target_ic into s_locked_ic so commits go there until unlocked.
void               shim_lock_ic();

// Clear s_locked_ic; tracking resumes normally.
void               shim_unlock_ic();

// Queue text to be committed the next time s_locked_ic regains focus.
// Use this instead of shim_commit_to_target when the picker window is open
// (and has stolen compositor focus from the target).
void               shim_queue_commit(const char* text, size_t len);

// Commit text immediately to s_locked_ic (or s_target_ic / mostRecent).
// Only works when the target IC is currently active (has compositor focus).
void               shim_commit_to_target(FcitxInstance* inst,
                                         const char* text, size_t len);

FcitxEventSourceIO* shim_add_io_event(FcitxInstance* inst, int fd,
                                       void (*cb)(void*), void* userdata);
void                shim_free_io_event(FcitxEventSourceIO* src);

#ifdef __cplusplus
}
#endif
