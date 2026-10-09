param([string]$InstallerPath = (Join-Path $PSScriptRoot '..\artifacts\DeAI-Windows-x64-0.1.0-Setup.exe'))
$ErrorActionPreference = 'Stop'
$registry = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{34BE8EE5-6500-4E17-9751-67F449CEFA0C}_is1'
if (Test-Path $registry) { throw 'An existing DeAI installation is registered; installer smoke test will not modify it.' }
if (!(Test-Path $InstallerPath)) { throw 'Build the Windows installer first.' }
$directory = Join-Path $env:LOCALAPPDATA ('DeAI-install-test-' + [Guid]::NewGuid().ToString('N'))
$data = Join-Path $env:LOCALAPPDATA 'DeAI'
$sentinel = Join-Path $data ('uninstall-test-' + [Guid]::NewGuid().ToString('N') + '.txt')
New-Item -ItemType Directory -Path $data -Force | Out-Null
Set-Content $sentinel 'Synthetic uninstall retention test'
function Run-Installer([string]$File, [string[]]$Arguments) {
    $process = Start-Process $File -ArgumentList $Arguments -PassThru -Wait
    if ($process.ExitCode -ne 0) { throw "Installer process failed ($($process.ExitCode))" }
}
try {
    $arguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', "/DIR=`"$directory`"")
    Run-Installer $InstallerPath $arguments
    foreach ($name in @('DeAI.exe', 'deai_native.dll', 'hostfxr.dll', 'DOTNET-LICENSE.TXT', 'THIRD_PARTY_NOTICES.md')) {
        if (!(Test-Path (Join-Path $directory $name))) { throw "Missing installed file: $name" }
    }
    Write-Output 'PASS user-scoped self-contained installation and native DLL'
    Run-Installer $InstallerPath $arguments
    Write-Output 'PASS reinstall in place'
    Run-Installer (Join-Path $directory 'unins000.exe') @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART')
    if ((Test-Path (Join-Path $directory 'DeAI.exe')) -or (Test-Path $registry)) { throw 'Uninstall did not remove application/registration.' }
    if (!(Test-Path $sentinel)) { throw 'Uninstall deleted user data.' }
    Write-Output 'PASS uninstall removes app and retains user data'
} finally {
    if (Test-Path $sentinel) { Remove-Item $sentinel }
}
