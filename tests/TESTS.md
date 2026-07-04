# Tests

- `pascal_polycall_adapter_test.c` verifies exact path forwarding, validation
  mode `1`, null handling, and unchanged core statuses without libpolycall.
- `pascal_polycall_smoke.pas` exercises explicit/default paths, status returns,
  and `EPolycallError` through the real Pascal/C boundary when `fpc` is present.
- `package.test.js` validates npm metadata, exports, relative directory indexes,
  author, license, and required source files.
