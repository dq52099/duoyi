#ifndef DUOYI_WIDGET_STORE_C_H
#define DUOYI_WIDGET_STORE_C_H
#include <sqlite3.h>
#include <stdint.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

/* iOS 13 may ship SQLite older than 3.31. Retain lstat/private-directory/lock
 * checks there; enable the additional SQLite open guard only when supported. */
static inline int duoyi_store_sqlite_nofollow_flag(void) {
#ifdef SQLITE_OPEN_NOFOLLOW
    return sqlite3_libversion_number() >= 3031000 ? SQLITE_OPEN_NOFOLLOW : 0;
#else
    return 0;
#endif
}

static inline int duoyi_store_bind_text(sqlite3_stmt *statement, int index,
                                        const char *text, int length) {
    return sqlite3_bind_text(statement, index, text, length, SQLITE_TRANSIENT);
}
/* 0 absent, 1 regular file, 2 directory, 3 other; -1 permission/IO error. */
static inline int duoyi_store_path_kind(const char *path) {
    struct stat info;
    if (lstat(path, &info) != 0) return errno == ENOENT ? 0 : -1;
    return S_ISREG(info.st_mode) ? 1 : S_ISDIR(info.st_mode) ? 2 : 3;
}
static inline int duoyi_store_open_lock(const char *path, int create, int writable) {
    int flags = (writable ? O_RDWR : O_RDONLY) | O_CLOEXEC | O_NOFOLLOW;
    return open(path, flags | (create ? O_CREAT : 0), 0600);
}
static inline int duoyi_store_try_lock(int descriptor, int exclusive) {
    return flock(descriptor, (exclusive ? LOCK_EX : LOCK_SH) | LOCK_NB);
}
static inline int duoyi_store_unlock(int descriptor) { return flock(descriptor, LOCK_UN); }
static inline int duoyi_store_close_fd(int descriptor) { return close(descriptor); }
static inline int duoyi_store_last_errno(void) { return errno; }
static inline int duoyi_store_lock_identity(int descriptor, uint64_t *device, uint64_t *inode) {
    struct stat info;
    if (fstat(descriptor, &info) != 0 || !S_ISREG(info.st_mode)) return 0;
    *device = (uint64_t)info.st_dev;
    *inode = (uint64_t)info.st_ino;
    return 1;
}
static inline int duoyi_store_lock_still_named(int descriptor, const char *path) {
    struct stat opened, named;
    return fstat(descriptor, &opened) == 0 && lstat(path, &named) == 0 &&
        S_ISREG(opened.st_mode) && S_ISREG(named.st_mode) &&
        opened.st_dev == named.st_dev && opened.st_ino == named.st_ino;
}
#endif
