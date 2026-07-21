Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'

$projectDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$mainScript = Join-Path $projectDir 'MonitorManager.ps1'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

function New-TestMonitor {
    $adapter = New-Object LUID
    $adapter.LowPart = 1
    $adapter.HighPart = 0
    return [PSCustomObject]@{
        DisplayName = '\\.\DISPLAY_TEST'
        MonitorName = 'Test Monitor'
        MonitorId = 'MON-TEST'
        Width = [int]$script:MockWidth
        Height = [int]$script:MockHeight
        RefreshRate = [int]$script:MockRefreshRate
        BitsPerPel = [int]$script:MockBitsPerPel
        DpiScale = [int]$script:MockDpi
        AdapterId = $adapter
        TargetAdapterId = $adapter
        SourceId = [uint32]0
        TargetId = [uint32]0
        IsPrimary = $true
        IsConnected = $true
        IsActive = $true
    }
}

$tokens = $null
$parseErrors = $null
$mainAst = [System.Management.Automation.Language.Parser]::ParseFile($mainScript, [ref]$tokens, [ref]$parseErrors)
Assert-True ($parseErrors.Count -eq 0) 'MonitorManager.ps1 must parse without errors'

# GetNewClosure creates a dynamic module. Any $script: variable inside the captured expression
# points at that module rather than MonitorManager.ps1 and can silently split GUI state.
$closureCalls = @($mainAst.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
    [string]$node.Member.Value -eq 'GetNewClosure'
}, $true))
$unsafeClosureVariables = @()
foreach ($call in $closureCalls) {
    $unsafeClosureVariables += @($call.Expression.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.VariableExpressionAst] -and
        $node.VariablePath.UserPath -like 'script:*'
    }, $true))
}
Assert-True ($unsafeClosureVariables.Count -eq 0) 'GetNewClosure callbacks must not access $script: state directly'

. $mainScript source

$workerMessage = '结构化后台结果：应用失败'
$workerMarker = $script:WorkerResultPrefix + (ConvertTo-Base64Text $workerMessage)
$parsedWorkerMessage = Get-WorkerResultMessage `
    -StandardOutput "普通输出`r`n$workerMarker`r`n标记后的警告" `
    -StandardError '驱动附加警告' -Fallback 'fallback'
Assert-True ($parsedWorkerMessage -eq $workerMessage) 'worker result marker wins over trailing stdout/stderr warnings'
$legacyWorkerMessage = Get-WorkerResultMessage -StandardOutput '旧版错误文本' -StandardError '' -Fallback 'fallback'
Assert-True ($legacyWorkerMessage -eq '旧版错误文本') 'worker result parser keeps legacy last-line fallback'

Assert-True ([Runtime.InteropServices.Marshal]::SizeOf([Type][DISPLAYCONFIG_MODE_INFO]) -eq 64) 'DISPLAYCONFIG_MODE_INFO ABI size'
Assert-True ([Runtime.InteropServices.Marshal]::SizeOf([Type][DISPLAYCONFIG_PATH_SOURCE_INFO]) -eq 20) 'DISPLAYCONFIG_PATH_SOURCE_INFO ABI size'
Assert-True ([Runtime.InteropServices.Marshal]::SizeOf([Type][DISPLAYCONFIG_PATH_TARGET_INFO]) -eq 48) 'DISPLAYCONFIG_PATH_TARGET_INFO ABI size'
Assert-True ([Runtime.InteropServices.Marshal]::SizeOf([Type][DISPLAYCONFIG_PATH_INFO]) -eq 72) 'DISPLAYCONFIG_PATH_INFO ABI size'
Assert-True ([Runtime.InteropServices.Marshal]::SizeOf([Type][DISPLAYCONFIG_SOURCE_DEVICE_NAME]) -eq 84) 'DISPLAYCONFIG_SOURCE_DEVICE_NAME ABI size'
Assert-True ([Runtime.InteropServices.Marshal]::SizeOf([Type][DISPLAYCONFIG_TARGET_DEVICE_NAME]) -eq 420) 'DISPLAYCONFIG_TARGET_DEVICE_NAME ABI size'

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('MonitorManager.SafeTests.' + [Guid]::NewGuid().ToString('N'))
New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null

try {
    $script:TemplateDir = $tempRoot
    $script:TemplateFile = Join-Path $tempRoot 'templates.json'
    $script:MonitorNamesFile = Join-Path $tempRoot 'monitor_names.json'
    $suffix = [Guid]::NewGuid().ToString('N')
    $script:DataMutexName = "Local\MonitorManager.SafeTests.Data.$suffix"
    $script:DisplayMutexName = "Local\MonitorManager.SafeTests.Display.$suffix"
    $script:MockDpi = 150
    $script:MockBitsPerPel = 32
    $script:MockWidth = 2560
    $script:MockHeight = 1440
    $script:MockRefreshRate = 144

    function Get-Monitors {
        $items = @(New-TestMonitor)
        return ,$items
    }

    $saved = Save-TemplateCore '1' '  work  '
    Assert-True $saved.success 'valid template save'
    Assert-True ($saved.name -eq 'work') 'template name is trimmed'
    Assert-True ([int]$saved.template.dpiScale -eq 150) 'known DPI is saved'

    $duplicate = Save-TemplateCore '1' 'duplicate-parameters'
    Assert-True (-not $duplicate.success) 'duplicate template parameters are rejected'
    Assert-True ([bool]$duplicate.duplicate) 'duplicate result is identified'
    Assert-True ($duplicate.duplicateName -eq 'work') 'duplicate result identifies the existing template'
    Assert-True (@((Load-Templates).monitors.'MON-TEST'.templates).Count -eq 1) 'duplicate save does not add a template'

    Assert-True (Test-TemplateParametersMatch -Template $saved.template -Width 2560 -Height 1440 -RefreshRate 144 -BitsPerPel 32 -DpiScale 150) 'exact template parameters match'
    Assert-True (Test-TemplateParametersMatch -Template $saved.template -Width 2560 -Height 1440 -RefreshRate 143 -BitsPerPel 32 -DpiScale 150 -RefreshTolerance 1) 'one-hertz readback difference matches for selection'
    Assert-True (-not (Test-TemplateParametersMatch -Template $saved.template -Width 2560 -Height 1440 -RefreshRate 144 -BitsPerPel 32 -DpiScale 125)) 'different DPI does not match'

    $selectionData = Load-Templates
    $selectionData.monitors.'MON-TEST'.templates += [PSCustomObject]@{
        name = 'manual'; created = '2026-01-01 00:00:00'
        width = 1920; height = 1080; refreshRate = 60; bitsPerPel = 32; dpiScale = 125
    }
    $currentMonitor = New-TestMonitor
    $automaticSelection = Get-PreferredTemplateName -Templates $selectionData -Monitor $currentMonitor
    Assert-True ($automaticSelection -eq 'work') 'current display parameters select the matching template'
    $manualSelection = Get-PreferredTemplateName -Templates $selectionData -Monitor $currentMonitor -PreviousTemplateName 'manual' -PreviousMonitorId 'MON-TEST'
    Assert-True ($manualSelection -eq 'manual') 'manual selection is preserved on the same monitor'
    $switchedSelection = Get-PreferredTemplateName -Templates $selectionData -Monitor $currentMonitor -PreviousTemplateName 'manual' -PreviousMonitorId 'MON-OTHER'
    Assert-True ($switchedSelection -eq 'work') 'switching monitors recalculates the matching template'
    $offlineMonitor = New-TestMonitor
    $offlineMonitor.IsConnected = $false
    $offlineMonitor.IsActive = $false
    $offlineSelection = Get-PreferredTemplateName -Templates $selectionData -Monitor $offlineMonitor
    Assert-True ([string]::IsNullOrEmpty($offlineSelection)) 'offline monitor has no automatic current-parameter selection'
    $inactiveMonitor = New-TestMonitor
    $inactiveMonitor.IsActive = $false
    $inactiveSelection = Get-PreferredTemplateName -Templates $selectionData -Monitor $inactiveMonitor
    Assert-True ([string]::IsNullOrEmpty($inactiveSelection)) 'connected but inactive monitor has no automatic current-parameter selection'

    $script:MockWidth = 1920
    $script:MockDpi = 0
    $preserved = Save-TemplateCore '1' 'work'
    Assert-True $preserved.success 'same-name save with unknown DPI'
    Assert-True $preserved.dpiPreserved 'existing DPI preservation flag'
    Assert-True ([int]$preserved.template.dpiScale -eq 150) 'existing DPI is preserved'

    $unknownNew = Save-TemplateCore '1' 'new-with-unknown-dpi'
    Assert-True (-not $unknownNew.success) 'new template with unknown DPI is rejected'

    $script:MockWidth = 2560
    $script:MockDpi = 150

    $blank = Save-TemplateCore '1' '   '
    Assert-True (-not $blank.success) 'whitespace-only template name is rejected'

    $longMonitorName = Set-MonitorCustomName 'MON-TEST' ('x' * 101)
    Assert-True (-not $longMonitorName.success) 'overlong monitor name is rejected'
    Assert-True (-not (Test-Path -LiteralPath $script:MonitorNamesFile)) 'invalid monitor name does not create a data file'

    $script:MockDpi = 150
    $script:MockBitsPerPel = 0
    $badBpp = Save-TemplateCore '1' 'bad-bpp'
    Assert-True (-not $badBpp.success) 'invalid color depth is rejected'
    $script:MockBitsPerPel = 32

    Set-Content -LiteralPath $script:TemplateFile -Value '{broken' -Encoding UTF8
    $corruptTemplateBefore = Get-Content -LiteralPath $script:TemplateFile -Raw -Encoding UTF8
    $blockedTemplateWrite = Save-TemplateCore '1' 'must-not-overwrite'
    $corruptTemplateAfter = Get-Content -LiteralPath $script:TemplateFile -Raw -Encoding UTF8
    Assert-True (-not $blockedTemplateWrite.success) 'write is blocked for corrupt template data'
    Assert-True ($corruptTemplateAfter -eq $corruptTemplateBefore) 'corrupt template file remains untouched'
    Assert-True (@(Get-ChildItem -LiteralPath $tempRoot -Filter 'templates.json.corrupted.*.bak').Count -ge 1) 'corrupt template backup exists'

    Set-Content -LiteralPath $script:TemplateFile -Value '{}' -Encoding UTF8
    $invalidTemplateShapeBefore = Get-Content -LiteralPath $script:TemplateFile -Raw -Encoding UTF8
    $blockedTemplateShape = Save-TemplateCore '1' 'must-not-replace-invalid-shape'
    $invalidTemplateShapeAfter = Get-Content -LiteralPath $script:TemplateFile -Raw -Encoding UTF8
    Assert-True (-not $blockedTemplateShape.success) 'write is blocked for unsupported template JSON shape'
    Assert-True ($invalidTemplateShapeAfter -eq $invalidTemplateShapeBefore) 'unsupported template JSON shape remains untouched'

    $invalidValueData = [PSCustomObject]@{ monitors = [PSCustomObject]@{} }
    $invalidValueData.monitors | Add-Member -MemberType NoteProperty -Name 'MON-TEST' -Value ([PSCustomObject]@{
        name = 'Test Monitor'
        templates = @([PSCustomObject]@{
            name = 'invalid-value'; created = '2026-01-01 00:00:00'
            width = 'not-a-number'; height = 1080; refreshRate = 60; bitsPerPel = 32; dpiScale = 125
        })
    })
    $invalidValueData | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $script:TemplateFile -Encoding UTF8
    $invalidValueBefore = Get-Content -LiteralPath $script:TemplateFile -Raw -Encoding UTF8
    $blockedInvalidValue = Save-TemplateCore '1' 'must-not-replace-invalid-value'
    $invalidValueAfter = Get-Content -LiteralPath $script:TemplateFile -Raw -Encoding UTF8
    Assert-True (-not $blockedInvalidValue.success) 'write is blocked for non-numeric template values'
    Assert-True ($invalidValueAfter -eq $invalidValueBefore) 'template with non-numeric values remains untouched'
    Assert-True (-not (Save-Templates $invalidValueData)) 'internal save boundary rejects invalid template values'

    $invalidValueData.monitors.'MON-TEST'.templates[0].width = 1920
    $invalidValueData.monitors.'MON-TEST'.templates[0].dpiScale = 110
    $invalidValueData | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $script:TemplateFile -Encoding UTF8
    $blockedInvalidDpi = Save-TemplateCore '1' 'must-not-replace-invalid-dpi'
    Assert-True (-not $blockedInvalidDpi.success) 'write is blocked for unsupported stored DPI values'

    Set-Content -LiteralPath $script:MonitorNamesFile -Value '{broken' -Encoding UTF8
    $corruptNamesBefore = Get-Content -LiteralPath $script:MonitorNamesFile -Raw -Encoding UTF8
    $blockedNameWrite = Set-MonitorCustomName 'MON-TEST' 'Renamed'
    $corruptNamesAfter = Get-Content -LiteralPath $script:MonitorNamesFile -Raw -Encoding UTF8
    Assert-True (-not $blockedNameWrite.success) 'write is blocked for corrupt monitor-name data'
    Assert-True ($corruptNamesAfter -eq $corruptNamesBefore) 'corrupt monitor-name file remains untouched'
    Assert-True (@(Get-ChildItem -LiteralPath $tempRoot -Filter 'monitor_names.json.corrupted.*.bak').Count -ge 1) 'corrupt monitor-name backup exists'

    Set-Content -LiteralPath $script:MonitorNamesFile -Value '[]' -Encoding UTF8
    $invalidNamesShapeBefore = Get-Content -LiteralPath $script:MonitorNamesFile -Raw -Encoding UTF8
    $blockedNamesShape = Set-MonitorCustomName 'MON-TEST' 'Must Not Replace'
    $invalidNamesShapeAfter = Get-Content -LiteralPath $script:MonitorNamesFile -Raw -Encoding UTF8
    Assert-True (-not $blockedNamesShape.success) 'write is blocked for unsupported monitor-name JSON shape'
    Assert-True ($invalidNamesShapeAfter -eq $invalidNamesShapeBefore) 'unsupported monitor-name JSON shape remains untouched'

    $legacyData = [PSCustomObject]@{
        templates = @([PSCustomObject]@{
            name = 'legacy-template'; created = '2025-01-01 00:00:00'
            monitors = @([PSCustomObject]@{
                monitorId = 'MON-TEST'; monitorName = 'Test Monitor'
                width = 1280; height = 720; refreshRate = 60; bitsPerPel = 32; dpiScale = 125
            })
        })
    }
    $legacyData | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $script:TemplateFile -Encoding UTF8
    $script:MockDpi = 150
    $legacySave = Save-TemplateCore '1' 'after-migration'
    Assert-True $legacySave.success 'valid legacy data migrates during a write'
    Assert-True (Test-Path -LiteralPath "$($script:TemplateFile).bak") 'legacy backup exists before replacement'
    $migrated = Load-Templates
    Assert-True (@($migrated.monitors.'MON-TEST'.templates).Count -eq 2) 'legacy and new templates survive migration'

    # A failed legacy backup must block the write and must not be mislabeled as JSON corruption.
    $legacyData | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $script:TemplateFile -Encoding UTF8
    Get-ChildItem -LiteralPath $tempRoot -Filter 'templates.json.corrupted.*.bak' | Remove-Item -Force
    $legacyBeforeFailedBackup = Get-Content -LiteralPath $script:TemplateFile -Raw -Encoding UTF8
    try {
        function Copy-Item { throw 'simulated legacy backup failure' }
        $blockedMigration = Save-TemplateCore '1' 'must-not-migrate'
    } finally {
        Remove-Item -LiteralPath Function:\Copy-Item -ErrorAction SilentlyContinue
    }
    $legacyAfterFailedBackup = Get-Content -LiteralPath $script:TemplateFile -Raw -Encoding UTF8
    Assert-True (-not $blockedMigration.success) 'legacy write is blocked when backup fails'
    Assert-True ($legacyAfterFailedBackup -eq $legacyBeforeFailedBackup) 'legacy file remains untouched when backup fails'
    Assert-True (@(Get-ChildItem -LiteralPath $tempRoot -Filter 'templates.json.corrupted.*.bak').Count -eq 0) 'migration failure is not mislabeled as corruption'

    Remove-Item -LiteralPath $script:TemplateFile -Force
    $offlineData = [PSCustomObject]@{ monitors = [PSCustomObject]@{} }
    $offlineData.monitors | Add-Member -MemberType NoteProperty -Name 'MON-OFFLINE' -Value ([PSCustomObject]@{
        name = 'Offline Monitor'
        templates = @([PSCustomObject]@{
            name = 'offline-template'; created = '2026-01-01 00:00:00'
            width = 1920; height = 1080; refreshRate = 60; bitsPerPel = 32; dpiScale = 125
        })
    })
    Assert-True (Save-Templates $offlineData) 'offline fixture save'
    $deleted = Delete-TemplateCore 'MON-OFFLINE' 'offline-template'
    Assert-True $deleted.success 'offline template deletion'
    $afterDelete = Load-Templates
    Assert-True ($null -eq $afterDelete.monitors.PSObject.Properties['MON-OFFLINE']) 'empty offline group is removed'

    # Simulate a failed global commit. All native display-changing calls are replaced,
    # so this verifies rollback orchestration without touching a real display.
    $rollbackData = [PSCustomObject]@{ monitors = [PSCustomObject]@{} }
    $rollbackData.monitors | Add-Member -MemberType NoteProperty -Name 'MON-TEST' -Value ([PSCustomObject]@{
        name = 'Test Monitor'
        templates = @([PSCustomObject]@{
            name = 'rollback-case'; created = '2026-01-01 00:00:00'
            width = 1920; height = 1080; refreshRate = 60; bitsPerPel = 32; dpiScale = 125
        })
    })
    Assert-True (Save-Templates $rollbackData) 'rollback fixture save'

    $script:StageCallCount = 0
    $script:CommitCallCount = 0
    $script:PendingWidth = 0
    $script:PendingHeight = 0
    $script:PendingRefreshRate = 0
    $script:PendingBitsPerPel = 0

    function Start-Sleep { param([int]$Milliseconds, [int]$Seconds) }
    function Get-CurrentDisplayModeSnapshot {
        param([string]$DisplayName)
        $mode = New-Object DEVMODE
        $mode.dmSize = [Runtime.InteropServices.Marshal]::SizeOf([Type][DEVMODE])
        $mode.dmPelsWidth = $script:MockWidth
        $mode.dmPelsHeight = $script:MockHeight
        $mode.dmDisplayFrequency = $script:MockRefreshRate
        $mode.dmBitsPerPel = $script:MockBitsPerPel
        $mode.dmFields = $DM_PELSWIDTH -bor $DM_PELSHEIGHT -bor $DM_DISPLAYFREQUENCY -bor $DM_BITSPERPEL
        return @{ success = $true; mode = $mode }
    }
    function Set-PendingDisplayMode {
        param([string]$DisplayName, $Mode)
        $script:StageCallCount++
        $script:PendingWidth = [int]$Mode.dmPelsWidth
        $script:PendingHeight = [int]$Mode.dmPelsHeight
        $script:PendingRefreshRate = [int]$Mode.dmDisplayFrequency
        $script:PendingBitsPerPel = [int]$Mode.dmBitsPerPel
        return 0
    }
    function Commit-PendingDisplayModes {
        $script:CommitCallCount++
        if ($script:CommitCallCount -eq 1) { return -1 }
        $script:MockWidth = $script:PendingWidth
        $script:MockHeight = $script:PendingHeight
        $script:MockRefreshRate = $script:PendingRefreshRate
        $script:MockBitsPerPel = $script:PendingBitsPerPel
        return 0
    }
    function Set-DpiScale {
        param($AdapterId, [uint32]$SourceId, [int]$TargetScale)
        $script:MockDpi = $TargetScale
        return @{ success = $true; code = 0; message = 'OK' }
    }

    $applyFailure = Apply-TemplateCore '1' 'rollback-case'
    Assert-True (-not $applyFailure.success) 'commit failure is reported'
    Assert-True ([bool]$applyFailure.result.rollbackAttempted) 'rollback is attempted after commit failure'
    Assert-True ([bool]$applyFailure.result.rollbackSuccess) 'rollback is verified after commit failure'
    Assert-True ($script:StageCallCount -eq 2) 'target and rollback modes are both staged'
    Assert-True ($script:CommitCallCount -eq 2) 'target and rollback commits are both attempted'
    Assert-True ($script:MockWidth -eq 2560 -and $script:MockHeight -eq 1440 -and $script:MockRefreshRate -eq 144) 'original display mode is restored'
    Assert-True ($script:MockDpi -eq 150) 'original DPI is restored'

    # Simulate a successful commit whose mode never matches the requested values.
    $script:StageCallCount = 0
    $script:CommitCallCount = 0
    $script:MockWidth = 2560
    $script:MockHeight = 1440
    $script:MockRefreshRate = 144
    $script:MockBitsPerPel = 32
    $script:MockDpi = 150
    function Commit-PendingDisplayModes {
        $script:CommitCallCount++
        if ($script:PendingWidth -eq 1920) {
            $script:MockWidth = 1600
            $script:MockHeight = 900
            $script:MockRefreshRate = 59
            $script:MockBitsPerPel = 32
        } else {
            $script:MockWidth = $script:PendingWidth
            $script:MockHeight = $script:PendingHeight
            $script:MockRefreshRate = $script:PendingRefreshRate
            $script:MockBitsPerPel = $script:PendingBitsPerPel
        }
        return 0
    }
    $verifyFailure = Apply-TemplateCore '1' 'rollback-case'
    Assert-True (-not $verifyFailure.success) 'mode verification failure is reported'
    Assert-True ([bool]$verifyFailure.result.rollbackSuccess) 'mode verification failure is rolled back'
    Assert-True ($script:StageCallCount -eq 2 -and $script:CommitCallCount -eq 2) 'mode mismatch triggers one rollback'
    Assert-True ($script:MockWidth -eq 2560 -and $script:MockHeight -eq 1440 -and $script:MockRefreshRate -eq 144) 'mode mismatch restores original display mode'

    # Simulate a DPI API failure after the target display mode was verified.
    $script:StageCallCount = 0
    $script:CommitCallCount = 0
    $script:DpiCallCount = 0
    $script:MockWidth = 2560
    $script:MockHeight = 1440
    $script:MockRefreshRate = 144
    $script:MockBitsPerPel = 32
    $script:MockDpi = 150
    function Commit-PendingDisplayModes {
        $script:CommitCallCount++
        $script:MockWidth = $script:PendingWidth
        $script:MockHeight = $script:PendingHeight
        $script:MockRefreshRate = $script:PendingRefreshRate
        $script:MockBitsPerPel = $script:PendingBitsPerPel
        return 0
    }
    function Set-DpiScale {
        param($AdapterId, [uint32]$SourceId, [int]$TargetScale)
        $script:DpiCallCount++
        if ($script:DpiCallCount -eq 1) {
            return @{ success = $false; code = 5; message = 'simulated DPI failure' }
        }
        $script:MockDpi = $TargetScale
        return @{ success = $true; code = 0; message = 'OK' }
    }
    $dpiFailure = Apply-TemplateCore '1' 'rollback-case'
    Assert-True (-not $dpiFailure.success) 'DPI failure is reported'
    Assert-True ([bool]$dpiFailure.result.rollbackSuccess) 'DPI failure is rolled back'
    Assert-True ($script:StageCallCount -eq 2 -and $script:CommitCallCount -eq 2) 'DPI failure triggers one mode rollback'
    Assert-True ($script:DpiCallCount -eq 2) 'DPI rollback is attempted after target DPI failure'
    Assert-True ($script:MockWidth -eq 2560 -and $script:MockHeight -eq 1440 -and $script:MockRefreshRate -eq 144) 'DPI failure restores original display mode'
    Assert-True ($script:MockDpi -eq 150) 'DPI failure restores original DPI'

    $script:MockDpi = 150
    $script:DpiCallCount = 0
    function Set-DpiScale {
        param($AdapterId, [uint32]$SourceId, [int]$TargetScale)
        $script:DpiCallCount++
        $script:MockDpi = $TargetScale
        return @{ success = $true; code = 0; message = 'OK' }
    }
    $verifiedDpi = Set-DpiScaleVerified '1' 125
    Assert-True $verifiedDpi.success 'standalone DPI change is verified'
    Assert-True ([bool]$verifiedDpi.verified -and $script:MockDpi -eq 125 -and $script:DpiCallCount -eq 1) 'standalone DPI success matches readback'

    $script:MockDpi = 150
    $script:DpiCallCount = 0
    function Set-DpiScale {
        param($AdapterId, [uint32]$SourceId, [int]$TargetScale)
        $script:DpiCallCount++
        if ($script:DpiCallCount -gt 1) { $script:MockDpi = $TargetScale }
        return @{ success = $true; code = 0; message = 'OK' }
    }
    $unverifiedDpi = Set-DpiScaleVerified '1' 125
    Assert-True (-not $unverifiedDpi.success) 'standalone DPI readback mismatch is reported'
    Assert-True ([bool]$unverifiedDpi.rollbackSuccess) 'standalone DPI readback mismatch is rolled back'
    Assert-True ($script:MockDpi -eq 150 -and $script:DpiCallCount -eq 2) 'standalone DPI rollback restores original value'

    $script:MockDpi = 0
    $script:DpiCallCount = 0
    $unknownOriginalDpi = Set-DpiScaleVerified '1' 125
    Assert-True (-not $unknownOriginalDpi.success) 'standalone DPI change requires a readable original value'
    Assert-True ($script:DpiCallCount -eq 0) 'unknown original DPI causes no write'

    # Display power tests below replace every native topology write with a test double.
    # They must never call SetDisplayConfig on the real desktop.
    function New-TestDisplayPath {
        param(
            [uint32]$SourceId,
            [uint32]$TargetId,
            [bool]$Active = $true,
            [bool]$TargetAvailable = $true
        )
        $adapter = New-Object LUID
        $adapter.LowPart = 42
        $adapter.HighPart = 0

        $source = New-Object DISPLAYCONFIG_PATH_SOURCE_INFO
        $source.adapterId = $adapter
        $source.id = $SourceId
        $source.modeInfoIdx = [uint32]7

        $target = New-Object DISPLAYCONFIG_PATH_TARGET_INFO
        $target.adapterId = $adapter
        $target.id = $TargetId
        $target.modeInfoIdx = [uint32]8
        $target.targetAvailable = $TargetAvailable

        $path = New-Object DISPLAYCONFIG_PATH_INFO
        $path.sourceInfo = $source
        $path.targetInfo = $target
        $path.flags = if ($Active) { [uint32]$DISPLAYCONFIG_PATH_ACTIVE } else { [uint32]0 }
        return $path
    }

    function New-TestPowerMonitor {
        param(
            [uint32]$TargetId,
            [uint32]$SourceId,
            [bool]$Active,
            [bool]$Primary = $false,
            [bool]$Connected = $true
        )
        $adapter = New-Object LUID
        $adapter.LowPart = 42
        $adapter.HighPart = 0
        return [PSCustomObject]@{
            DisplayName = if ($Active) { "\\.\DISPLAY$($SourceId + 1)" } else { '' }
            MonitorName = "Power Monitor $TargetId"
            MonitorId = "POWER-$TargetId"
            Width = if ($Active) { 1920 } else { 0 }
            Height = if ($Active) { 1080 } else { 0 }
            RefreshRate = if ($Active) { 60 } else { 0 }
            BitsPerPel = if ($Active) { 32 } else { 0 }
            DpiScale = if ($Active) { 100 } else { 0 }
            AdapterId = $adapter
            TargetAdapterId = $adapter
            SourceId = $SourceId
            TargetId = $TargetId
            IsPrimary = $Primary
            IsConnected = $Connected
            IsActive = $Active
        }
    }

    $pathOne = New-TestDisplayPath -SourceId 0 -TargetId 1 -Active $true
    $pathTwo = New-TestDisplayPath -SourceId 1 -TargetId 2 -Active $false
    $pathOnly = ConvertTo-PathOnlyTopology -Paths @($pathOne, $pathTwo)
    Assert-True ($pathOnly.Count -eq 2) 'path-only topology retains every requested target'
    Assert-True ($pathOnly[0].sourceInfo.modeInfoIdx -eq [uint32]::MaxValue -and $pathOnly[0].targetInfo.modeInfoIdx -eq [uint32]::MaxValue) 'path-only topology invalidates both mode indices'
    Assert-True (($pathOnly[1].flags -band $DISPLAYCONFIG_PATH_ACTIVE) -ne 0) 'path-only topology marks every desired path active'

    $originAdapter = New-Object LUID
    $originAdapter.LowPart = 42
    $originSourceMode = New-Object DISPLAYCONFIG_SOURCE_MODE
    $originPosition = New-Object POINT
    $originPosition.x = 0
    $originPosition.y = 0
    $originSourceMode.position = $originPosition
    $originUnion = New-Object DISPLAYCONFIG_MODE_INFO_UNION
    $originUnion.sourceMode = $originSourceMode
    $originMode = New-Object DISPLAYCONFIG_MODE_INFO
    $originMode.infoType = [uint32]$DISPLAYCONFIG_MODE_INFO_TYPE_SOURCE
    $originMode.id = [uint32]0
    $originMode.adapterId = $originAdapter
    $originMode.modeInfo = $originUnion
    $originPath = New-TestDisplayPath -SourceId 0 -TargetId 1 -Active $true
    $originPathSource = $originPath.sourceInfo
    $originPathSource.modeInfoIdx = [uint32]0
    $originPath.sourceInfo = $originPathSource
    Assert-True (Test-DisplayPathAtDesktopOrigin -Path $originPath -Modes @($originMode)) 'DisplayConfig source at desktop origin is recognized as primary'
    $nonOriginPosition = $originMode.modeInfo.sourceMode.position
    $nonOriginPosition.x = 1920
    $nonOriginSourceMode = $originMode.modeInfo.sourceMode
    $nonOriginSourceMode.position = $nonOriginPosition
    $nonOriginUnion = $originMode.modeInfo
    $nonOriginUnion.sourceMode = $nonOriginSourceMode
    $originMode.modeInfo = $nonOriginUnion
    Assert-True (-not (Test-DisplayPathAtDesktopOrigin -Path $originPath -Modes @($originMode))) 'non-origin DisplayConfig source is not recognized as primary'

    # Validate the exact SetDisplayConfig flag sequences without calling the native API.
    $script:SetDisplayResponses = @(0, 0)
    $script:SetDisplayCalls = @()
    function Invoke-NativeSetDisplayConfig {
        param($Paths, $Modes, [uint32]$Flags)
        $script:SetDisplayCalls += [PSCustomObject]@{
            Flags = $Flags
            PathCount = @($Paths).Count
            ModeCount = @($Modes).Count
        }
        $response = $script:SetDisplayResponses[$script:SetDisplayCalls.Count - 1]
        return [int]$response
    }
    $databaseTopology = Set-PathOnlyDisplayTopology -Paths @($pathOne)
    Assert-True $databaseTopology.success 'saved database topology path succeeds'
    Assert-True ($script:SetDisplayCalls.Count -eq 2) 'saved topology performs validate then apply'
    Assert-True ($script:SetDisplayCalls[0].Flags -eq [uint32]($SDC_VALIDATE -bor $SDC_TOPOLOGY_SUPPLIED -bor $SDC_ALLOW_PATH_ORDER_CHANGES)) 'database topology validation uses only legal flags'
    Assert-True ($script:SetDisplayCalls[1].Flags -eq [uint32]($SDC_APPLY -bor $SDC_TOPOLOGY_SUPPLIED -bor $SDC_ALLOW_PATH_ORDER_CHANGES)) 'database topology apply uses only legal flags'
    Assert-True ($script:SetDisplayCalls[0].ModeCount -eq 0 -and $script:SetDisplayCalls[1].ModeCount -eq 0) 'database topology path does not supply stale modes'

    $script:SetDisplayResponses = @(87, 0, 0)
    $script:SetDisplayCalls = @()
    $bestModeTopology = Set-PathOnlyDisplayTopology -Paths @($pathOne, $pathTwo)
    Assert-True $bestModeTopology.success 'best-mode fallback succeeds when database topology is unavailable'
    Assert-True ($script:SetDisplayCalls.Count -eq 3) 'best-mode fallback validates before applying'
    Assert-True ($script:SetDisplayCalls[1].Flags -eq [uint32]($SDC_VALIDATE -bor $SDC_USE_SUPPLIED_DISPLAY_CONFIG -bor $SDC_ALLOW_CHANGES)) 'best-mode validation uses legal supplied-config flags'
    Assert-True ($script:SetDisplayCalls[2].Flags -eq [uint32]($SDC_APPLY -bor $SDC_USE_SUPPLIED_DISPLAY_CONFIG -bor $SDC_SAVE_TO_DATABASE -bor $SDC_ALLOW_CHANGES)) 'best-mode apply persists only with supplied-config flags'

    $script:SetDisplayResponses = @(0)
    $script:SetDisplayCalls = @()
    $restoreSnapshot = @{ success = $true; paths = [DISPLAYCONFIG_PATH_INFO[]]@($pathOne); modes = [DISPLAYCONFIG_MODE_INFO[]]@() }
    $restoreTopology = Restore-DisplayTopology -Snapshot $restoreSnapshot
    Assert-True $restoreTopology.success 'exact topology rollback can be submitted'
    Assert-True ($script:SetDisplayCalls.Count -eq 1) 'rollback submits one native configuration'
    Assert-True ($script:SetDisplayCalls[0].Flags -eq [uint32]($SDC_APPLY -bor $SDC_USE_SUPPLIED_DISPLAY_CONFIG -bor $SDC_SAVE_TO_DATABASE -bor $SDC_ALLOW_CHANGES)) 'rollback uses a legal persisted supplied-config combination'

    $script:PowerMonitors = @()
    $script:PowerOriginalPaths = @()
    $script:PowerAllPaths = @()
    $script:PowerTopologyReads = 0
    $script:PowerChangeCalls = 0
    $script:PowerRestoreCalls = 0
    $script:PowerChangeResult = @{ success = $true; code = 0; method = 'test' }
    $script:PowerVerifyResult = @{ success = $true; activeCount = 1 }
    $script:PowerDesiredPaths = @()

    function Get-Monitors { return ,@($script:PowerMonitors) }
    function Get-DisplayConfigTopology {
        param([uint32]$Flags)
        $script:PowerTopologyReads++
        if ($Flags -eq $QDC_ONLY_ACTIVE_PATHS) {
            return @{ success = $true; code = 0; paths = [DISPLAYCONFIG_PATH_INFO[]]@($script:PowerOriginalPaths); modes = [DISPLAYCONFIG_MODE_INFO[]]@() }
        }
        return @{ success = $true; code = 0; paths = [DISPLAYCONFIG_PATH_INFO[]]@($script:PowerAllPaths); modes = [DISPLAYCONFIG_MODE_INFO[]]@() }
    }
    function Set-PathOnlyDisplayTopology {
        param($Paths)
        $script:PowerChangeCalls++
        $script:PowerDesiredPaths = @($Paths)
        return $script:PowerChangeResult
    }

    # Exercise the real verifier before replacing it below: MonitorId aliases can change when
    # a driver promotes an inactive target into the active desktop, but the physical target key cannot.
    $identityMonitorOne = New-TestPowerMonitor -TargetId 1 -SourceId 0 -Active $true -Primary $true
    $identityMonitorTwo = New-TestPowerMonitor -TargetId 2 -SourceId 1 -Active $true
    $identityMonitorTwo.MonitorId = 'POWER-2-ACTIVE-ALIAS'
    $script:PowerMonitors = @($identityMonitorOne, $identityMonitorTwo)
    $resolvedAcrossAlias = Resolve-MonitorByTargetIdentity -Monitors $script:PowerMonitors -MonitorId 'POWER-2-INACTIVE-ALIAS' -TargetKey (Get-MonitorTargetKey $identityMonitorTwo)
    Assert-True ($resolvedAcrossAlias -and $resolvedAcrossAlias.MonitorId -eq 'POWER-2-ACTIVE-ALIAS') 'GUI power target resolution prefers physical identity over a stale MonitorId alias'
    $physicalIdentityVerified = Wait-MonitorPowerState -TargetKey (Get-MonitorTargetKey (New-TestPowerMonitor -TargetId 2 -SourceId 1 -Active $false)) -DesiredActive $true -ExpectedActiveCount 2 -Attempts 1
    Assert-True $physicalIdentityVerified.success 'power verification follows the physical target when MonitorId changes'

    # WinForms may temporarily report no Primary immediately after the old primary is disconnected.
    # The requested target state and exact active count are authoritative and must not be rolled back.
    $successorWithoutCachedPrimary = New-TestPowerMonitor -TargetId 1 -SourceId 0 -Active $true -Primary $false
    $disconnectedFormerPrimary = New-TestPowerMonitor -TargetId 2 -SourceId 1 -Active $false -Primary $false
    $script:PowerMonitors = @($successorWithoutCachedPrimary, $disconnectedFormerPrimary)
    $primaryCacheLagVerified = Wait-MonitorPowerState -TargetKey (Get-MonitorTargetKey $disconnectedFormerPrimary) -DesiredActive $false -ExpectedActiveCount 1 -Attempts 1
    Assert-True $primaryCacheLagVerified.success 'disconnecting the former primary is not rolled back solely because Screen.Primary is stale'
    Assert-True (-not [bool]$primaryCacheLagVerified.primaryObserved) 'primary cache-lag result is recorded for diagnostics'

    function Wait-MonitorPowerState {
        param([string]$TargetKey, [bool]$DesiredActive, [int]$ExpectedActiveCount, [int]$Attempts = 8)
        $script:PowerWaitTargetKey = $TargetKey
        $script:PowerWaitDesiredActive = $DesiredActive
        $script:PowerWaitExpectedCount = $ExpectedActiveCount
        return $script:PowerVerifyResult
    }
    function Restore-DisplayTopology {
        param($Snapshot)
        $script:PowerRestoreCalls++
        return @{ success = $true; code = 0; message = 'test rollback' }
    }

    $monitorOne = New-TestPowerMonitor -TargetId 1 -SourceId 0 -Active $true -Primary $true
    $monitorTwo = New-TestPowerMonitor -TargetId 2 -SourceId 1 -Active $true
    $inactiveTwo = New-TestPowerMonitor -TargetId 2 -SourceId 1 -Active $false

    $script:PowerMonitors = @($monitorOne)
    $script:PowerTopologyReads = 0
    $script:PowerChangeCalls = 0
    $lastActiveBlocked = Invoke-MonitorPowerCoreUnlocked -MonitorSpec '1' -Operation off
    Assert-True (-not $lastActiveBlocked.success -and [bool]$lastActiveBlocked.safetyBlocked) 'last active monitor cannot be turned off'
    Assert-True ($script:PowerTopologyReads -eq 0 -and $script:PowerChangeCalls -eq 0) 'last-active guard performs no topology write'

    $script:PowerMonitors = @($monitorOne, $monitorTwo)
    $script:PowerOriginalPaths = @(
        (New-TestDisplayPath -SourceId 0 -TargetId 1 -Active $true),
        (New-TestDisplayPath -SourceId 1 -TargetId 2 -Active $true)
    )
    $script:PowerAllPaths = @($script:PowerOriginalPaths)
    $script:PowerChangeResult = @{ success = $true; code = 0; method = 'test' }
    $script:PowerVerifyResult = @{ success = $true; activeCount = 1 }
    $script:PowerChangeCalls = 0
    $script:PowerRestoreCalls = 0
    $powerOff = Invoke-MonitorPowerCoreUnlocked -MonitorSpec '2' -Operation off
    Assert-True $powerOff.success ("one of two active monitors can be turned off: " + ($powerOff | ConvertTo-Json -Depth 5 -Compress))
    Assert-True ($script:PowerChangeCalls -eq 1 -and $script:PowerDesiredPaths.Count -eq 1) 'turning off removes exactly one physical target path'
    Assert-True ((Get-DisplayPathTargetKey $script:PowerDesiredPaths[0]) -eq (Get-MonitorTargetKey $monitorOne)) 'turning off retains the other monitor path'
    Assert-True ($script:PowerWaitTargetKey -eq (Get-MonitorTargetKey $monitorTwo)) 'turn-off verification uses the physical target key'
    Assert-True (-not $script:PowerWaitDesiredActive -and $script:PowerWaitExpectedCount -eq 1) 'turn-off verification checks target state and active count'

    $script:PowerMonitors = @($monitorOne, $inactiveTwo)
    $script:PowerOriginalPaths = @((New-TestDisplayPath -SourceId 0 -TargetId 1 -Active $true))
    $script:PowerAllPaths = @(
        (New-TestDisplayPath -SourceId 0 -TargetId 1 -Active $true),
        (New-TestDisplayPath -SourceId 1 -TargetId 2 -Active $false)
    )
    $script:PowerVerifyResult = @{ success = $true; activeCount = 2 }
    $script:PowerChangeCalls = 0
    $powerOn = Invoke-MonitorPowerCoreUnlocked -MonitorSpec '2' -Operation on
    Assert-True $powerOn.success 'connected inactive monitor can be turned on with a free source'
    Assert-True ($script:PowerDesiredPaths.Count -eq 2) 'turning on appends exactly one target path'
    Assert-True ($script:PowerWaitDesiredActive -and $script:PowerWaitExpectedCount -eq 2) 'turn-on verification checks target state and active count'

    $wrappedPowerOn = Invoke-MonitorPowerCore -MonitorSpec '2' -Operation on
    Assert-True $wrappedPowerOn.success 'named-mutex wrapper can resolve and invoke the power core in script scope'

    $script:PowerAllPaths = @(
        (New-TestDisplayPath -SourceId 0 -TargetId 1 -Active $true),
        (New-TestDisplayPath -SourceId 0 -TargetId 2 -Active $false)
    )
    $script:PowerChangeCalls = 0
    $noFreeSource = Invoke-MonitorPowerCoreUnlocked -MonitorSpec '2' -Operation on
    Assert-True (-not $noFreeSource.success -and [bool]$noFreeSource.safetyBlocked) 'turn-on refuses to reuse an active source from a clone group'
    Assert-True ($script:PowerChangeCalls -eq 0) 'no-free-source guard performs no topology write'

    $disconnectedTwo = New-TestPowerMonitor -TargetId 2 -SourceId 1 -Active $false -Connected $false
    $script:PowerMonitors = @($monitorOne, $disconnectedTwo)
    $script:PowerTopologyReads = 0
    $disconnectedBlocked = Invoke-MonitorPowerCoreUnlocked -MonitorSpec '2' -Operation on
    Assert-True (-not $disconnectedBlocked.success) 'disconnected monitor cannot be turned on'
    Assert-True ($script:PowerTopologyReads -eq 0) 'disconnected guard performs no topology access'

    $script:PowerMonitors = @($monitorOne, $monitorTwo)
    $script:PowerOriginalPaths = @(
        (New-TestDisplayPath -SourceId 0 -TargetId 1 -Active $true),
        (New-TestDisplayPath -SourceId 1 -TargetId 2 -Active $true)
    )
    $script:PowerChangeResult = @{ success = $false; code = 5; method = 'test' }
    $script:PowerRestoreCalls = 0
    $applyFailurePower = Invoke-MonitorPowerCoreUnlocked -MonitorSpec '2' -Operation off
    Assert-True (-not $applyFailurePower.success -and [bool]$applyFailurePower.result.rollbackAttempted) 'topology apply failure triggers rollback'
    Assert-True ($script:PowerRestoreCalls -eq 1 -and [bool]$applyFailurePower.result.rollbackSuccess) 'topology apply failure rollback is recorded'

    $script:PowerChangeResult = @{ success = $true; code = 0; method = 'test' }
    $script:PowerVerifyResult = @{ success = $false; activeCount = 2 }
    $script:PowerRestoreCalls = 0
    $verifyFailurePower = Invoke-MonitorPowerCoreUnlocked -MonitorSpec '2' -Operation off
    Assert-True (-not $verifyFailurePower.success -and [bool]$verifyFailurePower.result.rollbackAttempted) 'power-state verification failure triggers rollback'
    Assert-True ($script:PowerRestoreCalls -eq 1 -and [bool]$verifyFailurePower.result.rollbackSuccess) 'verification failure rollback is recorded'

    Write-Output 'SAFE_TESTS_OK'
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
