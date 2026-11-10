# miint patches to Easel

Branch `v0.49-miint` is Easel tag `easel-0.49` (`07ca83b`) plus the commits listed below. It is the Easel that
[the-miint/hmmer](https://github.com/the-miint/hmmer) (branch `v3.4-miint`) builds against, as its `easel`
submodule. [duckdb-miint](https://github.com/the-miint/duckdb-miint) links the two into DuckDB, natively and as
WebAssembly (duckdb-wasm).

That use sets three requirements stock Easel 0.49 does not meet:

- **In-process.** Easel runs inside the host's process. An error must come back to the caller with its message.
- **WebAssembly.** The library must compile with Emscripten, SSE code included (emulated on wasm SIMD128).
- **Parity.** Scores must match a CLI oracle built from these forks. Easel must never turn on the x86
  flush-to-zero (FTZ) or denormals-are-zero (DAZ) modes, which change floating point results.

Each commit is either an upstream commit cherry-picked with `-x` (its message ends "cherry picked from commit …")
or a miint patch. Every miint patch carries a test that failed before it and passes after.

## Patch series (oldest first)

| Commit | Source | Change and why | Test |
|---|---|---|---|
| `be0ce67` | upstream `0e561ee` (#80) | `esl_sq_CreateFrom()` sets `abc = NULL`. Text mode means no alphabet, and `abc` was left uninitialized. | `utest_CreateFromIsInitialized` (added in `25ea1f4`) fails with this line reverted. |
| `097726c` | upstream `2c5f4b1` | `esl_sq_Copy()` sizes each `xr_tag[x]` by the tag's own length. It used the name's allocation, so a long `#=GR` tag overflowed the heap. | `utest_CopyLongMarkupTag` (`1d6a4a5`). |
| `25ea1f4` | miint | `sq_create_from()` (behind `esl_sq_CreateFrom()` and `esl_sq_CreateDigitalFrom()`) sets `tax_id` and `idx` to -1, as `esl_sq_Create()` does. They were uninitialized, and `esl_sq_Validate()` read them. Not fixed upstream (master and develop checked). | `utest_CreateFromIsInitialized` fills the heap with a nonzero pattern first, so the gap shows without valgrind. It checks every field from both constructors. |
| `1d6a4a5` | miint (test only) | Tests `esl_sq_Copy()` with a markup tag longer than the name. | `utest_CopyLongMarkupTag`: before `2c5f4b1`, valgrind reports an invalid write in `esl_sq_Copy()`. Easel's level-3 "valgrind sq-utest" exercise runs it. |
| `f2f811d` | miint | `esl_fail()`, `esl_exception()` and `esl_fatal()` dropped their "parent is PID 1, so we're a daemon: use syslog" branch. A PID-1 parent is common (a container entrypoint, an orphan), and under WebAssembly `getppid()` is always 1. There `esl_fail()` left the caller's error buffer empty, and the other two lost their message. | `miint/check.sh` `errmsg-pid1`: `miint/errmsg_check.c` calls each function under a PID-1 parent (`unshare -rpf`). Before the patch all three messages were lost. |
| `3301c9a` | miint | `configure.ac` no longer probes for FTZ/DAZ, so `HAVE_FLUSH_ZERO_MODE` and `HAVE_DENORMALS_ZERO_MODE` are never defined. No Easel source reads them; HMMER's `impl_Init()` does. | `miint/check.sh` `ftz-daz-off`: before the patch, the generated `esl_config.h` defined both. |
| `22784b3` | miint | `esl_sse.c`/`.h` and `m4/esl_sse.m4` include `<emmintrin.h>` (plus `<smmintrin.h>` under `eslENABLE_SSE4`), not `<x86intrin.h>`. `<x86intrin.h>` exists only on x86, so it does not compile under Emscripten. | `miint/check.sh` `emcc-build`. |
| `81bde25` | miint | `esl_cpu.c`: the `cpuid` inline asm is compiled only on x86. Elsewhere `esl_cpu_has_*()` returns FALSE. HMMER 3.4 never calls those functions. | `miint/check.sh` `emcc-build`: before `22784b3`, configure's SSE probe failed; between `22784b3` and this commit, the build failed only at `esl_cpu.c`; after it, the build passes. |

After those, two housekeeping commits: `.gitignore` ignores `configure~`, and this README.

## Testing

```sh
autoconf && ./configure && make && make check    # Easel's own suite: 87 exercises at the default level
miint/check.sh                                   # the environment checks below
```

`make check` runs the unit tests above, because they live in Easel's own test drivers. `miint/check.sh` (run from
any directory) covers the cases a test driver cannot set up for itself. It builds in `build-miint-native/` and
`build-miint-emcc/`, which `/build-*/` keeps out of git:

| Check | What it proves | Needs |
|---|---|---|
| `native-build` | `libeasel.a` builds with the host compiler. Other checks build on it. | a C compiler, autoconf |
| `errmsg-pid1` | Error messages reach the caller, or stderr, under a PID-1 parent. | `unshare` with unprivileged user namespaces |
| `ftz-daz-off` | configure defines neither FTZ nor DAZ. | — |
| `emcc-build` | `libeasel.a` compiles for WebAssembly with `--enable-sse` and `-msimd128 -msse -msse2`, and configure enabled the SSE code. | `emconfigure`/`emcc` on `PATH` (tested with emsdk 6.0.9 and 3.1.71) |

A missing tool prints `SKIP` with the reason, and the summary lists it again. The script exits 1 if any check
fails. Its helpers (`pass`, `fail`, `skip`, `step`) are copied in HMMER's `miint/check.sh`. That duplication is
deliberate: each fork stands alone.

## Known upstream bugs left alone

duckdb-miint is designed to avoid both, so neither gets a patch here.

- `esl_sq_CreateDigitalFrom(..., n = -1, ...)` computes the length into `sq->n`, but then sets `end`, `W` and `L`
  from `n`, so all three come out -1. Upstream develop is the same. duckdb-miint passes the length explicitly.
- `esl_sq_Copy()` after `2c5f4b1` leaves `dst->xr_tag[x]` uninitialized when the source tag is NULL. Upstream
  develop fixes this in `3fd1f3f`, which applies cleanly here but is not picked. duckdb-miint's sequences come
  from table columns and carry no residue markup (`nxr` is 0), so the loop never runs.
