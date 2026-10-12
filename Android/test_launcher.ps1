param([string]$FixtureDirectory = (Join-Path ([IO.Path]::GetTempPath()) ('android-av1-test-' + [Guid]::NewGuid().ToString('N'))))
$ErrorActionPreference = 'Stop'
# No real process or headset is touched by these settings-only tests.
function Get-Process { param([string]$Name) return $null }
$root = [IO.Path]::GetFullPath($FixtureDirectory)
New-Item -ItemType Directory "$root/steam/config","$root/state" -Force | Out-Null
$config = Join-Path $root 'steam/config/steamvr.vrsettings'
$backup = Join-Path $root 'state/steamvr.vrsettings.original'
$receiptPath = Join-Path $root 'state/session.json'
[IO.File]::WriteAllText($backup,'{"driver_vrlink":{"targetBandwidth":150},"other":{"keep":true}}')
[IO.File]::WriteAllText($config,'{"driver_vrlink":{"targetBandwidth":500},"other":{"keep":true}}')
$receipt = @{version=1;config_path=$config;original_sha256=(Get-FileHash $backup).Hash;applied_sha256=(Get-FileHash $config).Hash;restored=$false}
$receipt | ConvertTo-Json | Set-Content $receiptPath
$launcher = Join-Path $PSScriptRoot 'Start-GalaxyAv1.ps1'
& $launcher -Mode Restore -SteamRoot "$root/steam" -SteamVrRoot "$root/vr" -StateDirectory "$root/state"
if ((Get-FileHash $config).Hash -ne (Get-FileHash $backup).Hash) { throw 'Original settings restoration failed' }
$receipt | ConvertTo-Json | Set-Content $receiptPath
[IO.File]::WriteAllText($config,'{"newer_edit":"keep"}')
try {
    & $launcher -Mode Restore -SteamRoot "$root/steam" -SteamVrRoot "$root/vr" -StateDirectory "$root/state"
    throw 'Unexpected restore accepted'
} catch { if ($_.Exception.Message -notlike '*changed since the trial*') { throw } }
if ([IO.File]::ReadAllText($config) -ne '{"newer_edit":"keep"}') { throw 'Newer settings were overwritten' }
[IO.File]::WriteAllText($backup,'tampered backup')
try {
    & $launcher -Mode Restore -SteamRoot "$root/steam" -SteamVrRoot "$root/vr" -StateDirectory "$root/state"
    throw 'Unexpected corrupt backup accepted'
} catch { if ($_.Exception.Message -notlike '*backup fingerprint changed*') { throw } }
try {
    & $launcher -Mode Start -SteamRoot "$root/steam" -SteamVrRoot "$root/vr" -StateDirectory "$root/state" -BackendDirectory "$root/missing-backend"
    throw 'Unexpected missing backend accepted'
} catch { if ($_.Exception.Message -notlike '*Required file is missing*') { throw } }
if ([IO.File]::ReadAllText($config) -ne '{"newer_edit":"keep"}') { throw 'Failed startup changed settings' }
Write-Output 'Android launcher restoration, newer edits, corrupted backup and missing-backend checks passed.'
