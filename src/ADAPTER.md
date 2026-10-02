# Adapter boundary

`PascalPolycall.pas` declares every function of the Polycall binding ABI v1
(`<polycall.h>`) as a `cdecl` external of the core library with the exact C
types (`ctypes`: `cint`, `csize_t`, `cuint32`, `cint32` handles; `PAnsiChar`
for NUL-terminated UTF-8 strings, `Pointer` + length for payload bytes).
Output goes into Pascal-owned buffers; the core never returns memory to free.

    PolycallRunConfig(path)  ->  polycall_ffi_run_config(path, 1)

No layer in this package parses configuration or implements runtime behavior.
