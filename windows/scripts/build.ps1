param([switch]$Test, [switch]$Installer, [switch]$SkipUia)
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$env:DOTNET_ROOT = Split-Path (Get-Command dotnet).Source -Parent
$env:DOTNET_ROOT_X64 = $env:DOTNET_ROOT
function Invoke-Checked([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed ($LASTEXITCODE)" }
}
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (!(Test-Path $vswhere)) { throw 'Install Visual Studio Build Tools with Desktop development with C++ and a Windows SDK.' }
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$vs) { throw 'MSVC x64 build tools not found.' }
$vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'
& $env:ComSpec /d /s /c "`"`"$vcvars`" >nul && set`"" | ForEach-Object {
    if ($_ -match '^([^=]+)=(.*)$') { [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process') }
}
Push-Location (Join-Path $root 'core')
try {
    Invoke-Checked cargo @('build', '-p', 'deai-native', '--release', '--locked')
    if ($Test) { Invoke-Checked cargo @('test', '--workspace', '--release', '--locked') }
} finally { Pop-Location }
Push-Location (Join-Path $root 'windows')
try {
    Invoke-Checked dotnet @('build', 'DeAI.sln', '-c', 'Release')
    if ($Test) {
        Invoke-Checked dotnet @('format', 'DeAI.sln', '--verify-no-changes', '--no-restore', '--severity', 'warn')
        if ($SkipUia) { Invoke-Checked '.\DeAI.Tests\bin\x64\Release\net8.0-windows\DeAI.Tests.exe' @('--unit') }
        else { Invoke-Checked '.\DeAI.Tests\bin\x64\Release\net8.0-windows\DeAI.Tests.exe' @((Join-Path $PWD 'DeAI.Fixture\bin\x64\Release\net8.0-windows\DeAI.Fixture.exe')) }
    }
    Invoke-Checked dotnet @('publish', 'DeAI.App\DeAI.App.csproj', '-c', 'Release', '-r', 'win-x64', '--self-contained', 'true', '-p:PublishSingleFile=false', '-o', 'artifacts\win-x64')
    Copy-Item (Join-Path $root 'LICENSE'), (Join-Path $root 'THIRD_PARTY_NOTICES.md'), 'README.md' 'artifacts\win-x64'
    $deps = Get-Content 'artifacts\win-x64\DeAI.deps.json' -Raw | ConvertFrom-Json
    $runtimeVersion = ($deps.libraries.PSObject.Properties.Name | Where-Object { $_ -like 'runtimepack.Microsoft.NETCore.App.Runtime.win-x64/*' } | Select-Object -First 1).Split('/')[-1]
    $packages = if ($env:NUGET_PACKAGES) { $env:NUGET_PACKAGES } else { Join-Path $HOME '.nuget\packages' }
    Copy-Item (Join-Path $packages "microsoft.netcore.app.runtime.win-x64\$runtimeVersion\LICENSE.TXT") 'artifacts\win-x64\DOTNET-LICENSE.TXT'
    Copy-Item (Join-Path $packages "microsoft.netcore.app.runtime.win-x64\$runtimeVersion\THIRD-PARTY-NOTICES.TXT") 'artifacts\win-x64\DOTNET-THIRD-PARTY-NOTICES.TXT'
    Copy-Item (Join-Path $packages "microsoft.windowsdesktop.app.runtime.win-x64\$runtimeVersion\LICENSE") 'artifacts\win-x64\WINDOWSDESKTOP-LICENSE.TXT'
    if ($Installer) {
        $iscc = Get-Command ISCC.exe -ErrorAction SilentlyContinue
        $compiler = if ($iscc) { $iscc.Source } else { "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" }
        if (!(Test-Path $compiler)) { throw 'Install Inno Setup 6.4+ or put ISCC.exe on PATH.' }
        Invoke-Checked $compiler @('installer.iss')
    }
} finally { Pop-Location }
