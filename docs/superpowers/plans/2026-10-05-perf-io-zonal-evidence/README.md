# Evidence for 2026-10-05-perf-io-zonal.md

Benchmark and prototype scripts run on 2026-10-05 (Windows 11, R 4.5.3, terra 1.9.34, GDAL 3.12.1,
exactextractr 0.10.1). Run them from the repository root with `Rscript <script>`; the network
scripts need internet access to the public WaPOR bucket.

| File | What it shows |
|---|---|
| `net_worker.R`, `net_run.ps1` | Remote extraction of 150 polygons x 36 dekads under different GDAL settings, each in a fresh process; counts HTTP requests and requested megabytes from the libcurl log |
| `sticky.R` | The GDAL HTTP chunk size is fixed at the first remote read of a session |
| `ext_runtime.R` | The allowed-extensions filter can be set and cleared at run time |
| `fetch_proto.R` | Whole-file parallel fetch of Level 3 files, then local extraction |
| `open_cost.R`, `local_read.R` | Cost of opening local files with and without the PROJ fix; reading methods for local stacks |
| `zonal_bench.R`, `zonal_prof.R` | Time, memory and profile of the current `wapor_zonal_stats()` |
| `zonal_lean.R` | Restructured zonal loop with identical output (basis of WP-B) |
| `zonal_vec.R` | Grouped-sum variant (not faster than `zonal_lean.R`; extraction of per-cell tables is the floor) |
| `sf_check.R` | `format = "sf"` attaches wrong geometries with more than one statistic |
| `dekad_bins.R` | WaPOR dekads do not fit a regular 10-day time grid |

`results/`: `net2*.csv` and `net3*.csv` are the corrected runs used in the plan. `net1-before-proj-fix*.csv`
is the first round, run without the PROJ fix: its request counts and megabytes are valid, its
timings include about 12 s of unrelated overhead per run. Config names: `rwapor_now` = package
settings on 2026-10-05; `ai_suggested` = those plus the extension filter and merged ranges;
`no_chunk` = chunk setting removed; `no_chunk_ext` = proposed settings; `tuned_a` = proposed plus
`CPL_VSIL_CURL_USE_HEAD=NO`; `tuned_b`/`tuned_c` = 1 MB / 10 MB chunk with a larger region cache.
