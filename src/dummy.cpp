// Empty dummy file to satisfy R CMD INSTALL's shared library requirement
#include <Rinternals.h>
#include <R_ext/Rdynload.h>

extern "C" {
    void R_init_RDesk(DllInfo *dll) {
        R_registerRoutines(dll, NULL, NULL, NULL, NULL);
        R_useDynamicSymbols(dll, FALSE);
    }
}
