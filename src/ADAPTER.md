# Adapter boundary

`PascalPolycall.pas` retains the UTF-8 path while passing its NUL-terminated
`PAnsiChar` representation to `pascal_polycall_run_config()` using the C calling
convention. The native shim makes exactly one call to
`polycall_ffi_run_config(config_path, 1)` and returns its status unchanged.

No layer in this package parses configuration or implements runtime behavior.
