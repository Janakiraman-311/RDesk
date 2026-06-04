#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <mach-o/dyld.h>
#include <sys/stat.h>
#include <limits.h>

// Helper function to strip the last component of a path (parent directory)
static void get_parent_directory(char* path) {
    char* last_slash = strrchr(path, '/');
    if (last_slash != NULL) {
        *last_slash = '\0';
    }
}

int main(int argc, char* argv[]) {
    char exec_path[PATH_MAX];
    uint32_t size = sizeof(exec_path);

    if (_NSGetExecutablePath(exec_path, &size) != 0) {
        // Path is longer than PATH_MAX, allocate dynamically
        char* dynamic_path = malloc(size);
        if (dynamic_path == NULL || _NSGetExecutablePath(dynamic_path, &size) != 0) {
            fprintf(stderr, "[RDesk Stub] Error: Failed to resolve executable path.\n");
            if (dynamic_path) free(dynamic_path);
            return 1;
        }
        strncpy(exec_path, dynamic_path, PATH_MAX - 1);
        exec_path[PATH_MAX - 1] = '\0';
        free(dynamic_path);
    }

    // Resolve real path in case of symlinks
    char real_exec_path[PATH_MAX];
    if (realpath(exec_path, real_exec_path) == NULL) {
        // Fallback to unresolved path if realpath fails
        strncpy(real_exec_path, exec_path, PATH_MAX - 1);
        real_exec_path[PATH_MAX - 1] = '\0';
    }

    // Current path is: Contents/MacOS/MyApp
    // Move up to Contents/MacOS
    get_parent_directory(real_exec_path);
    // Move up to Contents
    get_parent_directory(real_exec_path);

    // real_exec_path is now the absolute path to Contents/
    char contents_path[PATH_MAX];
    strncpy(contents_path, real_exec_path, PATH_MAX - 1);
    contents_path[PATH_MAX - 1] = '\0';

    // Target binary: Contents/Resources/R-runtime/R/bin/Rscript
    char rscript_path[PATH_MAX];
    snprintf(rscript_path, sizeof(rscript_path), "%s/Resources/R-runtime/R/bin/Rscript", contents_path);

    // Verify Rscript exists
    struct stat st;
    if (stat(rscript_path, &st) != 0) {
        fprintf(stderr, "[RDesk Stub] Error: R runtime not found at: %s\n", rscript_path);
        return 1;
    }

    // Target R script: Contents/Resources/app/app.R
    char app_r_path[PATH_MAX];
    snprintf(app_r_path, sizeof(app_r_path), "%s/Resources/app/app.R", contents_path);

    // Set isolated environment variables for R
    char r_home_env[PATH_MAX + 32];
    char r_libs_env[PATH_MAX * 2 + 64];
    char r_share_env[PATH_MAX + 32];
    char r_doc_env[PATH_MAX + 32];
    char app_name_env[256];

    const char* app_name = "{{APP_NAME}}";

    snprintf(r_home_env, sizeof(r_home_env), "R_HOME=%s/Resources/R-runtime/R", contents_path);
    snprintf(r_libs_env, sizeof(r_libs_env), "R_LIBS=%s/Resources/packages/library:%s/Resources/R-runtime/R/library", contents_path, contents_path);
    snprintf(r_share_env, sizeof(r_share_env), "R_SHARE_DIR=%s/Resources/R-runtime/R/share", contents_path);
    snprintf(r_doc_env, sizeof(r_doc_env), "R_DOC_DIR=%s/Resources/R-runtime/R/doc", contents_path);
    snprintf(app_name_env, sizeof(app_name_env), "R_APP_NAME=%s", app_name);

    putenv(r_home_env);
    putenv(r_libs_env);
    putenv(r_share_env);
    putenv(r_doc_env);
    putenv("R_BUNDLE_APP=1");
    putenv(app_name_env);

    // Prepare execv arguments: Rscript --vanilla Contents/Resources/app/app.R
    char* const args[] = {
        rscript_path,
        "--vanilla",
        app_r_path,
        NULL
    };

    // Execute Rscript
    execv(rscript_path, args);

    // execv only returns if execution failed
    perror("[RDesk Stub] execv failed to launch Rscript");
    return 1;
}
