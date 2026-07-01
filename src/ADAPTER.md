# Pascal adapter (scaffold)

Implement the Pascal adapter here. It must call across the FFI boundary only:

    status = polycall_ffi_run_config("pascal-polycallrc", /*run=*/1)

Return/raise a Pascal-native error when `status` is non-zero. Do not parse
config or duplicate any core logic. See ../../../docs/adapter-pattern.md.
