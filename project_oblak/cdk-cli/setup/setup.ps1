$dir = Join-Path $PSScriptRoot "..\windows"
[Environment]::SetEnvironmentVariable("PATH", $env:PATH + ";$dir", "User")
Write-Host "Added $dir to PATH"
Write-Host "Restart your terminal to apply"
