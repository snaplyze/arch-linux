#define _GNU_SOURCE

#include <ctype.h>
#include <errno.h>
#include <dirent.h>
#include <fcntl.h>
#include <grp.h>
#include <linux/close_range.h>
#include <linux/memfd.h>
#include <limits.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/prctl.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/xattr.h>
#include <unistd.h>

#ifndef ALI_ACCEPTED_COMMIT_SHA
#error "ALI_ACCEPTED_COMMIT_SHA must be supplied by the root-only sealing step"
#endif
#ifndef ALI_ACCEPTED_TREE_SHA
#error "ALI_ACCEPTED_TREE_SHA must be supplied by the root-only sealing step"
#endif
#ifndef ALI_ACCEPTED_TREE_SHA256
#error "ALI_ACCEPTED_TREE_SHA256 must be supplied by the root-only sealing step"
#endif
#ifndef ALI_SIGNING_UID
#error "ALI_SIGNING_UID must be supplied by the root-only sealing step"
#endif
#ifndef ALI_SIGNING_GID
#error "ALI_SIGNING_GID must be supplied by the root-only sealing step"
#endif

#define REQUEST_MAX 16384U
#define PASSPHRASE_MAX 4096U
#define HOME_FD 6
#define PASSPHRASE_FD 7
#define BROKER_FD 8
#define MAX_PUBLIC_PATHS 6U
#define ACCOUNT_NAME "arch-linux-signing"

static const char broker_message[] = "arch-linux-offline-broker-v1\n";
static const char inspection_message[] = "arch-linux-offline-inspection-v1\n";
static const char authenticated_message[] = "arch-linux-offline-parent-authenticated-v1\n";

struct invocation_paths {
    char values[MAX_PUBLIC_PATHS][PATH_MAX];
    size_t count;
};

static bool write_all(int descriptor, const char *buffer, size_t size);
static bool read_exact(int descriptor, char *buffer, size_t size);

static int fail(void) {
    static const char message[] = "ERROR: sealed offline signing launcher failed\n";
    ssize_t ignored = write(STDERR_FILENO, message, sizeof(message) - 1U);
    (void)ignored;
    return 1;
}

static bool clean_initial_process(void) {
    const struct rlimit no_core = {0U, 0U};
    if (syscall(SYS_close_range, 3U, UINT_MAX, CLOSE_RANGE_UNSHARE) != 0 || environ[0] != NULL ||
        setrlimit(RLIMIT_CORE, &no_core) != 0) {
        return false;
    }
    struct stat input_metadata;
    struct stat output_metadata;
    struct stat error_metadata;
    return fstat(STDIN_FILENO, &input_metadata) == 0 && S_ISFIFO(input_metadata.st_mode) &&
           fstat(STDOUT_FILENO, &output_metadata) == 0 && !S_ISSOCK(output_metadata.st_mode) &&
           fstat(STDERR_FILENO, &error_metadata) == 0 && !S_ISSOCK(error_metadata.st_mode);
}

static bool same_identity(const struct stat *left, const struct stat *right) {
    return left->st_dev == right->st_dev && left->st_ino == right->st_ino &&
           left->st_uid == right->st_uid && left->st_gid == right->st_gid &&
           left->st_mode == right->st_mode && left->st_nlink == right->st_nlink &&
           left->st_size == right->st_size &&
           left->st_mtim.tv_sec == right->st_mtim.tv_sec &&
           left->st_mtim.tv_nsec == right->st_mtim.tv_nsec &&
           left->st_ctim.tv_sec == right->st_ctim.tv_sec &&
           left->st_ctim.tv_nsec == right->st_ctim.tv_nsec;
}

static bool no_extended_attributes(int descriptor) {
    return flistxattr(descriptor, NULL, 0U) == 0;
}

static bool process_real_uid(pid_t pid, uid_t *result) {
    char path[64];
    int count = snprintf(path, sizeof(path), "/proc/%ld/status", (long)pid);
    if (count <= 0 || (size_t)count >= sizeof(path)) {
        return false;
    }
    int descriptor = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (descriptor < 0) {
        return false;
    }
    char buffer[8192];
    ssize_t size = read(descriptor, buffer, sizeof(buffer) - 1U);
    int saved = errno;
    (void)close(descriptor);
    errno = saved;
    if (size <= 0 || (size_t)size >= sizeof(buffer)) {
        return false;
    }
    buffer[size] = '\0';
    char *line = strstr(buffer, "Uid:\t");
    if (line == NULL) {
        return false;
    }
    unsigned long value = 0U;
    unsigned long effective = 0U;
    unsigned long saved_set = 0U;
    unsigned long filesystem = 0U;
    if (sscanf(line, "Uid:\t%lu %lu %lu %lu", &value, &effective, &saved_set, &filesystem) != 4 ||
        value > UINT_MAX) {
        return false;
    }
    *result = (uid_t)value;
    return true;
}

static bool process_credentials_exact(pid_t pid, uid_t expected_uid, gid_t expected_gid) {
    char path[64];
    int count = snprintf(path, sizeof(path), "/proc/%ld/status", (long)pid);
    if (count <= 0 || (size_t)count >= sizeof(path)) {
        return false;
    }
    int descriptor = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (descriptor < 0) {
        return false;
    }
    char buffer[8192];
    ssize_t size = read(descriptor, buffer, sizeof(buffer) - 1U);
    int saved = errno;
    (void)close(descriptor);
    errno = saved;
    if (size <= 0 || (size_t)size >= sizeof(buffer)) {
        return false;
    }
    buffer[size] = '\0';
    char *uid_line = strstr(buffer, "Uid:\t");
    char *gid_line = strstr(buffer, "Gid:\t");
    unsigned long uid[4] = {0U, 0U, 0U, 0U};
    unsigned long gid[4] = {0U, 0U, 0U, 0U};
    if (uid_line == NULL || gid_line == NULL ||
        sscanf(uid_line, "Uid:\t%lu %lu %lu %lu", &uid[0], &uid[1], &uid[2], &uid[3]) != 4 ||
        sscanf(gid_line, "Gid:\t%lu %lu %lu %lu", &gid[0], &gid[1], &gid[2], &gid[3]) != 4) {
        return false;
    }
    for (size_t index = 0U; index < 4U; ++index) {
        if (uid[index] != (unsigned long)expected_uid || gid[index] != (unsigned long)expected_gid) {
            return false;
        }
    }
    return true;
}

static bool uid_processes_are_exact(uid_t expected_uid, pid_t first, pid_t second) {
    DIR *processes = opendir("/proc");
    if (processes == NULL) {
        return false;
    }
    bool valid = true;
    size_t matching = 0U;
    const size_t expected = first > 0 ? (second > 0 ? 2U : 1U) : 0U;
    struct dirent *entry = NULL;
    while ((entry = readdir(processes)) != NULL) {
        char *end = NULL;
        errno = 0;
        long value = strtol(entry->d_name, &end, 10);
        if (errno != 0 || end == entry->d_name || *end != '\0' || value <= 0 || value > INT_MAX) {
            continue;
        }
        uid_t candidate_uid = (uid_t)-1;
        if (!process_real_uid((pid_t)value, &candidate_uid)) {
            continue;
        }
        if (candidate_uid == expected_uid) {
            matching += 1U;
            if (first <= 0 || ((pid_t)value != first && (second <= 0 || (pid_t)value != second))) {
                valid = false;
                break;
            }
        }
    }
    int saved = errno;
    (void)closedir(processes);
    errno = saved;
    return valid && matching == expected;
}

static bool dedicated_account_processes_are_exact(pid_t first, pid_t second) {
    if (getuid() != (uid_t)ALI_SIGNING_UID || geteuid() != (uid_t)ALI_SIGNING_UID ||
        getgid() != (gid_t)ALI_SIGNING_GID || getegid() != (gid_t)ALI_SIGNING_GID ||
        getgroups(0, NULL) != 0) {
        return false;
    }
    return uid_processes_are_exact((uid_t)ALI_SIGNING_UID, first, second);
}

static bool dedicated_account_is_quiescent(void) {
    if (getuid() != (uid_t)ALI_SIGNING_UID || geteuid() != (uid_t)ALI_SIGNING_UID ||
        getgid() != (gid_t)ALI_SIGNING_GID || getegid() != (gid_t)ALI_SIGNING_GID ||
        getgroups(0, NULL) != 0) {
        return false;
    }
    return dedicated_account_processes_are_exact(getpid(), 0);
}

static char *read_root_policy_file(const char *path) {
    struct stat before;
    if (lstat(path, &before) != 0 || !S_ISREG(before.st_mode) || before.st_uid != 0U ||
        (before.st_mode & 0022U) != 0U || before.st_nlink != 1U ||
        before.st_size <= 0 || before.st_size > 1024 * 1024) {
        return NULL;
    }
    int descriptor = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (descriptor < 0) {
        return NULL;
    }
    char *buffer = calloc((size_t)before.st_size + 1U, 1U);
    size_t used = 0U;
    bool valid = buffer != NULL;
    while (valid && used < (size_t)before.st_size) {
        ssize_t count = read(descriptor, buffer + used, (size_t)before.st_size - used);
        if (count < 0 && errno == EINTR) {
            continue;
        }
        if (count <= 0) {
            valid = false;
            break;
        }
        used += (size_t)count;
    }
    char extra = '\0';
    ssize_t extra_count = valid ? read(descriptor, &extra, 1U) : -1;
    struct stat opened;
    struct stat after;
    valid = valid && extra_count == 0 && used == (size_t)before.st_size &&
            fstat(descriptor, &opened) == 0 && lstat(path, &after) == 0 &&
            same_identity(&before, &opened) && same_identity(&opened, &after) &&
            buffer[used - 1U] == '\n' && strlen(buffer) == used;
    int saved = errno;
    (void)close(descriptor);
    errno = saved;
    if (!valid) {
        free(buffer);
        return NULL;
    }
    return buffer;
}

static bool split_fields(char *line, char **fields, size_t expected) {
    if (expected == 0U) {
        return false;
    }
    size_t count = 1U;
    fields[0] = line;
    for (char *cursor = line; *cursor != '\0'; ++cursor) {
        if (*cursor != ':') {
            continue;
        }
        if (count >= expected) {
            return false;
        }
        *cursor = '\0';
        fields[count++] = cursor + 1;
    }
    return count == expected;
}

static bool decimal_id_is(const char *value, unsigned long expected) {
    if (value[0] == '\0' || strspn(value, "0123456789") != strlen(value)) {
        return false;
    }
    errno = 0;
    char *end = NULL;
    unsigned long actual = strtoul(value, &end, 10);
    return errno == 0 && end != value && *end == '\0' && actual == expected;
}

static bool member_list_contains(const char *members, const char *account) {
    size_t account_size = strlen(account);
    const char *cursor = members;
    while (*cursor != '\0') {
        const char *end = strchr(cursor, ',');
        size_t size = end == NULL ? strlen(cursor) : (size_t)(end - cursor);
        if (size == account_size && memcmp(cursor, account, size) == 0) {
            return true;
        }
        if (end == NULL) {
            break;
        }
        cursor = end + 1;
    }
    return false;
}

static bool passwd_policy_is_exact(char *contents) {
    size_t matches = 0U;
    char *cursor = contents;
    while (*cursor != '\0') {
        char *end = strchr(cursor, '\n');
        if (end == NULL) {
            return false;
        }
        *end = '\0';
        if (*cursor != '\0') {
            char *fields[7];
            if (!split_fields(cursor, fields, 7U)) {
                return false;
            }
            bool target_name = strcmp(fields[0], ACCOUNT_NAME) == 0;
            bool target_uid = decimal_id_is(fields[2], ALI_SIGNING_UID);
            if (target_name || target_uid) {
                matches += 1U;
                if (!target_name || !target_uid || strcmp(fields[1], "x") != 0 ||
                    !decimal_id_is(fields[3], ALI_SIGNING_GID) ||
                    strcmp(fields[5], "/nonexistent") != 0 ||
                    strcmp(fields[6], "/usr/sbin/nologin") != 0) {
                    return false;
                }
            }
        }
        cursor = end + 1;
    }
    return matches == 1U;
}

static bool group_policy_is_exact(char *contents) {
    size_t matches = 0U;
    char *cursor = contents;
    while (*cursor != '\0') {
        char *end = strchr(cursor, '\n');
        if (end == NULL) {
            return false;
        }
        *end = '\0';
        if (*cursor != '\0') {
            char *fields[4];
            if (!split_fields(cursor, fields, 4U)) {
                return false;
            }
            bool target_name = strcmp(fields[0], ACCOUNT_NAME) == 0;
            bool target_gid = decimal_id_is(fields[2], ALI_SIGNING_GID);
            if (target_name || target_gid) {
                matches += 1U;
                if (!target_name || !target_gid || strcmp(fields[1], "x") != 0 ||
                    fields[3][0] != '\0') {
                    return false;
                }
            } else if (member_list_contains(fields[3], ACCOUNT_NAME)) {
                return false;
            }
        }
        cursor = end + 1;
    }
    return matches == 1U;
}

static bool shadow_policy_is_exact(char *contents) {
    size_t matches = 0U;
    char *cursor = contents;
    while (*cursor != '\0') {
        char *end = strchr(cursor, '\n');
        if (end == NULL) {
            return false;
        }
        *end = '\0';
        if (*cursor != '\0') {
            char *fields[9];
            if (!split_fields(cursor, fields, 9U)) {
                return false;
            }
            if (strcmp(fields[0], ACCOUNT_NAME) == 0) {
                matches += 1U;
                if (fields[1][0] != '!' && fields[1][0] != '*') {
                    return false;
                }
            }
        }
        cursor = end + 1;
    }
    return matches == 1U;
}

static bool validate_account_and_drop_privileges(void) {
    const struct rlimit no_core = {0U, 0U};
    uid_t real_uid = (uid_t)-1;
    uid_t effective_uid = (uid_t)-1;
    uid_t saved_uid = (uid_t)-1;
    gid_t real_gid = (gid_t)-1;
    gid_t effective_gid = (gid_t)-1;
    gid_t saved_gid = (gid_t)-1;
    if (setrlimit(RLIMIT_CORE, &no_core) != 0 || prctl(PR_SET_DUMPABLE, 0, 0, 0, 0) != 0 ||
        getresuid(&real_uid, &effective_uid, &saved_uid) != 0 ||
        getresgid(&real_gid, &effective_gid, &saved_gid) != 0 ||
        real_uid != 0U || effective_uid != 0U || saved_uid != 0U ||
        real_gid != 0U || effective_gid != 0U || saved_gid != 0U) {
        return false;
    }
    struct stat nonexistent;
    errno = 0;
    if (lstat("/nonexistent", &nonexistent) == 0 || errno != ENOENT) {
        return false;
    }
    char *passwd_data = read_root_policy_file("/etc/passwd");
    char *group_data = read_root_policy_file("/etc/group");
    char *shadow_data = read_root_policy_file("/etc/shadow");
    size_t shadow_size = shadow_data == NULL ? 0U : strlen(shadow_data);
    bool valid = passwd_data != NULL && group_data != NULL && shadow_data != NULL &&
                 passwd_policy_is_exact(passwd_data) && group_policy_is_exact(group_data) &&
                 shadow_policy_is_exact(shadow_data) &&
                 uid_processes_are_exact((uid_t)ALI_SIGNING_UID, 0, 0);
    if (shadow_data != NULL) {
        explicit_bzero(shadow_data, shadow_size);
    }
    free(shadow_data);
    free(group_data);
    free(passwd_data);
    if (!valid || setgroups(0, NULL) != 0 ||
        setresgid((gid_t)ALI_SIGNING_GID, (gid_t)ALI_SIGNING_GID, (gid_t)ALI_SIGNING_GID) != 0 ||
        setresuid((uid_t)ALI_SIGNING_UID, (uid_t)ALI_SIGNING_UID, (uid_t)ALI_SIGNING_UID) != 0) {
        return false;
    }
    return process_credentials_exact(getpid(), (uid_t)ALI_SIGNING_UID, (gid_t)ALI_SIGNING_GID) &&
           dedicated_account_is_quiescent();
}

static bool initial_user_namespace(void) {
    char buffer[256];
    int descriptor = open("/proc/self/uid_map", O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (descriptor < 0) {
        return false;
    }
    ssize_t count = read(descriptor, buffer, sizeof(buffer) - 1U);
    int saved = errno;
    (void)close(descriptor);
    errno = saved;
    if (count <= 0 || (size_t)count >= sizeof(buffer)) {
        return false;
    }
    buffer[count] = '\0';
    unsigned long long inside = 1U;
    unsigned long long outside = 1U;
    unsigned long long length = 0U;
    char extra = '\0';
    return sscanf(buffer, "%llu %llu %llu %c", &inside, &outside, &length, &extra) == 3 &&
           inside == 0U && outside == 0U && length == 4294967295ULL;
}

static bool safe_root_object(const char *path, mode_t type, mode_t mode) {
    struct stat metadata;
    if (lstat(path, &metadata) != 0) {
        return false;
    }
    return (metadata.st_mode & S_IFMT) == type && metadata.st_uid == 0U && metadata.st_gid == 0U &&
           (metadata.st_mode & 07777U) == mode && metadata.st_nlink == 1U;
}

static bool safe_root_directory(const char *path) {
    struct stat metadata;
    if (lstat(path, &metadata) != 0) {
        return false;
    }
    return S_ISDIR(metadata.st_mode) && metadata.st_uid == 0U && metadata.st_gid == 0U &&
           (metadata.st_mode & 07777U) == 0555U;
}

static bool exact_suffix(const char *value, const char *suffix) {
    size_t value_size = strlen(value);
    size_t suffix_size = strlen(suffix);
    return value_size > suffix_size && strcmp(value + value_size - suffix_size, suffix) == 0;
}

static bool derive_paths(char *root, size_t root_size, char *launcher, size_t launcher_size,
                         char *verifier, size_t verifier_size, char *entry, size_t entry_size) {
    ssize_t count = readlink("/proc/self/exe", launcher, launcher_size - 1U);
    if (count <= 0 || (size_t)count >= launcher_size - 1U) {
        return false;
    }
    launcher[count] = '\0';
    static const char suffix[] = "/repository/offline-signing-launcher";
    if (!exact_suffix(launcher, suffix)) {
        return false;
    }
    size_t root_length = strlen(launcher) - (sizeof(suffix) - 1U);
    if (root_length == 0U || root_length >= root_size) {
        return false;
    }
    memcpy(root, launcher, root_length);
    root[root_length] = '\0';
    int verifier_count = snprintf(verifier, verifier_size, "%s/repository/verify-sealed-offline-code.py", root);
    int entry_count = snprintf(entry, entry_size, "%s/repository/run-offline-signing.sh", root);
    return verifier_count > 0 && (size_t)verifier_count < verifier_size && entry_count > 0 &&
           (size_t)entry_count < entry_size;
}

static bool verifier_passes(const char *root, const char *verifier) {
    pid_t child = fork();
    if (child < 0) {
        return false;
    }
    if (child == 0) {
        if (clearenv() != 0 || setenv("HOME", "/nonexistent", 1) != 0 ||
            setenv("LANG", "C", 1) != 0 || setenv("LC_ALL", "C", 1) != 0 ||
            setenv("PATH", "/usr/bin:/bin", 1) != 0 || setenv("TMPDIR", "/tmp", 1) != 0) {
            _exit(126);
        }
        char *const arguments[] = {
            "/usr/bin/python3", "-I", (char *)verifier, (char *)root,
            (char *)ALI_ACCEPTED_COMMIT_SHA, (char *)ALI_ACCEPTED_TREE_SHA,
            (char *)ALI_ACCEPTED_TREE_SHA256, NULL,
        };
        execve(arguments[0], arguments, environ);
        _exit(126);
    }
    int status = 0;
    while (waitpid(child, &status, 0) < 0) {
        if (errno != EINTR) {
            return false;
        }
    }
    return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

static bool safe_text(const char *value) {
    if (value[0] != '/' || strlen(value) >= PATH_MAX) {
        return false;
    }
    for (const unsigned char *cursor = (const unsigned char *)value; *cursor != '\0'; ++cursor) {
        if (*cursor < 0x20U || *cursor == 0x7fU) {
            return false;
        }
    }
    return true;
}

static bool lowercase_hex(const char *value, size_t size) {
    if (strlen(value) != size) {
        return false;
    }
    for (size_t index = 0U; index < size; ++index) {
        if (!isdigit((unsigned char)value[index]) &&
            (value[index] < 'a' || value[index] > 'f')) {
            return false;
        }
    }
    return true;
}

static bool semver_triplet(const char *value) {
    unsigned int components = 0U;
    bool digit = false;
    for (const unsigned char *cursor = (const unsigned char *)value; *cursor != '\0'; ++cursor) {
        if (isdigit(*cursor)) {
            digit = true;
            continue;
        }
        if (*cursor != '.' || !digit || components >= 2U) {
            return false;
        }
        components += 1U;
        digit = false;
    }
    return digit && components == 2U;
}

static bool canonical_existing_path(const char *path, bool directory, char *result) {
    struct stat metadata;
    if (path[0] != '/' || realpath(path, result) == NULL || strcmp(path, result) != 0 ||
        lstat(path, &metadata) != 0) {
        return false;
    }
    return directory ? S_ISDIR(metadata.st_mode) && metadata.st_nlink >= 2U :
                       S_ISREG(metadata.st_mode) && metadata.st_nlink == 1U;
}

static bool canonical_missing_output(const char *path, char *result) {
    if (path[0] != '/' || strlen(path) >= PATH_MAX) {
        return false;
    }
    char parent_input[PATH_MAX];
    if (snprintf(parent_input, sizeof(parent_input), "%s", path) <= 0) {
        return false;
    }
    char *slash = strrchr(parent_input, '/');
    if (slash == NULL || slash[1] == '\0' || strcmp(slash + 1, ".") == 0 ||
        strcmp(slash + 1, "..") == 0) {
        return false;
    }
    char basename[NAME_MAX + 1U];
    if (strlen(slash + 1) > NAME_MAX ||
        snprintf(basename, sizeof(basename), "%s", slash + 1) <= 0) {
        return false;
    }
    if (slash == parent_input) {
        slash[1] = '\0';
    } else {
        *slash = '\0';
    }
    char parent[PATH_MAX];
    struct stat metadata;
    if (realpath(parent_input, parent) == NULL || strcmp(parent_input, parent) != 0 ||
        lstat(parent, &metadata) != 0 || !S_ISDIR(metadata.st_mode)) {
        return false;
    }
    int count = snprintf(result, PATH_MAX, "%s%s%s", parent,
                         strcmp(parent, "/") == 0 ? "" : "/", basename);
    if (count <= 0 || count >= PATH_MAX || strcmp(result, path) != 0) {
        return false;
    }
    errno = 0;
    if (lstat(result, &metadata) == 0 || errno != ENOENT) {
        return false;
    }
    return true;
}

static bool add_public_path(struct invocation_paths *paths, const char *value,
                            bool directory, bool output) {
    if (paths->count >= MAX_PUBLIC_PATHS) {
        return false;
    }
    char *destination = paths->values[paths->count];
    bool valid = output ? canonical_missing_output(value, destination) :
                          canonical_existing_path(value, directory, destination);
    if (!valid) {
        return false;
    }
    paths->count += 1U;
    return true;
}

static int option_index(const char *value, const char *const *options, size_t count) {
    for (size_t index = 0U; index < count; ++index) {
        if (strcmp(value, options[index]) == 0) {
            return (int)index;
        }
    }
    return -1;
}

static bool parse_invocation(int argc, char **argv, const char *root,
                             struct invocation_paths *paths) {
    static const char *const snapshot_options[] = {
        "--unsigned", "--installer", "--output", "--release-version",
        "--build-metadata-sha256", "--unsigned-manifest-sha256",
    };
    static const char *const finalize_options[] = {
        "--phase-a", "--output", "--release-version", "--build-metadata-sha256",
        "--unsigned-manifest-sha256", "--snapshot-sha256", "--minimal-run",
        "--stock-run", "--marble-run",
    };
    const bool snapshot = strcmp(argv[1], "snapshot") == 0;
    const char *const *options = snapshot ? snapshot_options : finalize_options;
    const size_t option_count = snapshot ? sizeof(snapshot_options) / sizeof(snapshot_options[0]) :
                                           sizeof(finalize_options) / sizeof(finalize_options[0]);
    if ((size_t)argc != 2U + option_count * 2U) {
        return false;
    }
    bool seen[9] = {false};
    char expected_installer[PATH_MAX];
    int installer_count = snprintf(expected_installer, sizeof(expected_installer),
                                   "%s/arch-linux-installer.sh", root);
    if (installer_count <= 0 || (size_t)installer_count >= sizeof(expected_installer)) {
        return false;
    }
    for (int argument = 2; argument < argc; argument += 2) {
        int index = option_index(argv[argument], options, option_count);
        const char *value = argv[argument + 1];
        if (index < 0 || seen[index] || value[0] == '\0') {
            return false;
        }
        seen[index] = true;
        const char *option = options[index];
        if (strcmp(option, "--release-version") == 0) {
            if (!semver_triplet(value)) {
                return false;
            }
        } else if (strstr(option, "sha256") != NULL) {
            if (!lowercase_hex(value, 64U)) {
                return false;
            }
        } else {
            bool output = strcmp(option, "--output") == 0;
            bool directory = strcmp(option, "--installer") != 0;
            if (!add_public_path(paths, value, directory, output)) {
                return false;
            }
            if (strcmp(option, "--installer") == 0 && strcmp(value, expected_installer) != 0) {
                return false;
            }
        }
    }
    for (size_t index = 0U; index < option_count; ++index) {
        if (!seen[index]) {
            return false;
        }
    }
    return paths->count == (snapshot ? 3U : 5U);
}

static bool component_overlap(const char *left, const char *right) {
    size_t left_size = strlen(left);
    size_t right_size = strlen(right);
    if (strcmp(left, right) == 0) {
        return true;
    }
    if (left_size < right_size && strncmp(left, right, left_size) == 0 &&
        (left_size == 1U || right[left_size] == '/')) {
        return true;
    }
    return right_size < left_size && strncmp(right, left, right_size) == 0 &&
           (right_size == 1U || left[right_size] == '/');
}

static bool private_paths_are_disjoint(const char *home, const char *passphrase,
                                       const struct invocation_paths *paths) {
    char canonical_home[PATH_MAX];
    char canonical_passphrase[PATH_MAX];
    struct stat metadata;
    if (realpath(home, canonical_home) == NULL || strcmp(home, canonical_home) != 0 ||
        realpath(passphrase, canonical_passphrase) == NULL ||
        strcmp(passphrase, canonical_passphrase) != 0 ||
        lstat(canonical_home, &metadata) != 0 || !S_ISDIR(metadata.st_mode) ||
        lstat(canonical_passphrase, &metadata) != 0 || !S_ISREG(metadata.st_mode) ||
        component_overlap(canonical_home, canonical_passphrase)) {
        return false;
    }
    for (size_t index = 0U; index < paths->count; ++index) {
        if (component_overlap(canonical_home, paths->values[index]) ||
            component_overlap(canonical_passphrase, paths->values[index])) {
            return false;
        }
    }
    return true;
}

static bool process_start_time(pid_t pid, char *result, size_t result_size) {
    char path[64];
    int path_count = snprintf(path, sizeof(path), "/proc/%ld/stat", (long)pid);
    if (path_count <= 0 || (size_t)path_count >= sizeof(path)) {
        return false;
    }
    int descriptor = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (descriptor < 0) {
        return false;
    }
    char buffer[8192];
    ssize_t count = read(descriptor, buffer, sizeof(buffer) - 1U);
    int saved = errno;
    (void)close(descriptor);
    errno = saved;
    if (count <= 0 || (size_t)count >= sizeof(buffer)) {
        return false;
    }
    buffer[count] = '\0';
    char *cursor = strrchr(buffer, ')');
    if (cursor == NULL || cursor[1] != ' ') {
        return false;
    }
    cursor += 2;
    for (unsigned int field = 3U; field <= 22U; ++field) {
        char *end = cursor;
        while (*end != '\0' && *end != ' ' && *end != '\n') {
            ++end;
        }
        if (end == cursor) {
            return false;
        }
        if (field == 22U) {
            size_t size = (size_t)(end - cursor);
            if (size == 0U || size >= result_size) {
                return false;
            }
            memcpy(result, cursor, size);
            result[size] = '\0';
            return result[0] != '0' && strspn(result, "0123456789") == size;
        }
        if (*end != ' ') {
            return false;
        }
        cursor = end + 1;
    }
    return false;
}

static int open_private_home(const char *path) {
    char canonical[PATH_MAX];
    if (realpath(path, canonical) == NULL || strcmp(path, canonical) != 0) {
        return -1;
    }
    struct stat before;
    if (lstat(path, &before) != 0) {
        return -1;
    }
    int descriptor = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    if (descriptor < 0) {
        return -1;
    }
    struct stat opened;
    struct stat after;
    bool valid = fstat(descriptor, &opened) == 0 && lstat(path, &after) == 0 &&
                 same_identity(&before, &opened) && same_identity(&opened, &after) &&
                 S_ISDIR(opened.st_mode) && opened.st_uid == getuid() &&
                 opened.st_gid == getgid() && (opened.st_mode & 07777U) == 0700U &&
                 no_extended_attributes(descriptor);
    if (valid) {
        return descriptor;
    }
    int saved = errno;
    (void)close(descriptor);
    errno = saved;
    return -1;
}

static int capture_private_passphrase(const char *path) {
    char canonical[PATH_MAX];
    if (realpath(path, canonical) == NULL || strcmp(path, canonical) != 0) {
        return -1;
    }
    struct stat before;
    if (lstat(path, &before) != 0) {
        return -1;
    }
    int source = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (source < 0) {
        return -1;
    }
    struct stat opened;
    unsigned char buffer[PASSPHRASE_MAX];
    memset(buffer, 0, sizeof(buffer));
    size_t used = 0U;
    bool valid = fstat(source, &opened) == 0 && same_identity(&before, &opened) &&
                 S_ISREG(opened.st_mode) && opened.st_uid == getuid() &&
                 opened.st_gid == getgid() && (opened.st_mode & 07777U) == 0600U &&
                 opened.st_nlink == 1U && opened.st_size > 0 &&
                 opened.st_size <= (off_t)sizeof(buffer) && no_extended_attributes(source);
    while (valid && used < (size_t)opened.st_size) {
        ssize_t count = read(source, buffer + used, (size_t)opened.st_size - used);
        if (count < 0 && errno == EINTR) {
            continue;
        }
        if (count <= 0) {
            valid = false;
            break;
        }
        used += (size_t)count;
    }
    unsigned char extra = 0U;
    ssize_t extra_count = valid ? read(source, &extra, 1U) : -1;
    struct stat after_read;
    struct stat current;
    valid = valid && extra_count == 0 && used == (size_t)opened.st_size &&
            fstat(source, &after_read) == 0 && lstat(path, &current) == 0 &&
            same_identity(&opened, &after_read) && same_identity(&after_read, &current);
    int saved = errno;
    (void)close(source);
    errno = saved;
    if (!valid) {
        explicit_bzero(buffer, sizeof(buffer));
        return -1;
    }

    int captured = memfd_create("arch-linux-offline-passphrase", MFD_CLOEXEC | MFD_ALLOW_SEALING);
    if (captured < 0 || fchmod(captured, 0600U) != 0 ||
        !write_all(captured, (const char *)buffer, used) || lseek(captured, 0, SEEK_SET) != 0 ||
        fcntl(captured, F_ADD_SEALS, F_SEAL_WRITE | F_SEAL_GROW | F_SEAL_SHRINK | F_SEAL_SEAL) != 0 ||
        fcntl(captured, F_GET_SEALS) !=
            (F_SEAL_WRITE | F_SEAL_GROW | F_SEAL_SHRINK | F_SEAL_SEAL)) {
        saved = errno;
        if (captured >= 0) {
            (void)close(captured);
        }
        explicit_bzero(buffer, sizeof(buffer));
        errno = saved;
        return -1;
    }
    explicit_bzero(buffer, sizeof(buffer));
    return captured;
}

static bool move_descriptor(int source, int destination) {
    if (source == destination) {
        int flags = fcntl(source, F_GETFD);
        return flags >= 0 && fcntl(source, F_SETFD, flags & ~FD_CLOEXEC) == 0;
    }
    if (dup3(source, destination, 0) != destination) {
        return false;
    }
    return close(source) == 0;
}

static bool read_request(char *buffer, size_t size, char **gnupg_home, char **passphrase_file) {
    size_t used = 0U;
    while (used < size - 1U) {
        ssize_t count = read(STDIN_FILENO, buffer + used, size - 1U - used);
        if (count < 0) {
            if (errno == EINTR) {
                continue;
            }
            return false;
        }
        if (count == 0) {
            break;
        }
        used += (size_t)count;
    }
    if (used == 0U || used >= size - 1U) {
        return false;
    }
    buffer[used] = '\0';
    char *first_newline = memchr(buffer, '\n', used);
    if (first_newline == NULL) {
        return false;
    }
    char *second = first_newline + 1;
    size_t remaining = used - (size_t)(second - buffer);
    char *second_newline = memchr(second, '\n', remaining);
    if (second_newline == NULL || second_newline != buffer + used - 1U ||
        memchr(buffer, '\0', used) != NULL) {
        return false;
    }
    *first_newline = '\0';
    *second_newline = '\0';
    if (!safe_text(buffer) || !safe_text(second)) {
        return false;
    }
    *gnupg_home = buffer;
    *passphrase_file = second;
    return true;
}

static bool write_all(int descriptor, const char *buffer, size_t size) {
    size_t offset = 0U;
    while (offset < size) {
        ssize_t count = write(descriptor, buffer + offset, size - offset);
        if (count < 0) {
            if (errno == EINTR) {
                continue;
            }
            return false;
        }
        if (count == 0) {
            return false;
        }
        offset += (size_t)count;
    }
    return true;
}

static bool read_exact(int descriptor, char *buffer, size_t size) {
    size_t offset = 0U;
    while (offset < size) {
        ssize_t count = read(descriptor, buffer + offset, size - offset);
        if (count < 0) {
            if (errno == EINTR) {
                continue;
            }
            return false;
        }
        if (count == 0) {
            return false;
        }
        offset += (size_t)count;
    }
    return true;
}

static int launch_signer(const char *root, const char *launcher, const char *entry,
                         int argc, char **argv) {
    struct stat home_metadata;
    struct stat passphrase_metadata;
    struct stat launcher_metadata;
    char home_identity[96];
    char passphrase_identity[128];
    char launcher_identity[256];
    char launcher_start[64];
    char signing_uid[32];
    char signing_gid[32];
    if (fstat(HOME_FD, &home_metadata) != 0 || fstat(PASSPHRASE_FD, &passphrase_metadata) != 0 ||
        lstat(launcher, &launcher_metadata) != 0 ||
        snprintf(home_identity, sizeof(home_identity), "%llu:%llu",
                 (unsigned long long)home_metadata.st_dev,
                 (unsigned long long)home_metadata.st_ino) <= 0 ||
        snprintf(passphrase_identity, sizeof(passphrase_identity), "%llu:%llu:%llu",
                 (unsigned long long)passphrase_metadata.st_dev,
                 (unsigned long long)passphrase_metadata.st_ino,
                 (unsigned long long)passphrase_metadata.st_size) <= 0 ||
        snprintf(launcher_identity, sizeof(launcher_identity), "%llu:%llu:%u:%u:%o:%llu:%lld",
                 (unsigned long long)launcher_metadata.st_dev,
                 (unsigned long long)launcher_metadata.st_ino,
                 (unsigned int)launcher_metadata.st_uid,
                 (unsigned int)launcher_metadata.st_gid,
                 (unsigned int)(launcher_metadata.st_mode & 07777U),
                 (unsigned long long)launcher_metadata.st_nlink,
                 (long long)launcher_metadata.st_size) <= 0 ||
        snprintf(signing_uid, sizeof(signing_uid), "%u", (unsigned int)ALI_SIGNING_UID) <= 0 ||
        snprintf(signing_gid, sizeof(signing_gid), "%u", (unsigned int)ALI_SIGNING_GID) <= 0 ||
        !process_start_time(getpid(), launcher_start, sizeof(launcher_start))) {
        return 1;
    }
    int capability[2];
    if (socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, capability) != 0) {
        return 1;
    }
    pid_t child = fork();
    if (child < 0) {
        (void)close(capability[0]);
        (void)close(capability[1]);
        return 1;
    }
    if (child == 0) {
        pid_t broker_pid = getppid();
        (void)close(capability[0]);
        if (dup2(capability[1], BROKER_FD) != BROKER_FD) {
            _exit(126);
        }
        (void)close(capability[1]);
        if (prctl(PR_SET_PDEATHSIG, SIGKILL, 0, 0, 0) != 0 || getppid() != broker_pid) {
            _exit(126);
        }
        char parent[32];
        int parent_count = snprintf(parent, sizeof(parent), "%ld", (long)getppid());
        if (parent_count <= 0 || (size_t)parent_count >= sizeof(parent) || clearenv() != 0 ||
            setenv("ARCH_LINUX_OFFLINE_ACCEPTED_COMMIT", ALI_ACCEPTED_COMMIT_SHA, 1) != 0 ||
            setenv("ARCH_LINUX_OFFLINE_ACCEPTED_TREE", ALI_ACCEPTED_TREE_SHA, 1) != 0 ||
            setenv("ARCH_LINUX_OFFLINE_ACCEPTED_TREE_SHA256", ALI_ACCEPTED_TREE_SHA256, 1) != 0 ||
            setenv("ARCH_LINUX_OFFLINE_BROKER_PARENT", parent, 1) != 0 ||
            setenv("ARCH_LINUX_OFFLINE_BROKER_PARENT_START", launcher_start, 1) != 0 ||
            setenv("ARCH_LINUX_OFFLINE_CODE_ROOT", root, 1) != 0 ||
            setenv("ARCH_LINUX_OFFLINE_LAUNCHER", launcher, 1) != 0 ||
            setenv("ARCH_LINUX_OFFLINE_LAUNCHER_IDENTITY", launcher_identity, 1) != 0 ||
            setenv("ARCH_LINUX_SIGNING_HOME_IDENTITY", home_identity, 1) != 0 ||
            setenv("ARCH_LINUX_SIGNING_HOST_UID", signing_uid, 1) != 0 ||
            setenv("ARCH_LINUX_SIGNING_HOST_GID", signing_gid, 1) != 0 ||
            setenv("ARCH_LINUX_PASSPHRASE_IDENTITY", passphrase_identity, 1) != 0 ||
            setenv("HOME", "/nonexistent", 1) != 0 ||
            setenv("LANG", "C", 1) != 0 || setenv("LC_ALL", "C", 1) != 0 ||
            setenv("PATH", "/usr/bin:/bin", 1) != 0 || setenv("TMPDIR", "/tmp", 1) != 0) {
            _exit(126);
        }
        if (prctl(PR_SET_DUMPABLE, 0, 0, 0, 0) != 0) {
            _exit(126);
        }
        size_t argument_count = (size_t)argc + 4U;
        char **arguments = calloc(argument_count, sizeof(char *));
        if (arguments == NULL) {
            _exit(126);
        }
        arguments[0] = "/usr/bin/bash";
        arguments[1] = "-p";
        arguments[2] = (char *)entry;
        arguments[3] = "--sealed-broker";
        for (int index = 1; index < argc; ++index) {
            arguments[(size_t)index + 3U] = argv[index];
        }
        arguments[argument_count - 1U] = NULL;
        execve(arguments[0], arguments, environ);
        _exit(126);
    }
    (void)close(capability[1]);
    bool inspected = false;
    char acknowledgement[sizeof(authenticated_message) - 1U];
    if (prctl(PR_SET_PTRACER, (unsigned long)child, 0, 0, 0) == 0 &&
        dedicated_account_processes_are_exact(getpid(), child) &&
        process_credentials_exact(child, (uid_t)ALI_SIGNING_UID, (gid_t)ALI_SIGNING_GID) &&
        prctl(PR_SET_DUMPABLE, 1, 0, 0, 0) == 0 &&
        write_all(capability[0], inspection_message, sizeof(inspection_message) - 1U) &&
        read_exact(capability[0], acknowledgement, sizeof(acknowledgement)) &&
        memcmp(acknowledgement, authenticated_message, sizeof(acknowledgement)) == 0) {
        inspected = true;
    }
    bool nondumpable = prctl(PR_SET_DUMPABLE, 0, 0, 0, 0) == 0;
    bool sent = inspected && nondumpable &&
                dedicated_account_processes_are_exact(getpid(), child) &&
                process_credentials_exact(child, (uid_t)ALI_SIGNING_UID, (gid_t)ALI_SIGNING_GID) &&
                write_all(capability[0], broker_message, sizeof(broker_message) - 1U);
    (void)shutdown(capability[0], SHUT_RDWR);
    (void)close(capability[0]);
    int status = 0;
    while (waitpid(child, &status, 0) < 0) {
        if (errno != EINTR) {
            return 1;
        }
    }
    if (!sent || !WIFEXITED(status)) {
        return 1;
    }
    return WEXITSTATUS(status);
}

int main(int argc, char **argv) {
    if (argc < 2 || argc > 128 || (strcmp(argv[1], "snapshot") != 0 && strcmp(argv[1], "finalize") != 0) ||
        getuid() != 0U || geteuid() != 0U || !initial_user_namespace() ||
        !validate_account_and_drop_privileges() ||
        !clean_initial_process() || chdir("/") != 0 ||
        !process_credentials_exact(getpid(), (uid_t)ALI_SIGNING_UID, (gid_t)ALI_SIGNING_GID) ||
        !dedicated_account_is_quiescent()) {
        return fail();
    }
    for (int index = 1; index < argc; ++index) {
        if (strlen(argv[index]) > 4096U) {
            return fail();
        }
    }

    char root[PATH_MAX];
    char launcher[PATH_MAX];
    char verifier[PATH_MAX];
    char entry[PATH_MAX];
    if (!derive_paths(root, sizeof(root), launcher, sizeof(launcher), verifier, sizeof(verifier),
                      entry, sizeof(entry))) {
        return fail();
    }
    char repository[PATH_MAX];
    int repository_count = snprintf(repository, sizeof(repository), "%s/repository", root);
    if (repository_count <= 0 || (size_t)repository_count >= sizeof(repository) ||
        !safe_root_directory(root) || !safe_root_directory(repository) ||
        !safe_root_object(launcher, S_IFREG, 0555U) || !safe_root_object(verifier, S_IFREG, 0555U) ||
        !safe_root_object(entry, S_IFREG, 0555U) || !verifier_passes(root, verifier)) {
        return fail();
    }
    struct invocation_paths public_paths = {0};
    if (!parse_invocation(argc, argv, root, &public_paths)) {
        return fail();
    }

    if (prctl(PR_SET_DUMPABLE, 0, 0, 0, 0) != 0) {
        return fail();
    }
    char request[REQUEST_MAX];
    char *gnupg_home = NULL;
    char *passphrase_file = NULL;
    if (!read_request(request, sizeof(request), &gnupg_home, &passphrase_file)) {
        explicit_bzero(request, sizeof(request));
        return fail();
    }
    if (!private_paths_are_disjoint(gnupg_home, passphrase_file, &public_paths)) {
        explicit_bzero(request, sizeof(request));
        return fail();
    }
    int home_descriptor = open_private_home(gnupg_home);
    if (home_descriptor < 0) {
        explicit_bzero(request, sizeof(request));
        return fail();
    }
    int passphrase_descriptor = capture_private_passphrase(passphrase_file);
    if (passphrase_descriptor < 0 || !move_descriptor(home_descriptor, HOME_FD)) {
        (void)close(HOME_FD);
        if (home_descriptor >= 0) {
            (void)close(home_descriptor);
        }
        if (passphrase_descriptor >= 0) {
            (void)close(passphrase_descriptor);
        }
        explicit_bzero(request, sizeof(request));
        return fail();
    }
    home_descriptor = -1;
    if (!move_descriptor(passphrase_descriptor, PASSPHRASE_FD)) {
        (void)close(HOME_FD);
        (void)close(passphrase_descriptor);
        explicit_bzero(request, sizeof(request));
        return fail();
    }
    passphrase_descriptor = -1;
    explicit_bzero(request, sizeof(request));
    int status = launch_signer(root, launcher, entry, argc, argv);
    (void)close(HOME_FD);
    (void)close(PASSPHRASE_FD);
    return status;
}
