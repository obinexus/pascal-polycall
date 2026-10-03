# TODO — pascal-polycall

Status: supported (Linux, FPC 3.2.2) -- Free Pascal binding over Polycall
binding ABI v1 (polycall >= 1.1.0).

- [x] `PolycallRunConfig` / `PolycallRunConfigOrRaise` kept (+ strict mode)
- [x] cdecl externals for the whole ABI (no C shim, no stub header)
- [x] `TPolycallPeer`, `PolycallCall`, `PolycallDescribe`, version/ABI check
- [x] `EPolycallError` with status, strerror name, last_error detail, output
- [x] Free Pascal installed in the QA image; real-core tests + C CLI interop
- [x] Loader errors (missing / old / ABI-mismatched library), valgrind run
- [ ] Windows run (FPC + polycall.dll / libpolycall.dll via -dPOLYCALL_MINGW) --
      needs Free Pascal on the Windows host
- [ ] Publish `@obinexusltd/pascal-polycall` publicly on npm (not published)
