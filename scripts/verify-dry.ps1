$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$adapterPath = Join-Path $root 'src/pascal_polycall.c'
$pascalPath = Join-Path $root 'src/PascalPolycall.pas'
$forbidden = 'fopen|open\(|CreateFile|sscanf|strtok|socket\(|connect\('
$matches = Select-String -Path $adapterPath,$pascalPath -Pattern $forbidden

if ($matches) {
    $matches | ForEach-Object { Write-Error $_.Line }
    throw 'pascal-polycall must not parse configuration or implement runtime logic'
}

$adapter = Get-Content -Raw $adapterPath
$pascal = Get-Content -Raw $pascalPath
if (-not $adapter.Contains('polycall_ffi_run_config(config_path, 1)')) {
    throw 'pascal-polycall does not forward through polycall_ffi_run_config'
}
if (-not $pascal.Contains('PAnsiChar(StablePath)')) {
    throw 'pascal-polycall does not marshal its UTF-8 path as PAnsiChar'
}
if (-not $pascal.Contains('raise EPolycallError.Create(Status)')) {
    throw 'pascal-polycall does not expose idiomatic Pascal error handling'
}

Write-Output 'pascal-polycall thin-adapter check: PASS'
