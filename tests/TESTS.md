# Tests

- `pascal_polycall_test.pas` runs against the REAL installed Polycall core
  (no mock) and covers the checklist of the core's `docs/BINDING_ABI.md`:
  version/ABI; `PolycallRunConfig` (valid, missing, malformed, strict
  unknown key, unsupported TLS) and `EPolycallError`; `PolycallCall` against
  a live `polycall start` (success, unknown operation, unknown item,
  deadline, invalid input, no runtime); two `TPolycallPeer` nodes exchanging
  empty, UTF-8, binary-with-NUL and exactly-1-MiB payloads both ways,
  1 MiB + 1 rejected; registry ownership; duplicate id stored once; auth
  failure; dead peer; receive timeout; 4-byte receive buffer (E_TOO_LARGE
  keeps the message queued, the unit regrows); cancel/close waking a
  `TThread` blocked in `Receive`; double close / use after close;
  4 concurrent sender threads; interop both ways with the C CLI.
- `run-real.sh` starts `polycall peer serve` + `polycall start` with a random
  `POLYCALL_DEV_TOKEN`; exit 77 = SKIP without the CLI or `fpc`.
- `package.test.js` validates npm metadata, exports and the directory index.
