$tokens = $null
$errors = $null
$file = Join-Path $PSScriptRoot 'MonitorManager.ps1'
[System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors.Count -gt 0) {
    Write-Host 'SYNTAX ERRORS:' -ForegroundColor Red
    foreach ($e in $errors) {
        Write-Host ("  Line {0}: {1}" -f $e.Extent.StartLineNumber, $e.Message) -ForegroundColor Yellow
    }
    exit 1
} else {
    Write-Host 'OK: No syntax errors' -ForegroundColor Green
    exit 0
}
