//
//  qdl-bridge.h
//  qdl
//
//  Created by 经典 on 2025/12/24.
//

#ifndef qdl_bridge_h
#define qdl_bridge_h
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

enum qdl_storage_type {
    QDL_STORAGE_UNKNOWN,
    QDL_STORAGE_EMMC,
    QDL_STORAGE_NAND,
    QDL_STORAGE_UFS,
    QDL_STORAGE_NVME,
    QDL_STORAGE_SPINOR,
};


/* Progress callback for GUI clients. Called for each ux_progress emission.
 * task: human-readable task name (NUL-terminated).
 * value: current progress value.
 * total: total value.
 * userdata: user-provided pointer passed through qdl_set_progress_callback.
 */
typedef void (*qdl_progress_cb_t)(const char *task, unsigned int value, unsigned int total, void *userdata);

/* Register a progress callback. Passing NULL clears the callback. Thread-unsafe; callers
 * should register before starting long-running operations or ensure synchronization.
 */
void qdl_set_progress_callback(qdl_progress_cb_t cb, void *userdata);

// ===================
// QDL C API for GUI/Swift
// ===================

typedef struct {
    char serial[64];
    char product[64];
} qdl_device_info_t;

typedef enum {
    QDL_MODE_FLASH,
    QDL_MODE_PROVISION
} qdl_mode_t;

typedef enum qdl_storage_type qdl_storage_type_t;

typedef enum {
    QDL_OK = 0,
    QDL_ERR_GENERIC = -1,
    QDL_ERR_DEVICE_NOT_FOUND = -2,
    QDL_ERR_FLASH_FAILED = -3,
    QDL_ERR_PROVISION_FAILED = -4,
} qdl_error_t;

// 获取可用设备列表，返回设备数量，devices为输出数组，max_devices为最大数量
int qdl_list_devices(qdl_device_info_t *devices, int max_devices);

// 烧录/Provision 操作
int qdl_run(
    qdl_mode_t mode,
    const char *serial,
    qdl_storage_type_t storage_type,
    const char *prog_mbn,
    const char **xml_files,
    int xml_file_count,
    bool allow_missing,
    const char *include_dir,
    unsigned int out_chunk_size
);

const char* qdl_version(void);

#ifdef __cplusplus
}
#endif

#endif
