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

void               shim_commit_to_target(FcitxInstance* inst,
                                         const char* text, size_t len);

void               shim_install_key_watcher(FcitxInstance* inst);

FcitxEventSourceIO* shim_install_io_event(FcitxInstance* inst, int fd);
void                shim_free_io_event(FcitxEventSourceIO* src);

#ifdef __cplusplus
}
#endif
