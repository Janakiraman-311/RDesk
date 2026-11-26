# Copy an R installation into the bundle staging directory

Copies `bin/`, `library/`, `etc/`, `modules/`, and `include/` from
`r_home` into `dest_dir`. Skips heavyweight directories (Tcl/Tk, docs,
tests) that are already pruned by `rdesk_prune_runtime()`.

## Usage

``` r
rdesk_copy_r_runtime(r_home, dest_dir)
```
