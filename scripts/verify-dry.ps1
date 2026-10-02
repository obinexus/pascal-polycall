$ErrorActionPreference = 'Stop'

# Thin-adapter audit (see verify-dry.sh).
$root = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $root 'src/PascalPolycall.pas'
$source = Get-Content -Raw $sourcePath
$found = Select-String -Path $sourcePath -Pattern 'AssignFile|TFileStream|Sockets|fpSocket|fpConnect|TStringList'
if ($found) {
    $found | ForEach-Object { Write-Error $_.Line }
    throw 'pascal-polycall must not parse configuration or implement runtime logic'
}
foreach ($sym in @('polycall_ffi_abi_version', 'polycall_ffi_run_config', 'polycall_call',
                   'polycall_peer_open', 'polycall_peer_send', 'polycall_peer_recv')) {
    if (-not $source.Contains("external PolycallLib name '$sym'")) {
        throw "pascal-polycall does not declare $sym"
    }
}
Write-Output 'pascal-polycall thin-adapter check: PASS'
