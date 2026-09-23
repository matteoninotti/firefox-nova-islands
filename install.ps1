# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# firefox-nova-islands installer for Windows (PowerShell 5.1+).
# https://github.com/matteoninotti/firefox-nova-islands
#
# Usage:
#   .\install.ps1                      pick a profile interactively and install
#   .\install.ps1 -ProfilePath <dir>   install into a specific profile folder
#   .\install.ps1 -Uninstall [...]     remove it again
#
# What it does in the chosen profile:
#   1. backs up chrome\userChrome.css and user.js (if present)
#   2. copies nova-islands.css into chrome\
#   3. adds  @import url("nova-islands.css");  to the top of chrome\userChrome.css
#   4. adds  toolkit.legacyUserProfileCustomizations.stylesheets = true  to user.js

[CmdletBinding()]
param(
    [string]$ProfilePath,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$RepoRaw    = 'https://raw.githubusercontent.com/matteoninotti/firefox-nova-islands/main'
$CssName    = 'nova-islands.css'
$ImportLine = '@import url("nova-islands.css");'
$PrefLine   = 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true); // firefox-nova-islands'
$PrefMark   = '// firefox-nova-islands'
$Utf8NoBom  = New-Object System.Text.UTF8Encoding($false)

function Read-Lines([string]$Path) {
    if (Test-Path -LiteralPath $Path) { return [System.IO.File]::ReadAllLines($Path) }
    return @()
}

function Write-Lines([string]$Path, [string[]]$Lines) {
    $text = ''
    if ($Lines.Count -gt 0) { $text = ($Lines -join "`n") + "`n" }
    [System.IO.File]::WriteAllText($Path, $text, $Utf8NoBom)
}

# ---- Find profiles ----------------------------------------------------------

function Get-FirefoxProfiles {
    $root = if ($env:FIREFOX_ROOT) { $env:FIREFOX_ROOT } else { Join-Path $env:APPDATA 'Mozilla\Firefox' }
    $ini = Join-Path $root 'profiles.ini'
    if (-not (Test-Path -LiteralPath $ini)) { return @() }

    $profiles = @()
    $installDefaults = @{}
    $section = $null
    $cur = $null

    foreach ($raw in (Read-Lines $ini) + '[end]') {
        $line = $raw.Trim()
        if ($line -match '^\[(.+)\]$') {
            if ($cur -and $cur.Path) { $profiles += $cur }
            $section = $Matches[1]
            $cur = if ($section -like 'Profile*') { [pscustomobject]@{ Path = $null; IsRelative = '1'; Default = $false } } else { $null }
            continue
        }
        $eq = $line.IndexOf('=')
        if ($eq -lt 1) { continue }
        $key = $line.Substring(0, $eq); $val = $line.Substring($eq + 1)
        if ($cur) {
            switch ($key) {
                'Path'       { $cur.Path = $val }
                'IsRelative' { $cur.IsRelative = $val }
                'Default'    { $cur.Default = ($val -eq '1') }
            }
        } elseif ($section -like 'Install*' -and $key -eq 'Default') {
            $installDefaults[$val.Replace('/', '\')] = $true
        }
    }

    # Firefox 67+ picks the profile named in [Install...]; the older
    # Default=1 flag only counts when there is no such section.
    $hasInstall = $false
    foreach ($p in $profiles) { if ($installDefaults.ContainsKey($p.Path.Replace('/', '\'))) { $hasInstall = $true } }

    foreach ($p in $profiles) {
        $rel = $p.Path.Replace('/', '\')
        $full = if ($p.IsRelative -eq '0') { $rel } else { Join-Path $root $rel }
        $isDefault = if ($hasInstall) { $installDefaults.ContainsKey($rel) } else { $p.Default }
        [pscustomobject]@{
            Path    = $full
            Default = $isDefault
        }
    }
}

if (-not $ProfilePath) {
    $found = @(Get-FirefoxProfiles | Where-Object { Test-Path -LiteralPath $_.Path })
    if ($found.Count -eq 0) { throw 'No Firefox profiles found; pass -ProfilePath <dir>' }

    $defaultIndex = 0
    for ($i = 0; $i -lt $found.Count; $i++) {
        $mark = ''
        if ($found[$i].Default) {
            $mark = '  (default)'
            if ($defaultIndex -eq 0) { $defaultIndex = $i + 1 }
        }
        Write-Host ("  [{0}] {1}{2}" -f ($i + 1), $found[$i].Path, $mark)
    }
    if ($defaultIndex -eq 0) { $defaultIndex = 1 }
    $choice = Read-Host "Profile number [$defaultIndex]"
    if (-not $choice) { $choice = $defaultIndex }
    $n = 0
    if (-not [int]::TryParse("$choice", [ref]$n) -or $n -lt 1 -or $n -gt $found.Count) { throw "Invalid choice: $choice" }
    $ProfilePath = $found[$n - 1].Path
}

if (-not (Test-Path -LiteralPath $ProfilePath -PathType Container)) { throw "Profile folder not found: $ProfilePath" }
if (-not ((Test-Path -LiteralPath (Join-Path $ProfilePath 'prefs.js')) -or (Test-Path -LiteralPath (Join-Path $ProfilePath 'times.json')))) {
    throw "Does not look like a Firefox profile: $ProfilePath"
}

$Chrome     = Join-Path $ProfilePath 'chrome'
$UserChrome = Join-Path $Chrome 'userChrome.css'
$UserJs     = Join-Path $ProfilePath 'user.js'

if (Get-Process -Name firefox -ErrorAction SilentlyContinue) {
    Write-Host 'Note: Firefox is running. Changes take effect after you restart it.'
}

function Backup-Files {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $dir = Join-Path $ProfilePath "nova-islands-backup-$stamp"
    $n = 1
    while (Test-Path -LiteralPath $dir) { $dir = Join-Path $ProfilePath "nova-islands-backup-$stamp-$n"; $n++ }
    New-Item -ItemType Directory -Path $dir | Out-Null
    foreach ($f in @($UserChrome, $UserJs)) {
        if (Test-Path -LiteralPath $f) { Copy-Item -LiteralPath $f -Destination $dir }
    }
    Write-Host "Backup: $dir"
}

# ---- Uninstall --------------------------------------------------------------

if ($Uninstall) {
    Backup-Files
    Remove-Item -LiteralPath (Join-Path $Chrome $CssName) -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $UserChrome) {
        Write-Lines $UserChrome @(Read-Lines $UserChrome | Where-Object { $_ -ne $ImportLine })
    }
    if (Test-Path -LiteralPath $UserJs) {
        Write-Lines $UserJs @(Read-Lines $UserJs | Where-Object { -not $_.Contains($PrefMark) })
    }
    Write-Host "Removed firefox-nova-islands from $ProfilePath"
    Write-Host 'The stylesheet pref stays enabled in prefs.js; reset it in about:config if nothing else needs it.'
    Write-Host 'Restart Firefox to finish.'
    return
}

# ---- Install ----------------------------------------------------------------

Backup-Files
New-Item -ItemType Directory -Path $Chrome -Force | Out-Null

$localCss = if ($PSScriptRoot) { Join-Path $PSScriptRoot $CssName } else { $null }
if ($localCss -and (Test-Path -LiteralPath $localCss)) {
    Copy-Item -LiteralPath $localCss -Destination (Join-Path $Chrome $CssName) -Force
} else {
    Write-Host "Downloading $CssName ..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing -Uri "$RepoRaw/$CssName" -OutFile (Join-Path $Chrome $CssName)
}

# @import must come before any other rule, so put it on the first line.
$ucLines = @(Read-Lines $UserChrome)
if ($ucLines -notcontains $ImportLine) {
    Write-Lines $UserChrome (@($ImportLine) + $ucLines)
}

$jsLines = @(Read-Lines $UserJs)
if (-not ($jsLines | Where-Object { $_.Contains($PrefMark) })) {
    Write-Lines $UserJs ($jsLines + $PrefLine)
}

Write-Host "Installed into $ProfilePath"

if (Test-Path -LiteralPath (Join-Path $ProfilePath 'user-overrides.js')) {
    Write-Host ''
    Write-Host 'Heads-up: this profile has a user-overrides.js (arkenfox/Betterfox updater).'
    Write-Host 'Those updaters rewrite user.js, so also add this line to user-overrides.js:'
    Write-Host '  user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);'
}

# Nova is on by default from Firefox 157; before that it needs browser.nova.enabled.
$prefs = @(Read-Lines (Join-Path $ProfilePath 'prefs.js'))
$compat = @(Read-Lines (Join-Path $ProfilePath 'compatibility.ini'))
$major = $null
foreach ($l in $compat) { if ($l -match '^LastVersion=(\d+)') { $major = [int]$Matches[1]; break } }
$novaOff = ($prefs -contains 'user_pref("browser.nova.enabled", false);') -or
           ($major -and $major -lt 157 -and ($prefs -notcontains 'user_pref("browser.nova.enabled", true);'))
if ($novaOff) {
    Write-Host ''
    Write-Host 'Note: the Nova design is off in this profile, and this style only applies to Nova.'
    Write-Host 'Set browser.nova.enabled to true in about:config to see it.'
}

Write-Host ''
Write-Host 'Restart Firefox to apply.'
