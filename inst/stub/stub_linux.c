#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <limits.h>

/* Helper: strip the last path component (modifies path in-place). */
static void strip_last_component(char *path) {
    char *last_slash = strrchr(path, '/');
    if (last_slash != NULL && last_slash != path) {
        *last_slash = '\0';
    }
}

int main(int argc, char *argv[]) {
    char exe_path[PATH_MAX];

    /* Resolve the absolute path of this executable via /proc/self/exe. */
    ssize_t len = readlink("/proc/self/exe", exe_path, sizeof(exe_path) - 1);
    if (len < 0) {
        perror("[RDesk Stub] readlink /proc/self/exe failed");
        return 1;
    }
    exe_path[len] = '\0';

    /* Resolve symlinks so we always get a canonical path. */
    char real_exe[PATH_MAX];
    if (realpath(exe_path, real_exe) == NULL) {
        strncpy(real_exe, exe_path, PATH_MAX - 1);
        real_exe[PATH_MAX - 1] = '\0';
    }

    char bundle_root[PATH_MAX];
    strncpy(bundle_root, real_exe, PATH_MAX - 1);
    bundle_root[PATH_MAX - 1] = '\0';
    strip_last_component(bundle_root);

    /* Path to app entry point. */
    char app_r_path[PATH_MAX];
    snprintf(app_r_path, sizeof(app_r_path), "%s/app/app.R", bundle_root);

    struct stat st;
    if (stat(app_r_path, &st) != 0) {
        fprintf(stderr, "[RDesk Stub] Error: app/app.R not found at: %s\n", app_r_path);
        return 1;
    }

    /* Check if bundled R wrapper exists. */
    char r_path[PATH_MAX];
    snprintf(r_path, sizeof(r_path), "%s/R-runtime/R/bin/R", bundle_root);

    int use_bundled = (stat(r_path, &st) == 0);

    /* ---- Set up environment variables ---------------------------------- */
    char r_libs_env[PATH_MAX * 2 + 64];
    char app_name_env[256];
    char r_bundle_root_env[PATH_MAX + 32];
    snprintf(app_name_env, sizeof(app_name_env), "R_APP_NAME=%s", "{{APP_NAME}}");
    snprintf(r_bundle_root_env, sizeof(r_bundle_root_env), "R_BUNDLE_ROOT=%s", bundle_root);
    putenv("R_BUNDLE_APP=1");
    putenv(app_name_env);
    putenv(r_bundle_root_env);

    if (use_bundled) {
        char r_home_env[PATH_MAX + 16];
        snprintf(r_home_env, sizeof(r_home_env), "R_HOME=%s/R-runtime/R", bundle_root);

        snprintf(r_libs_env, sizeof(r_libs_env),
                 "R_LIBS=%s/packages/library:%s/R-runtime/R/library",
                 bundle_root, bundle_root);

        char r_share_env[PATH_MAX + 32];
        snprintf(r_share_env, sizeof(r_share_env), "R_SHARE_DIR=%s/R-runtime/R/share", bundle_root);

        char r_doc_env[PATH_MAX + 32];
        snprintf(r_doc_env, sizeof(r_doc_env), "R_DOC_DIR=%s/R-runtime/R/doc", bundle_root);

        char ld_lib_env[PATH_MAX * 2 + 64];
        char *old_ld = getenv("LD_LIBRARY_PATH");
        if (old_ld != NULL && strlen(old_ld) > 0) {
            snprintf(ld_lib_env, sizeof(ld_lib_env), "LD_LIBRARY_PATH=%s/R-runtime/R/lib:%s", bundle_root, old_ld);
        } else {
            snprintf(ld_lib_env, sizeof(ld_lib_env), "LD_LIBRARY_PATH=%s/R-runtime/R/lib", bundle_root);
        }

        putenv(r_home_env);
        putenv(r_libs_env);
        putenv(r_share_env);
        putenv(r_doc_env);
        putenv(ld_lib_env);

        char *const exec_args[] = {
            r_path,
            "--vanilla",
            "--slave",
            "-f",
            app_r_path,
            NULL
        };
        execv(r_path, exec_args);
    } else {
        // Fallback to system Rscript
        snprintf(r_libs_env, sizeof(r_libs_env), "R_LIBS_USER=%s/packages/library", bundle_root);
        putenv(r_libs_env);

        char *const exec_args[] = {
            "Rscript",
            "--vanilla",
            app_r_path,
            NULL
        };
        execvp("Rscript", exec_args);
    }

    /* execv/execvp only returns on failure. */
    perror("[RDesk Stub] exec failed to launch Rscript");
    return 1;
}
