# Tests

- `pascal_polycall_test.pas` runs against the REAL installed Polycall core
  (no mock) and covers the checklist of the core's `docs/BINDING_ABI.md`:
  version/ABI; `PolycallRunConfig` (valid, missing, malformed, strict
  unknown key, unsupported TLS, a non-ASCII UTF-8 file name) and
  `EPolycallError`; `PolycallCall` against a live `polycall start`
  (success, unknown operation, unknown item, deadline, invalid input, no
  runtime, timeout 0 / 600000 / 600001); two `TPolycallPeer` nodes
  exchanging empty, UTF-8, binary-with-NUL and exactly-1-MiB payloads both
  ways, 1 MiB + 1 rejected; 63-byte ids accepted and received intact,
  64-byte ids rejected; registry ownership; duplicate id stored once; auth
  failure; dead peer; receive timeout, poll (timeout 0) and
  `PolycallWaitForever` with a queued message; 4-byte receive buffer
  (E_TOO_LARGE keeps the message queued, the unit regrows) and an
  exactly-sized one; cancel/close waking a `TThread` blocked in `Receive`;
  double close / use after close; 4 concurrent sender threads, 4 threads of
  concurrent `PolycallCall` and 4 threads of concurrent NodeId / Endpoint /
  Health / List calls; interop both ways with the C CLI.
- `run-real.sh` starts `polycall peer serve` + `polycall start` with a random
  `POLYCALL_DEV_TOKEN`; exit 77 = SKIP without the CLI or `fpc`.
- `loader-errors.sh` (`make test-loader`, Linux) starts `loader_check.pas`
  against the real core, a fake library that reports binding ABI 2, a fake
  1.0 library without the ABI v1 symbols, and no library; the fake libraries
  come from `loader/stub_polycall.c` and are used for nothing else.
- `make memcheck` runs the real-core test under valgrind memcheck (errors
  and definite leaks fail it).
- `package.test.js` validates npm metadata, exports and the directory index.
