# @obinexusltd/pascal-polycall

Free Pascal source binding for
[libpolycall](https://github.com/obinexus/libpolycall) 1.5.

The package is a thin adapter. `PascalPolycall.pas` converts a Pascal
`UTF8String` to a stable `PAnsiChar`, and the native shim makes exactly one
call to `polycall_ffi_run_config(config_path, 1)`. Configuration parsing,
validation, and runtime behavior remain in libpolycall.

## Install

```powershell
npm install @obinexusltd/pascal-polycall
```

This is a native source package. The npm tarball contains the Pascal and C
sources, public and generated headers, examples, tests, scripts, Makefile,
manifest, configuration, and license—not platform-specific binaries.

## Pascal API

```pascal
program Service;

{$mode objfpc}{$H+}

uses
  PascalPolycall;

var
  Status: LongInt;

begin
  Status := PolycallRunConfig('pascal-polycallrc');
  if Status <> 0 then
    Halt(Status);
end.
```

For exception-oriented startup code:

```pascal
try
  PolycallRunConfigOrRaise('pascal-polycallrc');
except
  on Error: EPolycallError do
    WriteLn('libpolycall status: ', Error.Status);
end;
```

- `PolycallRunConfig` returns the libpolycall status unchanged.
- `PolycallRunConfigOrRaise` raises `EPolycallError` for nonzero statuses.
- Omitting the path uses `pascal-polycallrc`.
- Paths cross the C boundary as NUL-terminated UTF-8 strings.

## Build and test

Build the native adapter archive and run all available checks:

```powershell
npm run build
npm test
```

The current machine has GCC and GNU Make but does not have Free Pascal (`fpc`)
installed. `npm test` therefore runs the native mock contract test, boundary
audit, and npm package tests, while reporting the Pascal smoke test as skipped.
When `fpc` is on `PATH`, that smoke test runs automatically.

You can invoke the Pascal-specific operations directly:

```powershell
npm run build:pascal
npm run test:pascal
```

The native test proves that paths are forwarded unchanged, validation mode is
always `1`, and success/failure statuses are not rewritten. The Pascal test
exercises default and explicit paths plus `EPolycallError` through the actual
Pascal/C link boundary.

## Link with libpolycall

Build libpolycall first, then make its library and this package's adapter
archive visible to the Free Pascal linker. A typical GNU-compatible command is:

```powershell
fpc -Mobjfpc `
  -Fu./src `
  -Fl./lib `
  -FlC:/path/to/libpolycall/lib `
  -k-lpascal_polycall `
  -k-lpolycall `
  examples/basic.pas
```

Run `npm run build` first so `lib/libpascal_polycall.a` exists. Adjust library
paths and names for the selected libpolycall build and platform.

## JavaScript build-tool entry point

The CommonJS entry point indexes every published project directory:

```js
const binding = require('@obinexusltd/pascal-polycall');

console.log(binding.pascalUnit);
console.log(binding.directories.src.relativeFiles);
console.log(binding.resolve('examples', 'basic.pas'));
```

Indexed relative directories are `src`, `include`, `generated`, `dist`,
`examples`, `tests`, and `scripts`. `resolve()` prevents traversal outside the
selected directory.

## Publish

```powershell
npm pack --dry-run
npm publish --access public
```

Publishing is never performed automatically.

## License

MIT © 2026 Nnamdi Michael Okpala (`okpalan@protonmail.com`).
