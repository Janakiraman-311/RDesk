// Empty dummy file to satisfy R CMD INSTALL's shared library requirement
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunknown-warning-option"
#endif

#include <Rinternals.h>
#include <R_ext/Rdynload.h>

#if defined(__clang__)
#pragma clang diagnostic pop
#endif

extern "C" {
    void R_init_RDesk(DllInfo *dll) {
        R_registerRoutines(dll, NULL, NULL, NULL, NULL);
        R_useDynamicSymbols(dll, FALSE);
    }
}
