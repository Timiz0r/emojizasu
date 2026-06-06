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

// Key handler invoked (on the fcitx5 main thread) for every key event on the
// locked IC, in the PreInputMethod phase. Returns true if the key was consumed
// (the watcher then filterAndAccept()s it so it never reaches the app).
//   sym/states: fcitx KeySym / KeyStates as raw integers
//   utf8:       keySymToUTF8(sym) — the typed character, "" for non-text keys
//   isRelease:  true for key-release events
typedef bool (*ShimKeyHandler)(unsigned int sym, unsigned int states,
                               const char* utf8, bool isRelease);

// Install the key handler used by the PreInputMethod key watcher. Pass nullptr
// to disable forwarding.
void               shim_set_key_handler(ShimKeyHandler cb);

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
