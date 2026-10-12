param(
    [ValidateSet('Start','Restore')][string]$Mode = 'Start',
    [ValidateRange(25,500)][int]$Mbps = 100,
    [ValidateSet(72,90,120)][int]$Fps = 72,
    [string]$SteamRoot,
    [string]$SteamVrRoot,
    [string]$BackendDirectory,
    [string]$StateDirectory
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (!$SteamRoot) {
    $SteamRoot = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if (!$SteamRoot) { $SteamRoot = Join-Path ${env:ProgramFiles(x86)} 'Steam' }
}
$SteamRoot = [IO.Path]::GetFullPath($SteamRoot)
if (!$SteamVrRoot) {
    $pathsFile = Join-Path $env:LOCALAPPDATA 'openvr\openvrpaths.vrpath'
    if (Test-Path -LiteralPath $pathsFile) { $SteamVrRoot = (Get-Content -LiteralPath $pathsFile -Raw | ConvertFrom-Json).runtime[0] }
    if (!$SteamVrRoot) { $SteamVrRoot = Join-Path $SteamRoot 'steamapps\common\SteamVR' }
}
$SteamVrRoot = [IO.Path]::GetFullPath($SteamVrRoot)
if (!$BackendDirectory) {
    $BackendDirectory = Join-Path $PSScriptRoot 'Backend'
    if (!(Test-Path -LiteralPath $BackendDirectory)) { $BackendDirectory = Join-Path $repo 'artifacts\CodecLab\Backend' }
}
$BackendDirectory = [IO.Path]::GetFullPath($BackendDirectory)
if (!$StateDirectory) { $StateDirectory = Join-Path $repo 'artifacts\AndroidAv1Session' }
$StateDirectory = [IO.Path]::GetFullPath($StateDirectory)
$configPath = Join-Path $SteamRoot 'config\steamvr.vrsettings'
$receiptPath = Join-Path $StateDirectory 'session.json'
$backupPath = Join-Path $StateDirectory 'steamvr.vrsettings.original'
function HashFile([string]$path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
function WriteAtomic([string]$path, [byte[]]$bytes) {
    $temporary = $path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllBytes($temporary, $bytes)
        if (Test-Path -LiteralPath $path) { [IO.File]::Replace($temporary, $path, [NullString]::Value) }
        else { [IO.File]::Move($temporary, $path) }
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary } }
}
function RestoreSettings {
    if (Get-Process vrserver -ErrorAction SilentlyContinue) { throw 'Close SteamVR before restoring settings. The temporary AV1 adapter exits with vrserver.' }
    if (!(Test-Path -LiteralPath $receiptPath)) { throw 'No Android AV1 settings receipt exists.' }
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    if ($receipt.config_path -ne $configPath -or $receipt.version -ne 1) { throw 'Session receipt does not match this Steam installation.' }
    if ($receipt.restored) { Write-Output 'Settings are already restored.'; return }
    if ((HashFile $backupPath) -ne $receipt.original_sha256) { throw 'Original backup fingerprint changed; no restore was made.' }
    if ((HashFile $configPath) -ne $receipt.applied_sha256) { throw "Steam settings changed since the trial; merge settings manually from $backupPath instead of overwriting newer changes." }
    WriteAtomic $configPath ([IO.File]::ReadAllBytes($backupPath))
    $receipt.restored = $true
    WriteAtomic $receiptPath ([Text.Encoding]::UTF8.GetBytes(($receipt | ConvertTo-Json -Depth 10)))
    Write-Output 'Original Steam settings restored. Reinstall the original Steam Link APK to restore HEVC on the headset.'
}
if ($Mode -eq 'Restore') { RestoreSettings; return }
if (Get-Process vrserver -ErrorAction SilentlyContinue) { throw 'Close SteamVR before starting the Android AV1 trial.' }
if (Get-Process SteamLinkVRSettings -ErrorAction SilentlyContinue) { throw 'Close the settings/encoder-monitor app before starting this isolated trial.' }
$controller = Join-Path $BackendDirectory 'trial_control.exe'
$adapter = Join-Path $BackendDirectory 'SteamFrameAV1Backend.dll'
foreach ($file in @($controller,$adapter,$configPath,(Join-Path $SteamRoot 'steam.exe'))) {
    if (!(Test-Path -LiteralPath $file -PathType Leaf)) { throw "Required file is missing: $file" }
}
if (Test-Path -LiteralPath $receiptPath) {
    $old = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    if (!$old.restored) { throw 'Restore the previous Android AV1 session settings first.' }
}
New-Item -ItemType Directory -Path $StateDirectory -Force | Out-Null
$original = [IO.File]::ReadAllBytes($configPath)
$data = [Text.Encoding]::UTF8.GetString($original).TrimStart([char]0xfeff) | ConvertFrom-Json -AsHashtable
if (!$data.ContainsKey('driver_vrlink')) { $data.driver_vrlink = @{} }
if (!$data.ContainsKey('steamvr')) { $data.steamvr = @{} }
$data.driver_vrlink.targetBandwidth = $Mbps
$data.driver_vrlink.recommendedBandwidthMbit = $Mbps
$data.driver_vrlink.automaticBandwidth = $false
$data.driver_vrlink.automaticStreamFormatWidth = $false
$data.driver_vrlink.streamFormatWidth = 1536
$data.steamvr.preferredRefreshRate = $Fps
WriteAtomic $backupPath $original
$applied = [Text.Encoding]::UTF8.GetBytes(($data | ConvertTo-Json -Depth 100))
$receipt = @{version=1;config_path=$configPath;original_sha256=(HashFile $backupPath);applied_sha256=([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($applied)));restored=$false;mbps=$Mbps;fps=$Fps}
WriteAtomic $receiptPath ([Text.Encoding]::UTF8.GetBytes(($receipt | ConvertTo-Json -Depth 10)))
WriteAtomic $configPath $applied
Write-Output 'Start with the patched APK disconnected. This is an unverified Android AV1 trial; begin at 100 Mbps.'
Start-Process -FilePath (Join-Path $SteamRoot 'steam.exe') -ArgumentList '-applaunch','250820' -WindowStyle Hidden
$deadline = [DateTime]::UtcNow.AddSeconds(30)
$installed = $false
while ([DateTime]::UtcNow -lt $deadline) {
    $server = Get-Process vrserver -ErrorAction SilentlyContinue | Where-Object {
        $_.Path -and [IO.Path]::GetDirectoryName($_.Path) -eq (Join-Path $SteamVrRoot 'bin\win64')
    } | Select-Object -First 1
    if ($server) {
        $result = & $controller $server.Id $adapter install ($Mbps*1000000) ($Mbps*1000000) 1 $Fps 1
        if ($LASTEXITCODE -eq 0) { $installed = $true; break }
        try { $code = ($result | ConvertFrom-Json).code } catch { throw 'Native controller returned an invalid result.' }
        if ($code -ne 11) { throw "Native controller rejected the trial (code $code). Close SteamVR and run -Mode Restore." }
    }
    Start-Sleep -Milliseconds 100
}
if (!$installed) { throw 'Adapter startup timed out. Close SteamVR and run -Mode Restore.' }
Write-Output "PC AV1 adapter installed at $Mbps Mbps / $Fps Hz. Now connect the patched Steam Link APK."
Write-Output 'Waiting for fresh encoded AV1 frames (this does not prove headset decoding)...'
$deadline = [DateTime]::UtcNow.AddSeconds(90)
$baseline = $null
while ([DateTime]::UtcNow -lt $deadline -and !(Get-Process -Id $server.Id -ErrorAction SilentlyContinue).HasExited) {
    $stats = & $controller $server.Id $adapter stats
    if ($LASTEXITCODE -ne 0) { break }
    $stats = $stats | ConvertFrom-Json
    if ($stats.errors -gt 0) { throw 'Encoder reported errors. Disconnect, close SteamVR and restore settings.' }
    if ($null -ne $baseline -and $stats.locks -gt $baseline) {
        $identity = & $controller $server.Id $adapter identity | ConvertFrom-Json
        if ($identity.codec -eq 'AV1') { Write-Output 'Fresh PC AV1 output verified. Check headset picture, latency and decoder errors before increasing bitrate.'; return }
    }
    $baseline = $stats.locks
    Start-Sleep -Milliseconds 500
}
Write-Warning 'Fresh PC AV1 output was not verified. Close SteamVR and restore settings if the headset cannot connect.'
