# Builds the two release zips with explicit forward-slash entry names.
# Compress-Archive on PowerShell 5.1 writes backslash entry names, which some
# addon managers reject, so entries are added one by one instead.
# Paths are derived from the script location ($PSScriptRoot) so the workspace
# path never has to be written into this file as a literal.
#
# The regional (QFXMythicRankHUD) package is composed from the same Lua sources
# as the international one; only the TOC and LocaleCN.lua live in the
# releases/QFXMythicRankHUD overlay. Both zips therefore always ship the same
# code, and the version comes from the TOC files themselves.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = Split-Path -Parent $PSScriptRoot
$overlay = Join-Path $root "releases/QFXMythicRankHUD"
$files = @(
    "Core.lua", "Locale.lua", "MeetingStoneIntegration.lua", "MythicDetail.lua",
    "MythicDetailData.lua", "MythicDetailResources.lua", "MythicDetailStatistics.lua",
    "RankTarget.lua", "Region.lua", "RunSummary.lua", "Settings.lua", "Util.lua"
)

function Get-TocVersion($tocPath) {
    if (-not (Test-Path -LiteralPath $tocPath)) { throw "missing TOC: $tocPath" }
    $match = Select-String -LiteralPath $tocPath -Pattern '^##\s*Version:\s*(\S+)' |
        Select-Object -First 1
    if (-not $match) { throw "no ## Version line in $tocPath" }
    return $match.Matches[0].Groups[1].Value
}

$mainVersion = Get-TocVersion (Join-Path $root "MythicRankHUD.toc")
$cnVersion = Get-TocVersion (Join-Path $overlay "QFXMythicRankHUD.toc")
if ($mainVersion -ne $cnVersion) {
    throw "version mismatch: MythicRankHUD.toc is $mainVersion, QFXMythicRankHUD.toc is $cnVersion"
}

function New-PackageEntries($tocName, $tocPath, $extraFiles) {
    $entries = [ordered]@{}
    $entries[$tocName] = $tocPath
    foreach ($name in $files) {
        $entries[$name] = Join-Path $root $name
    }
    if ($extraFiles) {
        foreach ($name in $extraFiles.Keys) {
            $entries[$name] = $extraFiles[$name]
        }
    }
    return $entries
}

function New-AddonZip($zipPath, $folder, $entries) {
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    $zip = [System.IO.Compression.ZipFile]::Open($zipPath, 'Create')
    try {
        foreach ($entry in $entries.GetEnumerator()) {
            $source = $entry.Value
            if (-not (Test-Path -LiteralPath $source)) { throw "missing source file: $source" }
            $entryName = $folder + "/" + $entry.Key
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $zip, $source, $entryName, [System.IO.Compression.CompressionLevel]::Optimal)
        }
    } finally {
        $zip.Dispose()
    }
    Write-Output ("built " + $zipPath + " (" + ((Get-Item -LiteralPath $zipPath).Length) + " bytes)")
}

$mainEntries = New-PackageEntries "MythicRankHUD.toc" `
    (Join-Path $root "MythicRankHUD.toc") $null
New-AddonZip (Join-Path $root ("releases/MythicRankHUD-" + $mainVersion + ".zip")) `
    "MythicRankHUD" $mainEntries

$cnExtra = @{ "LocaleCN.lua" = Join-Path $overlay "LocaleCN.lua" }
$cnEntries = New-PackageEntries "QFXMythicRankHUD.toc" `
    (Join-Path $overlay "QFXMythicRankHUD.toc") $cnExtra
New-AddonZip (Join-Path $root ("releases/QFXMythicRankHUD-" + $mainVersion + ".zip")) `
    "QFXMythicRankHUD" $cnEntries
