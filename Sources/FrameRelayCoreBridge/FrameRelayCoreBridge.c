#include "FrameRelayCoreBridge.h"

#include <dlfcn.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct airplay_core airplay_core_t;

typedef airplay_core_t *(*FRCreateFn)(void);
typedef int (*FRSetWindowFn)(airplay_core_t *, void *);
typedef int (*FRSetStringFn)(airplay_core_t *, const char *);
typedef void (*FRSetLogCallbackFn)(airplay_core_t *, FRCoreLogCallback, void *);
typedef int (*FRStartFn)(airplay_core_t *);
typedef void (*FRVoidFn)(airplay_core_t *);

struct FRCoreHandle {
    void *library;
    airplay_core_t *core;

    FRCreateFn create;
    FRSetWindowFn set_window;
    FRSetStringFn set_device_name;
    FRSetLogCallbackFn set_log_callback;
    FRSetStringFn set_options;
    FRStartFn start;
    FRVoidFn stop;
    FRVoidFn destroy;

    pthread_mutex_t lifecycle;
    bool running;
};

/* UxPlay keeps its AirPlay state in file-static globals.  A process-wide
 * owner is therefore required even though each public handle has its own
 * lifecycle mutex. */
static pthread_mutex_t fr_global_lifecycle = PTHREAD_MUTEX_INITIALIZER;
static FRCoreHandle *fr_running_handle = NULL;

static void fr_set_error(char *buffer, size_t capacity, const char *message) {
    if (!buffer || capacity == 0) {
        return;
    }

    if (!message) {
        buffer[0] = '\0';
        return;
    }

    snprintf(buffer, capacity, "%s", message);
}

static bool fr_resolve_symbol(
    void *library,
    const char *name,
    void *destination,
    size_t destination_size,
    char *error_message,
    size_t error_capacity
) {
    void *symbol = dlsym(library, name);
    if (!symbol) {
        const char *detail = dlerror();
        if (detail) {
            char message[1024];
            snprintf(message, sizeof(message), "%s: %s", name, detail);
            fr_set_error(error_message, error_capacity, message);
        } else {
            char message[1024];
            snprintf(message, sizeof(message), "%s: symbol not found", name);
            fr_set_error(error_message, error_capacity, message);
        }
        return false;
    }

    if (destination_size != sizeof(symbol)) {
        fr_set_error(error_message, error_capacity, "function pointer size mismatch");
        return false;
    }

    memcpy(destination, &symbol, sizeof(symbol));
    return true;
}

static void fr_stop_locked(FRCoreHandle *handle) {
    if (!handle || !handle->core || !handle->running) {
        return;
    }

    handle->stop(handle->core);
    handle->running = false;
}

FRCoreHandle *fr_core_open(
    const char *dylib_path,
    char *error_message,
    size_t error_capacity
) {
    if (!dylib_path || dylib_path[0] == '\0') {
        fr_set_error(error_message, error_capacity, "empty AirPlay core path");
        return NULL;
    }

    FRCoreHandle *handle = calloc(1, sizeof(*handle));
    if (!handle) {
        fr_set_error(error_message, error_capacity, "unable to allocate core handle");
        return NULL;
    }

    if (pthread_mutex_init(&handle->lifecycle, NULL) != 0) {
        fr_set_error(error_message, error_capacity, "unable to initialize core mutex");
        free(handle);
        return NULL;
    }

    handle->library = dlopen(dylib_path, RTLD_NOW | RTLD_LOCAL);
    if (!handle->library) {
        const char *detail = dlerror();
        if (detail) {
            char message[1024];
            snprintf(message, sizeof(message), "dlopen failed: %s", detail);
            fr_set_error(error_message, error_capacity, message);
        } else {
            fr_set_error(error_message, error_capacity, "dlopen failed");
        }
        pthread_mutex_destroy(&handle->lifecycle);
        free(handle);
        return NULL;
    }

#define FR_RESOLVE(field, symbol_name) \
    if (!fr_resolve_symbol(handle->library, symbol_name, &handle->field, sizeof(handle->field), error_message, error_capacity)) { \
        dlclose(handle->library); \
        pthread_mutex_destroy(&handle->lifecycle); \
        free(handle); \
        return NULL; \
    }

    FR_RESOLVE(create, "airplay_core_create");
    FR_RESOLVE(set_device_name, "airplay_core_set_device_name");
    FR_RESOLVE(set_log_callback, "airplay_core_set_log_callback");
    FR_RESOLVE(set_window, "airplay_core_set_window");
    FR_RESOLVE(set_options, "airplay_core_set_options");
    FR_RESOLVE(start, "airplay_core_start");
    FR_RESOLVE(stop, "airplay_core_stop");
    FR_RESOLVE(destroy, "airplay_core_destroy");

#undef FR_RESOLVE

    handle->core = handle->create();
    if (!handle->core) {
        fr_set_error(error_message, error_capacity, "airplay_core_create returned null");
        dlclose(handle->library);
        pthread_mutex_destroy(&handle->lifecycle);
        free(handle);
        return NULL;
    }

    return handle;
}

FRCoreStatus fr_core_set_window(FRCoreHandle *handle, void *nsview) {
    if (!handle || !handle->core) {
        return FRCoreStatusInvalidArgument;
    }

    pthread_mutex_lock(&handle->lifecycle);
    if (handle->running) {
        pthread_mutex_unlock(&handle->lifecycle);
        return FRCoreStatusConfigureFailed;
    }

    int result = handle->set_window(handle->core, nsview);
    pthread_mutex_unlock(&handle->lifecycle);
    return result == 0 ? FRCoreStatusOK : FRCoreStatusConfigureFailed;
}

FRCoreStatus fr_core_set_device_name(FRCoreHandle *handle, const char *utf8_name) {
    if (!handle || !handle->core || !utf8_name) {
        return FRCoreStatusInvalidArgument;
    }

    pthread_mutex_lock(&handle->lifecycle);
    if (handle->running) {
        pthread_mutex_unlock(&handle->lifecycle);
        return FRCoreStatusConfigureFailed;
    }

    int result = handle->set_device_name(handle->core, utf8_name);
    pthread_mutex_unlock(&handle->lifecycle);
    return result == 0 ? FRCoreStatusOK : FRCoreStatusConfigureFailed;
}

FRCoreStatus fr_core_set_options(FRCoreHandle *handle, const char *argv_tail) {
    if (!handle || !handle->core || !argv_tail) {
        return FRCoreStatusInvalidArgument;
    }

    pthread_mutex_lock(&handle->lifecycle);
    if (handle->running) {
        pthread_mutex_unlock(&handle->lifecycle);
        return FRCoreStatusConfigureFailed;
    }

    int result = handle->set_options(handle->core, argv_tail);
    pthread_mutex_unlock(&handle->lifecycle);
    return result == 0 ? FRCoreStatusOK : FRCoreStatusConfigureFailed;
}

void fr_core_set_log_callback(
    FRCoreHandle *handle,
    FRCoreLogCallback callback,
    void *user
) {
    if (!handle || !handle->core) {
        return;
    }

    pthread_mutex_lock(&handle->lifecycle);
    handle->set_log_callback(handle->core, callback, user);
    pthread_mutex_unlock(&handle->lifecycle);
}

FRCoreStatus fr_core_start(FRCoreHandle *handle) {
    if (!handle || !handle->core) {
        return FRCoreStatusInvalidArgument;
    }

    pthread_mutex_lock(&fr_global_lifecycle);
    pthread_mutex_lock(&handle->lifecycle);
    if (handle->running || fr_running_handle) {
        pthread_mutex_unlock(&handle->lifecycle);
        pthread_mutex_unlock(&fr_global_lifecycle);
        return FRCoreStatusAlreadyRunning;
    }

    int result = handle->start(handle->core);
    if (result == 0) {
        handle->running = true;
        fr_running_handle = handle;
    }
    pthread_mutex_unlock(&handle->lifecycle);
    pthread_mutex_unlock(&fr_global_lifecycle);
    return result == 0 ? FRCoreStatusOK : FRCoreStatusConfigureFailed;
}

void fr_core_stop(FRCoreHandle *handle) {
    if (!handle || !handle->core) {
        return;
    }

    pthread_mutex_lock(&fr_global_lifecycle);
    pthread_mutex_lock(&handle->lifecycle);
    fr_stop_locked(handle);
    if (fr_running_handle == handle) {
        fr_running_handle = NULL;
    }
    pthread_mutex_unlock(&handle->lifecycle);
    pthread_mutex_unlock(&fr_global_lifecycle);
}

void fr_core_close(FRCoreHandle *handle) {
    if (!handle) {
        return;
    }

    pthread_mutex_lock(&fr_global_lifecycle);
    pthread_mutex_lock(&handle->lifecycle);
    fr_stop_locked(handle);
    if (fr_running_handle == handle) {
        fr_running_handle = NULL;
    }

    /* The stop above has joined the worker.  Clear all callbacks and the host
     * view before destroying the upstream object so no worker or renderer can
     * retain host state while the dylib is unloaded. */
    if (handle->core) {
        handle->set_log_callback(handle->core, NULL, NULL);
        (void) handle->set_window(handle->core, NULL);
    }

    if (handle->core) {
        handle->destroy(handle->core);
        handle->core = NULL;
    }

    if (handle->library) {
        dlclose(handle->library);
        handle->library = NULL;
    }

    pthread_mutex_unlock(&handle->lifecycle);
    pthread_mutex_unlock(&fr_global_lifecycle);
    pthread_mutex_destroy(&handle->lifecycle);
    free(handle);
}
