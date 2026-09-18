#ifndef FRAMERELAY_CORE_BRIDGE_H
#define FRAMERELAY_CORE_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct FRCoreHandle FRCoreHandle;

typedef void (*FRCoreLogCallback)(
    int32_t level,
    const char *message,
    void *user
);

typedef enum FRCoreStatus {
    FRCoreStatusOK = 0,
    FRCoreStatusInvalidArgument = -1,
    FRCoreStatusLoadFailed = -2,
    FRCoreStatusSymbolMissing = -3,
    FRCoreStatusCreateFailed = -4,
    FRCoreStatusConfigureFailed = -5,
    FRCoreStatusAlreadyRunning = -6
} FRCoreStatus;

FRCoreHandle *fr_core_open(
    const char *dylib_path,
    char *error_message,
    size_t error_capacity
);

FRCoreStatus fr_core_set_window(
    FRCoreHandle *handle,
    void *nsview
);

FRCoreStatus fr_core_set_device_name(
    FRCoreHandle *handle,
    const char *utf8_name
);

FRCoreStatus fr_core_set_options(
    FRCoreHandle *handle,
    const char *argv_tail
);

void fr_core_set_log_callback(
    FRCoreHandle *handle,
    FRCoreLogCallback callback,
    void *user
);

FRCoreStatus fr_core_start(
    FRCoreHandle *handle
);

void fr_core_stop(
    FRCoreHandle *handle
);

void fr_core_close(
    FRCoreHandle *handle
);

#ifdef __cplusplus
}
#endif

#endif
