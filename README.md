# @obinexusltd/pascal-polycall

Free Pascal binding for the [Polycall](https://github.com/obinexus/polycall)
core (**polycall >= 1.1.0**, binding ABI v1).

`src/PascalPolycall.pas` declares the core's binding ABI (`<polycall.h>`,
`docs/BINDING_ABI.md` in the core repository) as `cdecl` externals of the
`polycall` library with their exact C types -- there is no C shim.
Configuration parsing, validation, networking and the peer protocol stay in
the core.

## Install

```sh
npm install @obinexusltd/pascal-polycall
```

This is a native source package (not yet published): the tarball contains
the Pascal unit, examples, tests, scripts, Makefile, manifest, configuration
and license -- no binaries, and its JavaScript entry point loads nothing.

## Pascal API

```pascal
uses PascalPolycall;

PolycallCheckABI;                                  { EPolycallError unless ABI 1 }
WriteLn(PolycallVersion);                          { '1.1.0' }

Status := PolycallRunConfig('pascal-polycallrc');  { polycall_ffi_run_config(path, 1) }
Status := PolycallRunConfig('pascal-polycallrc', False);   { validate only }
PolycallRunConfigOrRaise('pascal-polycallrc');     { raises EPolycallError }

WriteLn(PolycallCall('127.0.0.1:7000', 'inventory', 'get',
  '{"item_id":"widget-a"}', 2000));

Alpha := TPolycallPeer.Create('alpha');            { 127.0.0.1:<ephemeral> }
Beta := TPolycallPeer.Create('beta', '127.0.0.1:0', Token);
try
  Alpha.RegisterPeer('beta', Beta.Endpoint);
  Alpha.Send('beta', 'hello'#0'bytes', 'msg-1');    { exactly one delivery attempt }
  Msg := Beta.Receive(5000);                        { Msg.Sender, Msg.Id, Msg.Payload }
finally
  Alpha.Free;                                       { Free closes the node }
  Beta.Free;
end;
```

Also `TPolycallPeer.CreateSendOnly`, `Close` (a second `Close` raises
`POLYCALL_E_INVALID_HANDLE`), `NodeId`, `UnregisterPeer`, `List`, `Ping`,
`TryReceive`, `Cancel` (wakes a thread blocked in `Receive`), `Health`,
`PolycallDescribe`, `PolycallCallStatus` (non-raising),
`PolycallStrError`, `PolycallLastError`.

`EPolycallError` exposes `Status` (negative `POLYCALL_E_*` constant),
`StatusName` (`polycall_strerror`), `Detail` (`polycall_last_error`) and, for
`PolycallCall`, `Output` (the remote error object).

## Build and test

Needs Free Pascal >= 3.2 (Debian: `apt-get install fp-compiler`) and an
installed core found through pkg-config:

```sh
export PKG_CONFIG_PATH=/opt/polycall/lib/pkgconfig LD_LIBRARY_PATH=/opt/polycall/lib
make            # compile the unit
make test       # real-core test + interop with the polycall CLI
make example    # examples/basic.pas
npm test        # make test + verify-dry + npm package test
```

Programs using the unit need `-Fl<prefix>/lib` (the Makefile takes it from
`pkg-config --variable=libdir polycall`); programs using `TThread` on Unix
put `cthreads` first in their `uses` clause. On Windows the unit expects
`polycall.dll` (MSVC build) or, with `-dPOLYCALL_MINGW`, `libpolycall.dll`;
Windows is not tested yet.

`make test` runs `tests/pascal_polycall_test.pas` through `tests/run-real.sh`,
which starts `polycall peer serve` and `polycall start`; a missing `fpc` or
polycall CLI is reported as SKIP (exit 77), never as success. See
[tests/TESTS.md](tests/TESTS.md).

## License

MIT © 2026 Nnamdi Michael Okpala (`okpalan@protonmail.com`).
