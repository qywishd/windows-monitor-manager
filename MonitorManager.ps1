<#
.SYNOPSIS
    Windows 多显示器配置管理工具（原生 GUI 程序）
.DESCRIPTION
    功能：
      1. 识别已连接的显示器（分辨率、刷新率、颜色深度）
      2. 针对多显示器配置保存模板
      3. 快速切换模板（GUI / CLI / 交互菜单）
      4. 桌面快捷方式
      5. 单独连接或断开显示器（GUI / CLI，等同 Windows“扩展桌面/断开此显示器”）
.EXAMPLE
    .\MonitorManager.ps1              打开 GUI 程序
    .\MonitorManager.ps1 gui          打开 GUI 程序
    .\MonitorManager.ps1 list         命令行：列出显示器
    .\MonitorManager.ps1 save 工作    命令行：保存模板
    .\MonitorManager.ps1 apply 工作   命令行：应用模板
    .\MonitorManager.ps1 disconnect 2 命令行：断开 2 号显示器
    .\MonitorManager.ps1 connect 2    命令行：连接 2 号显示器
    .\MonitorManager.ps1 shortcut     创建桌面快捷方式
#>

param(
    [Parameter(Position = 0)]
    [string]$Command = 'gui',

    [Parameter(Position = 1)]
    [string]$Arg1,

    [Parameter(Position = 2)]
    [string]$Arg2
)

# CLI 命令通过该值统一向调用方返回可判断的进程退出码：0=成功，1=失败，2=部分成功/用法错误
$script:CommandExitCode = 0
$script:MonitorManagerScriptPath = $PSCommandPath
$script:WorkerResultPrefix = 'MM_RESULT:'

# ============================================================
#  Win32 API 定义
# ============================================================
if (-not ([System.Management.Automation.PSTypeName]'DisplayApi').Type) {
    try {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
public struct DEVMODE {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
    public string dmDeviceName;
    public short dmSpecVersion;
    public short dmDriverVersion;
    public short dmSize;
    public short dmDriverExtra;
    public int dmFields;
    public short dmOrientation;
    public short dmPaperSize;
    public short dmPaperLength;
    public short dmPaperWidth;
    public short dmScale;
    public short dmCopies;
    public short dmDefaultSource;
    public short dmPrintQuality;
    public short dmColor;
    public short dmDuplex;
    public short dmYResolution;
    public short dmTTOption;
    public short dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
    public string dmFormName;
    public short dmLogPixels;
    public int dmBitsPerPel;
    public int dmPelsWidth;
    public int dmPelsHeight;
    public int dmDisplayFlags;
    public int dmDisplayFrequency;
    public int dmICMMethod;
    public int dmICMIntent;
    public int dmMediaType;
    public int dmDitherType;
    public int dmReserved1;
    public int dmReserved2;
    public int dmPanningWidth;
    public int dmPanningHeight;
}

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
public struct DISPLAY_DEVICE {
    public int cb;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
    public string DeviceName;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
    public string DeviceString;
    public int StateFlags;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
    public string DeviceID;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
    public string DeviceKey;
}

// ===== DisplayConfig API 结构体（用于 Per-Monitor DPI 设置）=====
[StructLayout(LayoutKind.Sequential)]
public struct LUID {
    public uint LowPart;
    public int  HighPart;
}

[StructLayout(LayoutKind.Sequential)]
public struct DISPLAYCONFIG_RATIONAL {
    public uint Numerator;
    public uint Denominator;
}

[StructLayout(LayoutKind.Sequential)]
public struct DISPLAYCONFIG_PATH_SOURCE_INFO {
    public LUID adapterId;
    public uint id;
    public uint modeInfoIdx;
    public uint statusFlags;
}

[StructLayout(LayoutKind.Sequential)]
public struct DISPLAYCONFIG_PATH_TARGET_INFO {
    public LUID adapterId;
    public uint id;
    public uint modeInfoIdx;
    public uint outputTechnology;
    public uint rotation;
    public uint scaling;
    public DISPLAYCONFIG_RATIONAL refreshRate;
    public uint scanLineOrder;
    public bool targetAvailable;
    public uint statusFlags;
}

[StructLayout(LayoutKind.Sequential)]
public struct DISPLAYCONFIG_PATH_INFO {
    public DISPLAYCONFIG_PATH_SOURCE_INFO sourceInfo;
    public DISPLAYCONFIG_PATH_TARGET_INFO targetInfo;
    public uint flags;
}

// DISPLAYCONFIG_MODE_INFO 需要完整定义（含 union），否则 QueryDisplayConfig 会导致内存越界
[StructLayout(LayoutKind.Sequential)]
public struct DISPLAYCONFIG_2DREGION {
    public uint cx;
    public uint cy;
}
[StructLayout(LayoutKind.Sequential)]
public struct DISPLAYCONFIG_RATIONAL2 {
    public uint Numerator;
    public uint Denominator;
}
[StructLayout(LayoutKind.Sequential)]
public struct DISPLAYCONFIG_VIDEO_SIGNAL_INFO {
    public ulong pixelRate;
    public DISPLAYCONFIG_RATIONAL2 hSyncFreq;
    public DISPLAYCONFIG_RATIONAL2 vSyncFreq;
    public DISPLAYCONFIG_2DREGION activeSize;
    public DISPLAYCONFIG_2DREGION totalSize;
    public uint videoStandard;
    public uint scanLineOrdering;
}
[StructLayout(LayoutKind.Sequential)]
public struct DISPLAYCONFIG_TARGET_MODE {
    public DISPLAYCONFIG_VIDEO_SIGNAL_INFO targetVideoSignalInfo;
}
[StructLayout(LayoutKind.Sequential)]
public struct POINT {
    public int x;
    public int y;
}
[StructLayout(LayoutKind.Sequential)]
public struct RECT {
    public int left;
    public int top;
    public int right;
    public int bottom;
}
[StructLayout(LayoutKind.Sequential)]
public struct DISPLAYCONFIG_SOURCE_MODE {
    public uint width;
    public uint height;
    public uint pixelFormat;
    public POINT position;
}
[StructLayout(LayoutKind.Sequential)]
public struct DISPLAYCONFIG_DESKTOP_IMAGE_INFO {
    public POINT pathSourceSize;
    public RECT desktopImageRegion;
    public RECT desktopImageClip;
}
[StructLayout(LayoutKind.Explicit, Size = 48)]
public struct DISPLAYCONFIG_MODE_INFO_UNION {
    [FieldOffset(0)]
    public DISPLAYCONFIG_TARGET_MODE targetMode;
    [FieldOffset(0)]
    public DISPLAYCONFIG_SOURCE_MODE sourceMode;
    [FieldOffset(0)]
    public DISPLAYCONFIG_DESKTOP_IMAGE_INFO desktopImageInfo;
}
[StructLayout(LayoutKind.Sequential)]
public struct DISPLAYCONFIG_MODE_INFO {
    public uint infoType;
    public uint id;
    public LUID adapterId;
    public DISPLAYCONFIG_MODE_INFO_UNION modeInfo;
}

[StructLayout(LayoutKind.Sequential)]
public struct DISPLAYCONFIG_DEVICE_INFO_HEADER {
    public int  type;       // DISPLAYCONFIG_DEVICE_INFO_TYPE_CUSTOM（负数）
    public uint size;
    public LUID adapterId;
    public uint id;
}

// 根据 DisplayConfig source 精确取得对应的 GDI 设备名（如 \\.\DISPLAY1）
[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
public struct DISPLAYCONFIG_SOURCE_DEVICE_NAME {
    public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
    public string viewGdiDeviceName;
}

// 根据 DisplayConfig target 精确取得物理显示器名称和 PnP 设备路径。
[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
public struct DISPLAYCONFIG_TARGET_DEVICE_NAME {
    public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
    public uint flags;
    public uint outputTechnology;
    public ushort edidManufactureId;
    public ushort edidProductCodeId;
    public uint connectorInstance;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)]
    public string monitorFriendlyDeviceName;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
    public string monitorDevicePath;
}

// Per-Monitor DPI 获取（逆向值 type=-3，sizeof=32）
[StructLayout(LayoutKind.Sequential)]
public struct DISPLAYCONFIG_SOURCE_DPI_SCALE_GET {
    public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
    public int minScaleRel;   // recommended 向下多少档（负数）
    public int curScaleRel;   // 当前相对 recommended 偏移
    public int maxScaleRel;   // recommended 向上多少档
}

// Per-Monitor DPI 设置（逆向值 type=-4，sizeof=24）
[StructLayout(LayoutKind.Sequential)]
public struct DISPLAYCONFIG_SOURCE_DPI_SCALE_SET {
    public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
    public int scaleRel;   // 相对 recommended 的偏移
}

public static class DisplayApi {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern bool EnumDisplayDevices(string lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern bool EnumDisplaySettingsEx(string lpszDeviceName, int iModeNum, ref DEVMODE lpDevMode, uint dwFlags);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int ChangeDisplaySettingsEx(string lpszDeviceName, ref DEVMODE lpDevMode, IntPtr hwnd, uint dwflags, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int ChangeDisplaySettingsEx(string lpszDeviceName, IntPtr lpDevMode, IntPtr hwnd, uint dwflags, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern int GetDisplayConfigBufferSizes(uint flags, out uint pathCount, out uint modeCount);

    [DllImport("user32.dll")]
    public static extern int QueryDisplayConfig(uint flags, ref uint pathCount, [Out] DISPLAYCONFIG_PATH_INFO[] paths, ref uint modeCount, [Out] DISPLAYCONFIG_MODE_INFO[] modes, IntPtr currentTopologyId);

    [DllImport("user32.dll")]
    public static extern int SetDisplayConfig(uint pathCount, [In] DISPLAYCONFIG_PATH_INFO[] paths, uint modeCount, [In] DISPLAYCONFIG_MODE_INFO[] modes, uint flags);

    [DllImport("user32.dll")]
    public static extern int DisplayConfigGetDeviceInfo(ref DISPLAYCONFIG_SOURCE_DPI_SCALE_GET requestPacket);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int DisplayConfigGetDeviceInfo(ref DISPLAYCONFIG_SOURCE_DEVICE_NAME requestPacket);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int DisplayConfigGetDeviceInfo(ref DISPLAYCONFIG_TARGET_DEVICE_NAME requestPacket);

    [DllImport("user32.dll")]
    public static extern int DisplayConfigSetDeviceInfo(ref DISPLAYCONFIG_SOURCE_DPI_SCALE_SET setPacket);
}
"@
    } catch {
        Write-Warning "DisplayApi 编译失败: $($_.Exception.Message)。将使用基础显示器枚举；模式切换和 DPI 功能不可用。"
    }
}

# === 必须在任何其他操作之前声明 Per-Monitor DPI Awareness ===
# PowerShell 默认非 DPI-aware，DisplayConfigGetDeviceInfo/SetDeviceInfo 需要此设置
# 必须在 System.Windows.Forms 加载之前调用，否则 WinForms 初始化会崩溃
try {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class DpiAwareness {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("shcore.dll")]
    public static extern int SetProcessDpiAwareness(int value);
    [DllImport("user32.dll")]
    public static extern uint GetDpiForSystem();
    public static readonly IntPtr PER_MONITOR_AWARE_V2 = new IntPtr(-4);
    public static readonly IntPtr PER_MONITOR_AWARE = new IntPtr(-3);
}
"@
} catch {
    Write-Warning "DpiAwareness 编译失败: $($_.Exception.Message)。DPI 功能不可用。"
}
if (([System.Management.Automation.PSTypeName]'DpiAwareness').Type) {
    if (-not [DpiAwareness]::SetProcessDpiAwarenessContext([DpiAwareness]::PER_MONITOR_AWARE_V2)) {
        if (-not [DpiAwareness]::SetProcessDpiAwarenessContext([DpiAwareness]::PER_MONITOR_AWARE)) {
            [void][DpiAwareness]::SetProcessDpiAwareness(2)
        }
    }
}

# 批量替换 WinForms 控件时临时冻结绘制，避免清空与重建之间闪出空白背景。
if (-not ([System.Management.Automation.PSTypeName]'RedrawApi').Type) {
    try {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class RedrawApi {
    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
}
"@
    } catch {
        Write-Warning "RedrawApi 编译失败: $($_.Exception.Message)。界面仍可使用，但批量刷新时可能出现轻微闪烁。"
    }
}

# 预加载 System.Windows.Forms（必须在 DPI awareness 设置之后）
Add-Type -AssemblyName System.Windows.Forms

# ============================================================
#  常量
# ============================================================
$ENUM_CURRENT_SETTINGS  = -1
$CDS_UPDATEREGISTRY     = 0x00000001
$CDS_TEST               = 0x00000002
$CDS_NORESET            = 0x10000000
$DM_BITSPERPEL          = 0x00040000
$DM_PELSWIDTH           = 0x00080000
$DM_PELSHEIGHT          = 0x00100000
$DM_DISPLAYFREQUENCY    = 0x00400000

$QDC_ALL_PATHS          = 0x00000001
$QDC_ONLY_ACTIVE_PATHS  = 0x00000002
$ERROR_INSUFFICIENT_BUFFER = 122
$DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME = 1
$DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME = 2
$DISPLAYCONFIG_MODE_INFO_TYPE_SOURCE = 1
$DISPLAYCONFIG_PATH_ACTIVE = 0x00000001
$DISPLAYCONFIG_PATH_MODE_IDX_INVALID = [uint32]::MaxValue
$DISPLAY_DEVICE_ACTIVE = 0x00000001

$SDC_TOPOLOGY_SUPPLIED            = 0x00000010
$SDC_USE_SUPPLIED_DISPLAY_CONFIG  = 0x00000020
$SDC_VALIDATE                     = 0x00000040
$SDC_APPLY                        = 0x00000080
$SDC_SAVE_TO_DATABASE             = 0x00000200
$SDC_ALLOW_CHANGES                = 0x00000400
$SDC_ALLOW_PATH_ORDER_CHANGES     = 0x00002000

# 逆向 API 的 type 值（负数，未公开）
$DPI_TYPE_GET = -3
$DPI_TYPE_SET = -4

# 标准缩放档位（系统内部完整档位表，用于计算相对偏移）
# 用户选择限制在 $UserDpiScaleTable 的 5 档内（100/125/150/175/200）
$DpiScaleTable = @(100, 125, 150, 175, 200, 225, 250, 300, 350, 400, 450, 500)
# 用户可选择的 5 档（符合"无自定义缩放"原则）
$UserDpiScaleTable = @(100, 125, 150, 175, 200)
# 缩放百分比 → DPI 像素值（兼容旧式 LogPixels 注册表语义，仅用于显示参考）
$DpiScaleToPixels = @{
    100 = 96
    125 = 120
    150 = 144
    175 = 168
    200 = 192
}

$TemplateDir  = Join-Path $env:USERPROFILE ".monitormanager"
$TemplateFile = Join-Path $TemplateDir "templates.json"
$MonitorNamesFile = Join-Path $TemplateDir "monitor_names.json"

# 多实例会同时读写模板并可能同时提交显示模式。使用当前用户范围的命名互斥锁，
# 将“读取→修改→保存”和显示器配置提交分别串行化。
try { $CurrentUserSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value } catch { $CurrentUserSid = $env:USERNAME }
$DataMutexName = "Local\MonitorManager.Data.$CurrentUserSid"
$DisplayMutexName = "Local\MonitorManager.Display.$CurrentUserSid"

function Invoke-WithNamedMutex {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [int]$TimeoutMs = 15000
    )

    $mutex = $null
    $acquired = $false
    try {
        $mutex = New-Object System.Threading.Mutex($false, $Name)
        try {
            $acquired = $mutex.WaitOne($TimeoutMs)
        } catch [System.Threading.AbandonedMutexException] {
            # 前一个进程异常退出；此时当前线程已经取得互斥锁。
            $acquired = $true
        }
        if (-not $acquired) { throw "等待其他实例完成操作超时，请稍后重试" }
        return (& $Action)
    } finally {
        if ($acquired -and $mutex) {
            try { $mutex.ReleaseMutex() } catch {}
        }
        if ($mutex) { $mutex.Dispose() }
    }
}

function Set-ControlRedraw {
    param($Control, [bool]$Enabled)
    if (-not $Control -or $Control.IsDisposed -or -not ([System.Management.Automation.PSTypeName]'RedrawApi').Type) { return }
    try {
        $wParam = if ($Enabled) { [IntPtr]1 } else { [IntPtr]0 }
        [void][RedrawApi]::SendMessage($Control.Handle, 0x000B, $wParam, [IntPtr]::Zero) # WM_SETREDRAW
    } catch {}
}

function Load-MonitorNames {
    param([switch]$ForWrite)
    if (Test-Path $MonitorNamesFile) {
        try {
            $data = Get-Content $MonitorNamesFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -eq $data -or -not ($data -is [PSCustomObject])) {
                throw '显示器名称文件的根节点必须是 JSON 对象'
            }
            return $data
        } catch {
            # 读取用途可降级为空对象；写入用途必须中止，避免用空数据覆盖损坏文件。
            $timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss-fff')
            $backupPath = "$MonitorNamesFile.corrupted.$timestamp.bak"
            $backupSucceeded = $false
            try {
                Copy-Item $MonitorNamesFile $backupPath -Force -ErrorAction Stop
                $backupSucceeded = Test-Path $backupPath
            } catch {
                Write-Warning "显示器名称文件已损坏，且备份失败: $($_.Exception.Message)"
            }
            if ($backupSucceeded) {
                Write-Warning "显示器名称文件已损坏，已备份至: $backupPath"
            }
            if ($ForWrite) {
                $backupInfo = if ($backupSucceeded) { "备份: $backupPath" } else { '备份未成功' }
                throw "显示器名称文件损坏，已阻止写入（$backupInfo）"
            }
        }
    }
    return [PSCustomObject]@{}
}

function Save-MonitorNames {
    param($Names)
    $tmpFile = $null
    try {
        if (-not (Test-Path $TemplateDir)) {
            New-Item -Path $TemplateDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        # 同目录唯一临时文件 + rename，兼顾原子替换和多实例写入
        $tmpFile = Join-Path $TemplateDir ("monitor_names.{0}.{1}.tmp" -f $PID, [Guid]::NewGuid().ToString('N'))
        $Names | ConvertTo-Json -Depth 3 | Set-Content $tmpFile -Encoding UTF8 -ErrorAction Stop
        Move-Item $tmpFile $MonitorNamesFile -Force -ErrorAction Stop
        return $true
    } catch {
        Write-Warning "保存显示器名称失败: $($_.Exception.Message)"
        if ($tmpFile -and (Test-Path $tmpFile)) { Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue }
        return $false
    }
}

function Get-MonitorCustomName {
    param([string]$MonitorId)
    if (-not $MonitorId) { return $null }
    $names = Load-MonitorNames
    if ($null -ne $names.PSObject.Properties[$MonitorId]) {
        return $names.$MonitorId
    }
    return $null
}

function Set-MonitorCustomName {
    param([string]$MonitorId, [string]$CustomName)
    if ([string]::IsNullOrWhiteSpace($MonitorId)) {
        return @{ success = $false; error = "显示器缺少 MonitorId，无法保存自定义名称" }
    }
    $CustomName = ([string]$CustomName).Trim()
    if ($CustomName.Length -gt 100 -or $CustomName -match '[\r\n\t]') {
        return @{ success = $false; error = "显示器名称不能超过 100 个字符，也不能包含换行或制表符" }
    }
    try {
        return Invoke-WithNamedMutex -Name $DataMutexName -Action {
            $names = Load-MonitorNames -ForWrite
            if ([string]::IsNullOrWhiteSpace($CustomName)) {
                if ($null -ne $names.PSObject.Properties[$MonitorId]) {
                    $names.PSObject.Properties.Remove($MonitorId)
                }
            } else {
                if ($null -ne $names.PSObject.Properties[$MonitorId]) {
                    $names.$MonitorId = $CustomName
                } else {
                    $names | Add-Member -MemberType NoteProperty -Name $MonitorId -Value $CustomName
                }
            }
            if (-not (Save-MonitorNames $names)) {
                return @{ success = $false; error = "显示器名称未能写入 $MonitorNamesFile" }
            }
            return @{ success = $true }
        }
    } catch {
        return @{ success = $false; error = "保存显示器名称失败: $($_.Exception.Message)" }
    }
}

# ============================================================
#  辅助函数
# ============================================================

function Apply-MonitorCustomNames {
    param($Monitors)
    $customNames = Load-MonitorNames
    foreach ($m in @($Monitors)) {
        if ($m.MonitorId -and $null -ne $customNames.PSObject.Properties[$m.MonitorId]) {
            $m.MonitorName = $customNames.$($m.MonitorId)
        }
    }
}

# 使用 adapterId/sourceId 获取同一 DisplayConfig source 的 GDI 名称。
# 不依赖 QueryDisplayConfig 与 EnumDisplayDevices 的枚举顺序。
function Get-GdiDeviceName {
    param($AdapterId, [uint32]$SourceId)

    $request = New-Object DISPLAYCONFIG_SOURCE_DEVICE_NAME
    $header = $request.header
    $header.type      = $DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME
    $header.size      = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf([Type][DISPLAYCONFIG_SOURCE_DEVICE_NAME])
    $header.adapterId = $AdapterId
    $header.id        = $SourceId
    $request.header   = $header

    $ret = [DisplayApi]::DisplayConfigGetDeviceInfo([ref]$request)
    if ($ret -eq 0 -and -not [string]::IsNullOrWhiteSpace($request.viewGdiDeviceName)) {
        return $request.viewGdiDeviceName
    }
    return $null
}

# 使用 target adapter/id 获取物理显示器身份。source/GDI 名称描述桌面输出，
# target 才对应真实的显示器；两者在复制拓扑或多接口切换时不能混用。
function Get-DisplayTargetDeviceInfo {
    param($AdapterId, [uint32]$TargetId)

    $request = New-Object DISPLAYCONFIG_TARGET_DEVICE_NAME
    $header = $request.header
    $header.type      = $DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME
    $header.size      = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf([Type][DISPLAYCONFIG_TARGET_DEVICE_NAME])
    $header.adapterId = $AdapterId
    $header.id        = $TargetId
    $request.header   = $header

    $ret = [DisplayApi]::DisplayConfigGetDeviceInfo([ref]$request)
    if ($ret -ne 0) { return $null }
    return [PSCustomObject]@{
        FriendlyName = [string]$request.monitorFriendlyDeviceName
        DevicePath   = [string]$request.monitorDevicePath
        TargetId     = $TargetId
    }
}

function Get-DisplayTargetKey {
    param($AdapterId, [uint32]$TargetId)
    if (-not $AdapterId) { return "unknown:$TargetId" }
    return "$([int]$AdapterId.HighPart):$([uint32]$AdapterId.LowPart):$TargetId"
}

# EnumDisplayDevices(gdi, 0) 在一张显卡挂有多个屏幕时经常返回第一个已连接设备，
# 并不一定是该 GDI source 当前使用的物理显示器。优先用 target PnP 路径中的硬件码匹配。
function Get-MonitorDeviceForTarget {
    param([string]$GdiName, [string]$TargetDevicePath)
    if ([string]::IsNullOrWhiteSpace($GdiName)) { return $null }

    $targetHardwareCode = $null
    if ($TargetDevicePath -match '(?i)^\\\\\?\\DISPLAY#([^#]+)#') {
        $targetHardwareCode = [string]$Matches[1]
    }

    $firstDevice = $null
    $activeDevice = $null
    for ($index = 0; $index -lt 32; $index++) {
        $device = New-Object DISPLAY_DEVICE
        $device.cb = [System.Runtime.InteropServices.Marshal]::SizeOf([Type][DISPLAY_DEVICE])
        if (-not [DisplayApi]::EnumDisplayDevices($GdiName, [uint32]$index, [ref]$device, 0)) { break }
        if (-not $firstDevice) { $firstDevice = $device }
        if (-not $activeDevice -and (($device.StateFlags -band $DISPLAY_DEVICE_ACTIVE) -ne 0)) {
            $activeDevice = $device
        }
        if ($targetHardwareCode) {
            $idParts = @([string]$device.DeviceID -split '\\')
            if ($idParts.Count -ge 2 -and $idParts[1] -eq $targetHardwareCode) {
                return $device
            }
        }
    }

    if ($activeDevice) { return $activeDevice }
    return $firstDevice
}

function Test-MonitorIsActive {
    param($Monitor)
    if (-not $Monitor) { return $false }
    if ($null -ne $Monitor.PSObject.Properties['IsActive']) { return [bool]$Monitor.IsActive }
    return [bool]$Monitor.IsConnected
}

function Get-MonitorTargetKey {
    param($Monitor)
    if (-not $Monitor) { return $null }
    $targetAdapter = if ($null -ne $Monitor.PSObject.Properties['TargetAdapterId'] -and $Monitor.TargetAdapterId) {
        $Monitor.TargetAdapterId
    } else {
        $Monitor.AdapterId
    }
    return Get-DisplayTargetKey -AdapterId $targetAdapter -TargetId ([uint32]$Monitor.TargetId)
}

function Resolve-MonitorByTargetIdentity {
    param($Monitors, [string]$MonitorId, [string]$TargetKey)
    if ($TargetKey) {
        $target = $Monitors | Where-Object { (Get-MonitorTargetKey $_) -eq $TargetKey } | Select-Object -First 1
        if ($target) { return $target }
    }
    if ($MonitorId) {
        return $Monitors | Where-Object { $_.MonitorId -eq $MonitorId } | Select-Object -First 1
    }
    return $null
}

function Get-DisplayPathTargetKey {
    param($Path)
    return Get-DisplayTargetKey -AdapterId $Path.targetInfo.adapterId -TargetId ([uint32]$Path.targetInfo.id)
}

function Get-DisplayPathSourceKey {
    param($Path)
    $adapter = $Path.sourceInfo.adapterId
    return "$([int]$adapter.HighPart):$([uint32]$adapter.LowPart):$([uint32]$Path.sourceInfo.id)"
}

function Test-DisplayPathAtDesktopOrigin {
    param($Path, $Modes)
    if (-not $Path) { return $false }
    $modeIndex = [uint32]$Path.sourceInfo.modeInfoIdx
    $modeItems = @($Modes)
    if ($modeIndex -eq $DISPLAYCONFIG_PATH_MODE_IDX_INVALID -or $modeIndex -ge $modeItems.Count) { return $false }
    $mode = $modeItems[$modeIndex]
    if ([uint32]$mode.infoType -ne $DISPLAYCONFIG_MODE_INFO_TYPE_SOURCE -or
        [uint32]$mode.id -ne [uint32]$Path.sourceInfo.id) { return $false }
    $pathAdapter = $Path.sourceInfo.adapterId
    $modeAdapter = $mode.adapterId
    if ([int]$pathAdapter.HighPart -ne [int]$modeAdapter.HighPart -or
        [uint32]$pathAdapter.LowPart -ne [uint32]$modeAdapter.LowPart) { return $false }
    $sourceMode = $mode.modeInfo.sourceMode
    return ([int]$sourceMode.position.x -eq 0 -and [int]$sourceMode.position.y -eq 0)
}

# 返回与同一次 QueryDisplayConfig 调用配套的 path/mode 数组；modeInfoIdx 只能与该 modes 数组一起使用。
function Get-DisplayConfigTopology {
    param([uint32]$Flags = $QDC_ONLY_ACTIVE_PATHS)
    if (-not ([System.Management.Automation.PSTypeName]'DisplayApi').Type) {
        return @{ success = $false; code = -1; error = '系统显示 API 不可用' }
    }

    $ret = $ERROR_INSUFFICIENT_BUFFER
    for ($attempt = 0; $attempt -lt 4; $attempt++) {
        $pathCount = [uint32]0
        $modeCount = [uint32]0
        $sizeRet = [DisplayApi]::GetDisplayConfigBufferSizes($Flags, [ref]$pathCount, [ref]$modeCount)
        if ($sizeRet -ne 0) { return @{ success = $false; code = $sizeRet; error = "读取显示拓扑大小失败 (code=$sizeRet)" } }

        $paths = New-Object 'DISPLAYCONFIG_PATH_INFO[]' $pathCount
        $modes = New-Object 'DISPLAYCONFIG_MODE_INFO[]' $modeCount
        $ret = [DisplayApi]::QueryDisplayConfig($Flags, [ref]$pathCount, $paths, [ref]$modeCount, $modes, [IntPtr]::Zero)
        if ($ret -eq 0) {
            $validPaths = New-Object 'DISPLAYCONFIG_PATH_INFO[]' $pathCount
            for ($i = 0; $i -lt $pathCount; $i++) { $validPaths[$i] = $paths[$i] }
            $validModes = New-Object 'DISPLAYCONFIG_MODE_INFO[]' $modeCount
            for ($i = 0; $i -lt $modeCount; $i++) { $validModes[$i] = $modes[$i] }
            return @{ success = $true; code = 0; paths = $validPaths; modes = $validModes }
        }
        if ($ret -ne $ERROR_INSUFFICIENT_BUFFER) { break }
    }
    return @{ success = $false; code = $ret; error = "读取显示拓扑失败 (code=$ret)" }
}

function ConvertTo-PathOnlyTopology {
    param($Paths)
    $sourcePaths = @($Paths)
    $result = New-Object 'DISPLAYCONFIG_PATH_INFO[]' $sourcePaths.Count
    for ($i = 0; $i -lt $sourcePaths.Count; $i++) {
        $path = $sourcePaths[$i]
        $source = $path.sourceInfo
        $source.modeInfoIdx = $DISPLAYCONFIG_PATH_MODE_IDX_INVALID
        $path.sourceInfo = $source
        $target = $path.targetInfo
        $target.modeInfoIdx = $DISPLAYCONFIG_PATH_MODE_IDX_INVALID
        $path.targetInfo = $target
        $path.flags = [uint32]($path.flags -bor $DISPLAYCONFIG_PATH_ACTIVE)
        $result[$i] = $path
    }
    return ,$result
}

# 单独封装原生写调用，safe_tests.ps1 会替换此函数，绝不触碰真实显示器。
function Invoke-NativeSetDisplayConfig {
    param($Paths, $Modes, [uint32]$Flags)
    $pathItems = @($Paths)
    $modeItems = @($Modes)
    $pathArray = if ($pathItems.Count -gt 0) { [DISPLAYCONFIG_PATH_INFO[]]$pathItems } else { $null }
    $modeArray = if ($modeItems.Count -gt 0) { [DISPLAYCONFIG_MODE_INFO[]]$modeItems } else { $null }
    return [DisplayApi]::SetDisplayConfig([uint32]$pathItems.Count, $pathArray, [uint32]$modeItems.Count, $modeArray, $Flags)
}

function Restore-DisplayTopology {
    param($Snapshot)
    if (-not $Snapshot -or -not $Snapshot.success) { return @{ success = $false; code = -1; message = '缺少可用的原始拓扑快照' } }
    $flags = [uint32]($SDC_APPLY -bor $SDC_USE_SUPPLIED_DISPLAY_CONFIG -bor $SDC_SAVE_TO_DATABASE -bor $SDC_ALLOW_CHANGES)
    $code = Invoke-NativeSetDisplayConfig -Paths $Snapshot.paths -Modes $Snapshot.modes -Flags $flags
    return @{ success = ($code -eq 0); code = $code; message = if ($code -eq 0) { '原始显示拓扑已恢复' } else { "恢复原始显示拓扑失败 (code=$code)" } }
}

# 优先从 Windows 持久化数据库恢复该 path 组合；没有历史组合时再让 best-mode 生成并保存。
function Set-PathOnlyDisplayTopology {
    param($Paths)
    $pathOnly = ConvertTo-PathOnlyTopology -Paths $Paths

    $databaseValidateFlags = [uint32]($SDC_VALIDATE -bor $SDC_TOPOLOGY_SUPPLIED -bor $SDC_ALLOW_PATH_ORDER_CHANGES)
    $databaseValidate = Invoke-NativeSetDisplayConfig -Paths $pathOnly -Modes @() -Flags $databaseValidateFlags
    if ($databaseValidate -eq 0) {
        $databaseApplyFlags = [uint32]($SDC_APPLY -bor $SDC_TOPOLOGY_SUPPLIED -bor $SDC_ALLOW_PATH_ORDER_CHANGES)
        $databaseApply = Invoke-NativeSetDisplayConfig -Paths $pathOnly -Modes @() -Flags $databaseApplyFlags
        return @{ success = ($databaseApply -eq 0); code = $databaseApply; method = 'database'; validated = $true }
    }

    $bestValidateFlags = [uint32]($SDC_VALIDATE -bor $SDC_USE_SUPPLIED_DISPLAY_CONFIG -bor $SDC_ALLOW_CHANGES)
    $bestValidate = Invoke-NativeSetDisplayConfig -Paths $pathOnly -Modes @() -Flags $bestValidateFlags
    if ($bestValidate -ne 0) {
        return @{ success = $false; code = $bestValidate; method = 'best-mode'; validated = $false; databaseCode = $databaseValidate }
    }

    $bestApplyFlags = [uint32]($SDC_APPLY -bor $SDC_USE_SUPPLIED_DISPLAY_CONFIG -bor $SDC_SAVE_TO_DATABASE -bor $SDC_ALLOW_CHANGES)
    $bestApply = Invoke-NativeSetDisplayConfig -Paths $pathOnly -Modes @() -Flags $bestApplyFlags
    return @{ success = ($bestApply -eq 0); code = $bestApply; method = 'best-mode'; validated = $true; databaseCode = $databaseValidate }
}

function Get-MonitorsFallback {
    $monitors = @()
    $nativeAvailable = [bool]([System.Management.Automation.PSTypeName]'DisplayApi').Type
    $screens = [System.Windows.Forms.Screen]::AllScreens
    foreach ($screen in $screens) {
        $displayName = $screen.DeviceName
        # Screen 是完全托管的保底路径，即使本机无法编译 Win32 类型也能启动 GUI/列出屏幕。
        $monitorName = $displayName
        $monitorId = $displayName
        $width = [int]$screen.Bounds.Width
        $height = [int]$screen.Bounds.Height
        $refresh = 0
        $bpp = [int]$screen.BitsPerPixel
        $adapterId = $null

        if ($nativeAvailable) {
            $md = Get-MonitorDeviceForTarget -GdiName $displayName -TargetDevicePath $null
            if ($md) {
                if ($md.DeviceString) { $monitorName = $md.DeviceString }
                if ($md.DeviceID) { $monitorId = $md.DeviceID }
            }

            $dm = New-Object DEVMODE
            $dm.dmSize = [System.Runtime.InteropServices.Marshal]::SizeOf([Type][DEVMODE])
            if ([DisplayApi]::EnumDisplaySettingsEx($displayName, $ENUM_CURRENT_SETTINGS, [ref]$dm, 0)) {
                $width = $dm.dmPelsWidth; $height = $dm.dmPelsHeight
                $refresh = $dm.dmDisplayFrequency; $bpp = $dm.dmBitsPerPel
            }
            $adapterId = New-Object LUID
        }

        $monitors += [PSCustomObject]@{
            DisplayName = $displayName
            MonitorName = $monitorName
            MonitorId   = $monitorId
            Width       = $width
            Height      = $height
            RefreshRate = $refresh
            BitsPerPel  = $bpp
            DpiScale    = 0
            AdapterId   = $adapterId
            TargetAdapterId = $adapterId
            SourceId    = [uint32]0
            TargetId    = [uint32]0
            IsPrimary   = $screen.Primary
            IsConnected = $true
            IsActive    = $true
        }
    }
    Apply-MonitorCustomNames $monitors
    return ,$monitors
}

function Get-Monitors {
    Add-Type -AssemblyName System.Windows.Forms
    $monitors = @()

    if (-not ([System.Management.Automation.PSTypeName]'DisplayApi').Type) {
        $fallback = @(Get-MonitorsFallback)
        return ,$fallback
    }

    # 通过 QueryDisplayConfig 获取每条活动路径（含 adapterId / sourceId，用于 DPI 设置）
    $ret = $ERROR_INSUFFICIENT_BUFFER
    $paths = $null
    $modes = $null
    for ($attempt = 0; $attempt -lt 4; $attempt++) {
        $pathCount = [uint32]0
        $modeCount = [uint32]0
        $sizeRet = [DisplayApi]::GetDisplayConfigBufferSizes($QDC_ONLY_ACTIVE_PATHS, [ref]$pathCount, [ref]$modeCount)
        if ($sizeRet -ne 0 -or $pathCount -eq 0) { $ret = $sizeRet; break }

        $paths = New-Object 'DISPLAYCONFIG_PATH_INFO[]' $pathCount
        $modes = New-Object 'DISPLAYCONFIG_MODE_INFO[]' $modeCount
        $ret = [DisplayApi]::QueryDisplayConfig($QDC_ONLY_ACTIVE_PATHS, [ref]$pathCount, $paths, [ref]$modeCount, $modes, [IntPtr]::Zero)
        if ($ret -eq 0) { break }
        if ($ret -ne $ERROR_INSUFFICIENT_BUFFER) { break }
        # 拓扑在两次调用之间发生变化；重新取大小并重试。
    }
    if ($ret -ne 0 -or -not $paths) {
        $fallback = @(Get-MonitorsFallback)
        return ,$fallback
    }

    # 用 Screen.AllScreens 取主显示器标记
    $screens = [System.Windows.Forms.Screen]::AllScreens
    $nameToPrimary = @{}
    foreach ($s in $screens) { $nameToPrimary[$s.DeviceName] = $s.Primary }

    $activeTargetKeys = @{}
    $seenMonitorIds = @{}
    # 遍历每条活动 path。GDI/source 用于读写模式，target 用于识别物理显示器。
    for ($pathIdx = 0; $pathIdx -lt $pathCount; $pathIdx++) {
        $path = $paths[$pathIdx]
        $adapterId = $path.sourceInfo.adapterId
        $sourceId  = $path.sourceInfo.id
        $targetAdapterId = $path.targetInfo.adapterId
        $targetId = [uint32]$path.targetInfo.id
        $targetKey = Get-DisplayTargetKey -AdapterId $targetAdapterId -TargetId $targetId
        if ($activeTargetKeys.ContainsKey($targetKey)) { continue }
        $activeTargetKeys[$targetKey] = $true

        $gdiName = Get-GdiDeviceName -AdapterId $adapterId -SourceId $sourceId
        if (-not $gdiName) {
            # 单条 path 无法精确关联时整组降级，避免把 DPI 设置到错误显示器
            $fallback = @(Get-MonitorsFallback)
            return ,$fallback
        }

        $targetInfo = Get-DisplayTargetDeviceInfo -AdapterId $targetAdapterId -TargetId $targetId
        $targetDevicePath = if ($targetInfo) { [string]$targetInfo.DevicePath } else { '' }
        $md = Get-MonitorDeviceForTarget -GdiName $gdiName -TargetDevicePath $targetDevicePath
        $monitorName = if ($targetInfo -and $targetInfo.FriendlyName) { [string]$targetInfo.FriendlyName } elseif ($md) { [string]$md.DeviceString } else { $gdiName }
        $monitorId = if ($md -and $md.DeviceID) { [string]$md.DeviceID } elseif ($targetDevicePath) { $targetDevicePath } else { "DISPLAYCONFIG\$targetKey" }
        if ($seenMonitorIds.ContainsKey($monitorId)) { continue }
        $seenMonitorIds[$monitorId] = $true

        # 分辨率/刷新率/色深
        $dm = New-Object DEVMODE
        $dm.dmSize = [System.Runtime.InteropServices.Marshal]::SizeOf([Type][DEVMODE])
        $width = 0; $height = 0; $refresh = 0; $bpp = 0
        if ([DisplayApi]::EnumDisplaySettingsEx($gdiName, $ENUM_CURRENT_SETTINGS, [ref]$dm, 0)) {
            $width = $dm.dmPelsWidth; $height = $dm.dmPelsHeight
            $refresh = $dm.dmDisplayFrequency; $bpp = $dm.dmBitsPerPel
        }

        # 当前 DPI 缩放
        $dpiScale = Get-DpiScale $adapterId $sourceId

        $isPrimary = $false
        if ($nameToPrimary.ContainsKey($gdiName)) { $isPrimary = $nameToPrimary[$gdiName] }
        if (-not $isPrimary -and (Test-DisplayPathAtDesktopOrigin -Path $path -Modes $modes)) {
            # Screen.AllScreens 在主屏断开后的当前进程中可能仍是旧缓存；DisplayConfig
            # source mode 的桌面原点是更及时、也更底层的主屏依据。
            $isPrimary = $true
        }

        $monitors += [PSCustomObject]@{
            DisplayName  = $gdiName
            MonitorName  = $monitorName
            MonitorId    = $monitorId
            Width        = $width
            Height       = $height
            RefreshRate  = $refresh
            BitsPerPel   = $bpp
            DpiScale     = $dpiScale
            AdapterId    = $adapterId
            TargetAdapterId = $targetAdapterId
            SourceId     = $sourceId
            TargetId     = $targetId
            IsPrimary    = $isPrimary
            IsConnected  = $true
            IsActive     = $true
        }
    }

    # QDC_ONLY_ACTIVE_PATHS 不包含“线缆已连接但未加入桌面”的设备。再读取全部路径，
    # 只追加 targetAvailable 且不在活动集合中的唯一物理目标，供用户查看和管理已有模板。
    $allRet = $ERROR_INSUFFICIENT_BUFFER
    $allPaths = $null
    for ($attempt = 0; $attempt -lt 4; $attempt++) {
        $allPathCount = [uint32]0
        $allModeCount = [uint32]0
        $allSizeRet = [DisplayApi]::GetDisplayConfigBufferSizes($QDC_ALL_PATHS, [ref]$allPathCount, [ref]$allModeCount)
        if ($allSizeRet -ne 0 -or $allPathCount -eq 0) { $allRet = $allSizeRet; break }
        $allPaths = New-Object 'DISPLAYCONFIG_PATH_INFO[]' $allPathCount
        $allModes = New-Object 'DISPLAYCONFIG_MODE_INFO[]' $allModeCount
        $allRet = [DisplayApi]::QueryDisplayConfig($QDC_ALL_PATHS, [ref]$allPathCount, $allPaths, [ref]$allModeCount, $allModes, [IntPtr]::Zero)
        if ($allRet -eq 0) { break }
        if ($allRet -ne $ERROR_INSUFFICIENT_BUFFER) { break }
    }

    if ($allRet -eq 0 -and $allPaths) {
        $seenAvailableTargets = @{}
        for ($pathIdx = 0; $pathIdx -lt $allPathCount; $pathIdx++) {
            $path = $allPaths[$pathIdx]
            if (-not $path.targetInfo.targetAvailable) { continue }
            $targetAdapterId = $path.targetInfo.adapterId
            $targetId = [uint32]$path.targetInfo.id
            $targetKey = Get-DisplayTargetKey -AdapterId $targetAdapterId -TargetId $targetId
            if ($activeTargetKeys.ContainsKey($targetKey) -or $seenAvailableTargets.ContainsKey($targetKey)) { continue }
            $seenAvailableTargets[$targetKey] = $true

            $targetInfo = Get-DisplayTargetDeviceInfo -AdapterId $targetAdapterId -TargetId $targetId
            if (-not $targetInfo) { continue }
            $possibleGdiName = Get-GdiDeviceName -AdapterId $path.sourceInfo.adapterId -SourceId $path.sourceInfo.id
            $md = Get-MonitorDeviceForTarget -GdiName $possibleGdiName -TargetDevicePath ([string]$targetInfo.DevicePath)
            $monitorName = if ($targetInfo.FriendlyName) { [string]$targetInfo.FriendlyName } elseif ($md) { [string]$md.DeviceString } else { "显示器 $targetId" }
            $monitorId = if ($md -and $md.DeviceID) { [string]$md.DeviceID } elseif ($targetInfo.DevicePath) { [string]$targetInfo.DevicePath } else { "DISPLAYCONFIG\$targetKey" }
            if ($seenMonitorIds.ContainsKey($monitorId)) { continue }
            $seenMonitorIds[$monitorId] = $true

            $monitors += [PSCustomObject]@{
                DisplayName  = '已断开'
                MonitorName  = $monitorName
                MonitorId    = $monitorId
                Width        = 0
                Height       = 0
                RefreshRate  = 0
                BitsPerPel   = 0
                DpiScale     = 0
                AdapterId    = $null
                TargetAdapterId = $targetAdapterId
                SourceId     = [uint32]0
                TargetId     = $targetId
                IsPrimary    = $false
                IsConnected  = $true
                IsActive     = $false
            }
        }
    }
    Apply-MonitorCustomNames $monitors

    # 注意：PowerShell 的 return 会把单元素数组解开成单个对象，导致 .Count 失效
    # 用 ,(数组) 强制返回数组本身
    return ,$monitors
}

# 获取单台显示器当前 DPI 缩放百分比（如 100/125/150/175/200），失败返回 0
function Get-DpiScale {
    param($AdapterId, $SourceId)

    $get = New-Object DISPLAYCONFIG_SOURCE_DPI_SCALE_GET
    # PowerShell 不能直接修改嵌套 struct 字段（值类型副本问题），必须先取局部变量再整体赋值
    $h = $get.header
    $h.type      = $DPI_TYPE_GET
    $h.size      = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf([Type][DISPLAYCONFIG_SOURCE_DPI_SCALE_GET])
    $h.adapterId = $AdapterId
    $h.id        = $SourceId
    $get.header  = $h

    $ret = [DisplayApi]::DisplayConfigGetDeviceInfo([ref]$get)
    if ($ret -ne 0) { return 0 }

    # 相对 recommended 的偏移 → 绝对档位索引
    # minScaleRel 是负数（向下多少档），curScaleRel 是相对 recommended 的偏移
    # 推荐档位索引 = |minScaleRel|；当前档位索引 = |minScaleRel| + curScaleRel
    $recIdx = [Math]::Abs($get.minScaleRel)
    $curIdx = $recIdx + $get.curScaleRel

    if ($curIdx -ge 0 -and $curIdx -lt $DpiScaleTable.Count) {
        return [int]$DpiScaleTable[$curIdx]
    }
    return 0
}

# 设置单台显示器 DPI 缩放百分比（接受系统标准档位；交互界面仍只展示常用 5 档）
# 返回 hashtable: @{ success=$true/false; code=$ret; message='...' }
function Set-DpiScale {
    param($AdapterId, $SourceId, [int]$TargetScale)

    if ($DpiScaleTable -notcontains $TargetScale) {
        return @{ success = $false; code = -1; message = "不支持的缩放值 $TargetScale%，仅支持系统标准档位: $($DpiScaleTable -join '/')" }
    }

    $get = New-Object DISPLAYCONFIG_SOURCE_DPI_SCALE_GET
    $hg = $get.header
    $hg.type      = $DPI_TYPE_GET
    $hg.size      = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf([Type][DISPLAYCONFIG_SOURCE_DPI_SCALE_GET])
    $hg.adapterId = $AdapterId
    $hg.id        = $SourceId
    $get.header   = $hg

    $ret = [DisplayApi]::DisplayConfigGetDeviceInfo([ref]$get)
    if ($ret -ne 0) {
        return @{ success = $false; code = $ret; message = "获取当前 DPI 失败 (code=$ret)" }
    }

    $recIdx = [Math]::Abs($get.minScaleRel)
    $targetIdx = [Array]::IndexOf($DpiScaleTable, $TargetScale)
    if ($targetIdx -lt 0) {
        return @{ success = $false; code = -1; message = "目标档位 $TargetScale% 不在档位表内" }
    }

    $scaleRel = $targetIdx - $recIdx

    $set = New-Object DISPLAYCONFIG_SOURCE_DPI_SCALE_SET
    $hs = $set.header
    $hs.type      = $DPI_TYPE_SET
    $hs.size      = [uint32][System.Runtime.InteropServices.Marshal]::SizeOf([Type][DISPLAYCONFIG_SOURCE_DPI_SCALE_SET])
    $hs.adapterId = $AdapterId
    $hs.id        = $SourceId
    $set.header   = $hs
    $set.scaleRel = $scaleRel

    $ret = [DisplayApi]::DisplayConfigSetDeviceInfo([ref]$set)
    if ($ret -eq 0) {
        return @{ success = $true; code = 0; message = "OK" }
    }
    return @{ success = $false; code = $ret; message = "DisplayConfigSetDeviceInfo 失败 (code=$ret)" }
}

# 独立 DPI 命令使用：在显示锁内重新定位目标，设置后回读验证，失败时恢复原缩放。
function Set-DpiScaleVerified {
    param([string]$MonitorSpec, [int]$TargetScale)

    if ([string]::IsNullOrWhiteSpace($MonitorSpec)) {
        return @{ success = $false; message = '缺少显示器标识' }
    }
    if ($UserDpiScaleTable -notcontains $TargetScale) {
        return @{ success = $false; message = "不支持的缩放值 $TargetScale%" }
    }

    try {
        return Invoke-WithNamedMutex -Name $DisplayMutexName -TimeoutMs 30000 -Action {
            $latestMonitors = Get-Monitors
            $latestTarget = Resolve-Monitor -Spec $MonitorSpec -Monitors $latestMonitors
            if (-not $latestTarget) {
                return @{ success = $false; message = "显示器 '$MonitorSpec' 已断开或无法重新定位" }
            }
            if (-not (Test-AdapterIdAvailable $latestTarget.AdapterId)) {
                return @{ success = $false; message = '无法获取显示器 AdapterId，已取消设置' }
            }

            $originalDpi = [int]$latestTarget.DpiScale
            if ($originalDpi -le 0 -or $DpiScaleTable -notcontains $originalDpi) {
                return @{ success = $false; message = '无法可靠读取当前缩放比例，已取消设置以确保可以回滚' }
            }
            if ($originalDpi -eq $TargetScale) {
                return @{ success = $true; verified = $true; unchanged = $true; message = "当前已经是 $TargetScale%" }
            }

            $setResult = Set-DpiScale $latestTarget.AdapterId $latestTarget.SourceId $TargetScale
            if (-not $setResult.success) {
                return @{ success = $false; verified = $false; message = $setResult.message }
            }

            $verifiedTarget = $null
            for ($tryIndex = 0; $tryIndex -lt 4; $tryIndex++) {
                Start-Sleep -Milliseconds 400
                $afterMonitors = Get-Monitors
                $verifiedTarget = Find-MonitorAfterChange -Monitors $afterMonitors -OriginalMonitor $latestTarget
                if ($verifiedTarget -and [int]$verifiedTarget.DpiScale -eq $TargetScale) {
                    return @{ success = $true; verified = $true; unchanged = $false; message = "已应用并验证 $TargetScale% 缩放" }
                }
            }

            $restoreResult = Set-DpiScale $latestTarget.AdapterId $latestTarget.SourceId $originalDpi
            $restoreVerified = $false
            if ($restoreResult.success) {
                for ($restoreTry = 0; $restoreTry -lt 4; $restoreTry++) {
                    Start-Sleep -Milliseconds 400
                    $restoreMonitors = Get-Monitors
                    $restoredTarget = Find-MonitorAfterChange -Monitors $restoreMonitors -OriginalMonitor $latestTarget
                    if ($restoredTarget -and [int]$restoredTarget.DpiScale -eq $originalDpi) {
                        $restoreVerified = $true
                        break
                    }
                }
            }
            $actualDpi = if ($verifiedTarget) { "$($verifiedTarget.DpiScale)%" } else { '未知' }
            $restoreMessage = if ($restoreVerified) {
                "已恢复并验证原来的 $originalDpi%"
            } else {
                '原缩放恢复未通过验证，请在 Windows 显示设置中检查'
            }
            return @{ success = $false; verified = $false; rollbackSuccess = $restoreVerified; message = "缩放回读不匹配（实际: $actualDpi）；$restoreMessage" }
        }
    } catch {
        return @{ success = $false; verified = $false; message = "设置缩放失败: $($_.Exception.Message)" }
    }
}

# 验证新格式模板的完整结构与字段值。加载和保存共用同一边界，避免“JSON 合法但值不可用”
# 的记录进入 GUI 后在整数转换或预览绘制阶段触发未处理异常。
function Assert-TemplateDataValid {
    param($Data)

    if ($null -eq $Data -or -not ($Data -is [PSCustomObject])) {
        throw '模板文件的根节点必须是 JSON 对象'
    }
    if ($null -eq $Data.PSObject.Properties['monitors'] -or $null -eq $Data.monitors -or -not ($Data.monitors -is [PSCustomObject])) {
        throw '模板文件的 monitors 节点必须是 JSON 对象'
    }

    foreach ($monitorProperty in @($Data.monitors.PSObject.Properties)) {
        if ([string]::IsNullOrWhiteSpace([string]$monitorProperty.Name)) {
            throw '模板文件包含空的显示器 ID'
        }
        $group = $monitorProperty.Value
        if ($null -eq $group -or -not ($group -is [PSCustomObject]) -or $null -eq $group.PSObject.Properties['templates']) {
            throw "模板分组 '$($monitorProperty.Name)' 的结构无效"
        }

        foreach ($item in @($group.templates)) {
            if ($null -eq $item -or -not ($item -is [PSCustomObject])) {
                throw "模板分组 '$($monitorProperty.Name)' 包含无效记录"
            }
            foreach ($requiredField in @('name', 'width', 'height', 'refreshRate', 'bitsPerPel', 'dpiScale')) {
                if ($null -eq $item.PSObject.Properties[$requiredField]) {
                    throw "模板分组 '$($monitorProperty.Name)' 的记录缺少字段 '$requiredField'"
                }
            }

            $templateName = [string]$item.name
            if (-not ($item.name -is [string]) -or [string]::IsNullOrWhiteSpace($templateName) -or
                $templateName.Length -gt 100 -or $templateName -match '[\r\n\t]') {
                throw "模板分组 '$($monitorProperty.Name)' 包含无效名称"
            }

            $width = 0; $height = 0; $refreshRate = 0; $bitsPerPel = 0; $dpiScale = 0
            if (-not [int]::TryParse([string]$item.width, [ref]$width) -or $width -le 0) {
                throw "模板 '$templateName' 的宽度无效"
            }
            if (-not [int]::TryParse([string]$item.height, [ref]$height) -or $height -le 0) {
                throw "模板 '$templateName' 的高度无效"
            }
            if (-not [int]::TryParse([string]$item.refreshRate, [ref]$refreshRate) -or $refreshRate -le 0) {
                throw "模板 '$templateName' 的刷新率无效"
            }
            if (-not [int]::TryParse([string]$item.bitsPerPel, [ref]$bitsPerPel) -or $bitsPerPel -le 0) {
                throw "模板 '$templateName' 的颜色深度无效"
            }
            if (-not [int]::TryParse([string]$item.dpiScale, [ref]$dpiScale) -or
                ($dpiScale -ne 0 -and $DpiScaleTable -notcontains $dpiScale)) {
                throw "模板 '$templateName' 的 DPI 缩放值无效"
            }
        }
    }
}

function Load-Templates {
    param([switch]$ForWrite)
    # 新数据结构：按 monitorId 分组
    # { monitors: { "<monitorId>": { name: "...", templates: [ {name, created, width, height, refreshRate, bitsPerPel, dpiScale} ] } } }
    if (Test-Path $TemplateFile) {
        try {
            $data = Get-Content $TemplateFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -eq $data -or -not ($data -is [PSCustomObject])) { throw '模板文件的根节点必须是 JSON 对象' }
            # 新格式
            if ($null -ne $data.PSObject.Properties['monitors'] -and $null -ne $data.monitors) {
                Assert-TemplateDataValid $data
                return $data
            }
            # 旧格式迁移：{ templates: [{name, monitors: [...]}] }
            if ($null -ne $data.PSObject.Properties['templates'] -and $null -ne $data.templates) {
                $newData = [PSCustomObject]@{ monitors = [PSCustomObject]@{} }
                $droppedCount = 0
                foreach ($t in $data.templates) {
                    if ($null -eq $t -or -not ($t -is [PSCustomObject]) -or
                        $null -eq $t.PSObject.Properties['name'] -or $null -eq $t.PSObject.Properties['monitors']) {
                        throw '旧模板文件包含无效的模板记录'
                    }
                    foreach ($m in $t.monitors) {
                        if ($null -eq $m -or -not ($m -is [PSCustomObject])) {
                            throw "旧模板 '$($t.name)' 包含无效的显示器记录"
                        }
                        if (-not $m.monitorId) { $droppedCount++; continue }
                        $mid = $m.monitorId
                        if ($null -eq $newData.monitors.PSObject.Properties[$mid]) {
                            $newData.monitors | Add-Member -MemberType NoteProperty -Name $mid -Value ([PSCustomObject]@{ name = $m.monitorName; templates = @() })
                        }
                        $newData.monitors.$mid.templates += [PSCustomObject]@{
                            name        = $t.name
                            created     = $t.created
                            width       = $m.width
                            height      = $m.height
                            refreshRate = $m.refreshRate
                            bitsPerPel  = $m.bitsPerPel
                            dpiScale    = $m.dpiScale
                        }
                    }
                }
                if ($droppedCount -gt 0) {
                    Write-Warning "旧模板格式迁移: $droppedCount 条记录因缺少 MonitorId 被跳过"
                }
                Assert-TemplateDataValid $newData
                # 迁移本身也属于写操作。取得锁后重新检查磁盘：若其他实例已迁移并写入，
                # 直接采用最新内容，避免用先前读到的旧数据覆盖它的新模板。
                try {
                    return Invoke-WithNamedMutex -Name $DataMutexName -Action {
                        $latest = Get-Content $TemplateFile -Raw -Encoding UTF8 | ConvertFrom-Json
                        if ($null -ne $latest.PSObject.Properties['monitors'] -and $null -ne $latest.monitors) {
                            Assert-TemplateDataValid $latest
                            return $latest
                        }

                        $legacyBackup = "$TemplateFile.bak"
                        Copy-Item $TemplateFile $legacyBackup -Force -ErrorAction Stop
                        if (-not (Test-Path -LiteralPath $legacyBackup)) {
                            throw '旧模板备份文件未生成'
                        }

                        # 写操作的调用方会在本次修改结束时一次性保存迁移结果，避免中间重复写盘。
                        if (-not $ForWrite -and -not (Save-Templates $newData)) {
                            Write-Warning "旧模板已在内存中完成迁移，但新格式暂未能写入磁盘；下次启动会再次尝试"
                        }
                        return $newData
                    }
                } catch {
                    Write-Warning "旧模板已在内存中完成迁移，但迁移写入被推迟: $($_.Exception.Message)"
                    if ($ForWrite) {
                        $migrationException = New-Object System.InvalidOperationException("旧模板无法安全迁移，已阻止写入: $($_.Exception.Message)", $_.Exception)
                        $migrationException.Data['MonitorManagerMigrationFailure'] = $true
                        throw $migrationException
                    }
                    return $newData
                }
            }
            throw '模板文件不包含受支持的数据结构'
        } catch {
            # 有效旧格式文件的迁移/备份失败不等于 JSON 损坏，不创建误导性的 corrupted 备份。
            if ($_.Exception.Data -and $_.Exception.Data.Contains('MonitorManagerMigrationFailure')) {
                throw
            }
            # 读取用途可降级为空对象；写入用途必须中止，避免用空数据覆盖损坏文件。
            $timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss-fff')
            $backupPath = "$TemplateFile.corrupted.$timestamp.bak"
            $backupSucceeded = $false
            try {
                Copy-Item $TemplateFile $backupPath -Force -ErrorAction Stop
                $backupSucceeded = Test-Path $backupPath
            } catch {
                Write-Warning "模板文件已损坏，且备份失败: $($_.Exception.Message)"
            }
            if ($backupSucceeded) {
                Write-Warning "模板文件已损坏，已备份至: $backupPath"
            }
            if ($ForWrite) {
                $backupInfo = if ($backupSucceeded) { "备份: $backupPath" } else { '备份未成功' }
                throw "模板文件损坏，已阻止写入（$backupInfo）"
            }
        }
    }
    return [PSCustomObject]@{ monitors = [PSCustomObject]@{} }
}

function Save-Templates {
    param($Templates)
    $tmpFile = $null
    try {
        Assert-TemplateDataValid $Templates
        if (-not (Test-Path $TemplateDir)) {
            New-Item -Path $TemplateDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        # 同目录唯一临时文件 + rename，防止中断损坏并避免多实例共用同一 .tmp 文件
        $tmpFile = Join-Path $TemplateDir ("templates.{0}.{1}.tmp" -f $PID, [Guid]::NewGuid().ToString('N'))
        $Templates | ConvertTo-Json -Depth 10 | Set-Content $tmpFile -Encoding UTF8 -ErrorAction Stop
        Move-Item $tmpFile $TemplateFile -Force -ErrorAction Stop
        return $true
    } catch {
        Write-Warning "保存模板失败: $($_.Exception.Message)"
        if ($tmpFile -and (Test-Path $tmpFile)) { Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue }
        return $false
    }
}

# 获取指定显示器下的所有模板（返回数组）
function Get-MonitorTemplates {
    param([string]$MonitorId, $Templates)
    if (-not $MonitorId -or -not $Templates) { return @() }
    if ($Templates.monitors -and $null -ne $Templates.monitors.PSObject.Properties[$MonitorId]) {
        return @($Templates.monitors.$MonitorId.templates)
    }
    return @()
}

# 比较模板参数。保存去重使用严格匹配；与当前显示状态匹配时允许刷新率存在 1Hz 回读误差。
function Test-TemplateParametersMatch {
    param(
        $Template,
        [int]$Width,
        [int]$Height,
        [int]$RefreshRate,
        [int]$BitsPerPel,
        [int]$DpiScale,
        [int]$RefreshTolerance = 0
    )
    if (-not $Template) { return $false }

    $templateWidth = 0; $templateHeight = 0; $templateRefresh = 0; $templateBpp = 0; $templateDpi = 0
    if (-not [int]::TryParse([string]$Template.width, [ref]$templateWidth) -or
        -not [int]::TryParse([string]$Template.height, [ref]$templateHeight) -or
        -not [int]::TryParse([string]$Template.refreshRate, [ref]$templateRefresh) -or
        -not [int]::TryParse([string]$Template.bitsPerPel, [ref]$templateBpp) -or
        -not [int]::TryParse([string]$Template.dpiScale, [ref]$templateDpi)) {
        return $false
    }

    return ($templateWidth -eq $Width -and
        $templateHeight -eq $Height -and
        [Math]::Abs($templateRefresh - $RefreshRate) -le [Math]::Max(0, $RefreshTolerance) -and
        $templateBpp -eq $BitsPerPel -and
        $templateDpi -eq $DpiScale)
}

# 选择模板时优先保留同一显示器上的用户选择；否则匹配当前实际显示参数。
function Get-PreferredTemplateName {
    param(
        $Templates,
        $Monitor,
        [string]$PreviousTemplateName,
        [string]$PreviousMonitorId
    )
    if (-not $Monitor -or -not $Monitor.MonitorId) { return $null }

    $monitorId = [string]$Monitor.MonitorId
    $monitorTemplates = @(Get-MonitorTemplates -MonitorId $monitorId -Templates $Templates)

    if ($PreviousMonitorId -eq $monitorId -and -not [string]::IsNullOrWhiteSpace($PreviousTemplateName)) {
        $previous = $monitorTemplates |
            Where-Object { [string]$_.name -eq $PreviousTemplateName } |
            Select-Object -First 1
        if ($previous) { return [string]$previous.name }
    }

    if (-not (Test-MonitorIsActive $Monitor) -or
        [int]$Monitor.Width -le 0 -or [int]$Monitor.Height -le 0 -or
        [int]$Monitor.RefreshRate -le 0 -or [int]$Monitor.BitsPerPel -le 0 -or
        [int]$Monitor.DpiScale -le 0) {
        return $null
    }

    $matching = $monitorTemplates |
        Where-Object {
            Test-TemplateParametersMatch -Template $_ `
                -Width ([int]$Monitor.Width) -Height ([int]$Monitor.Height) `
                -RefreshRate ([int]$Monitor.RefreshRate) -BitsPerPel ([int]$Monitor.BitsPerPel) `
                -DpiScale ([int]$Monitor.DpiScale) -RefreshTolerance 1
        } |
        Select-Object -First 1

    if ($matching) { return [string]$matching.name }
    return $null
}

function Get-ChangeResultMessage {
    param([int]$Code)
    switch ($Code) {
        0  { "成功" }
        1  { "需要重启" }
        -1 { "失败" }
        -2 { "不支持的模式" }
        -3 { "未写入注册表" }
        -4 { "标志无效" }
        -5 { "参数无效" }
        -6 { "双视图错误" }
        default { "未知错误 ($Code)" }
    }
}

function ConvertTo-Base64Text {
    param([string]$Text)
    return [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes([string]$Text))
}

function ConvertFrom-Base64Text {
    param([string]$Text)
    return [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($Text))
}

# GUI 后台进程使用固定前缀和 Base64 传递最终结果。解析器按标记查找，
# 不依赖 stdout/stderr 的最后一行，因此不会被 PowerShell 或驱动附加警告覆盖。
function Write-WorkerResult {
    param([AllowEmptyString()][string]$Message)
    Write-Output ($script:WorkerResultPrefix + (ConvertTo-Base64Text ([string]$Message)))
}

function Get-WorkerResultMessage {
    param(
        [AllowEmptyString()][string]$StandardOutput,
        [AllowEmptyString()][string]$StandardError,
        [AllowEmptyString()][string]$Fallback = ''
    )

    $lines = @(($StandardOutput + [Environment]::NewLine + $StandardError) -split '\r?\n')
    $markers = @($lines | Where-Object { ([string]$_).StartsWith($script:WorkerResultPrefix, [StringComparison]::Ordinal) })
    if ($markers.Count -gt 0) {
        $payload = ([string]$markers[$markers.Count - 1]).Substring($script:WorkerResultPrefix.Length)
        try { return ConvertFrom-Base64Text $payload } catch {}
    }

    # 兼容旧版后台进程或标记损坏的情况；忽略无法解析的结果标记。
    $plainLines = @($lines | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_) -and
        -not ([string]$_).StartsWith($script:WorkerResultPrefix, [StringComparison]::Ordinal)
    })
    if ($plainLines.Count -gt 0) { return ([string]$plainLines[$plainLines.Count - 1]).Trim() }
    return $Fallback
}

function Complete-WorkerOutput {
    param(
        [object[]]$Records,
        [AllowEmptyString()][string]$Fallback = ''
    )

    $detail = $Fallback
    foreach ($record in @($Records)) {
        $text = [string]$record
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        Write-Output $text
        $detail = $text.Trim()
    }
    Write-WorkerResult -Message $detail
}

# ============================================================
#  辅助：解析显示器标识（序号 / monitorId / displayName）
# ============================================================

function Resolve-Monitor {
    param([string]$Spec, $Monitors)
    if (-not $Monitors -or $Monitors.Count -eq 0) { return $null }
    # 1. 数字序号（1-based）
    $idx = 0
    if ([int]::TryParse($Spec, [ref]$idx) -and $idx -ge 1 -and $idx -le $Monitors.Count) {
        return $Monitors[$idx - 1]
    }
    # 2. monitorId 完全匹配
    $m = $Monitors | Where-Object { $_.MonitorId -eq $Spec } | Select-Object -First 1
    if ($m) { return $m }
    # 3. displayName 完全匹配
    $m = $Monitors | Where-Object { $_.DisplayName -eq $Spec } | Select-Object -First 1
    if ($m) { return $m }
    # 4. 友好名称唯一匹配（离线模板组也可用名称定位）
    $nameMatches = @($Monitors | Where-Object { $_.MonitorName -and $_.MonitorName -eq $Spec })
    if ($nameMatches.Count -eq 1) { return $nameMatches[0] }
    # 5. monitorId 包含匹配（仅当唯一匹配时才返回，避免歧义）
    $partialMatches = @($Monitors | Where-Object { $_.MonitorId -and $_.MonitorId.Contains($Spec) })
    if ($partialMatches.Count -eq 1) { return $partialMatches[0] }
    if ($partialMatches.Count -gt 1) {
        # 多匹配时尝试精确匹配子串（如完整设备 ID 中的一部分）
        $exactPartial = $partialMatches | Where-Object { $_.MonitorId -eq $Spec } | Select-Object -First 1
        if ($exactPartial) { return $exactPartial }
    }
    return $null
}

# 合并当前已连接显示器与仅存在于模板文件中的离线显示器组。
# 当前显示器排在前面，因此 templates 命令显示的序号可直接用于 show/delete。
function Get-TemplateMonitorEntries {
    param($Monitors, $Templates)

    $entries = @()
    $connectedIds = @{}
    foreach ($m in @($Monitors)) {
        if ($null -eq $m.PSObject.Properties['IsConnected']) {
            $m | Add-Member -MemberType NoteProperty -Name IsConnected -Value $true
        }
        if ($null -eq $m.PSObject.Properties['IsActive']) {
            $m | Add-Member -MemberType NoteProperty -Name IsActive -Value ([bool]$m.IsConnected)
        }
        if ($m.MonitorId) { $connectedIds[$m.MonitorId] = $true }
        $entries += $m
    }

    if ($Templates -and $Templates.monitors) {
        $customNames = Load-MonitorNames
        foreach ($mid in @($Templates.monitors.PSObject.Properties | ForEach-Object { $_.Name })) {
            if ($connectedIds.ContainsKey($mid)) { continue }
            $group = $Templates.monitors.$mid
            $storedName = if ($group.name) { [string]$group.name } else { $mid }
            if ($null -ne $customNames.PSObject.Properties[$mid]) { $storedName = [string]$customNames.$mid }
            $entries += [PSCustomObject]@{
                DisplayName  = '未连接'
                MonitorName  = $storedName
                MonitorId    = $mid
                Width        = 0
                Height       = 0
                RefreshRate  = 0
                BitsPerPel   = 0
                DpiScale     = 0
                AdapterId    = $null
                TargetAdapterId = $null
                SourceId     = [uint32]0
                TargetId     = [uint32]0
                IsPrimary    = $false
                IsConnected  = $false
                IsActive     = $false
            }
        }
    }
    return $entries
}

# ============================================================
#  核心操作（按单个显示器）
# ============================================================

function Wait-MonitorPowerState {
    param(
        [string]$TargetKey,
        [bool]$DesiredActive,
        [int]$ExpectedActiveCount,
        [int]$Attempts = 8
    )
    $lastMonitors = @()
    for ($attempt = 0; $attempt -lt $Attempts; $attempt++) {
        if ($attempt -gt 0) { Start-Sleep -Milliseconds 350 }
        $lastMonitors = Get-Monitors
        # MonitorId 可能在 target 从 inactive 变为 active 后因驱动枚举路径变化而改变；
        # 电源状态必须按 DisplayConfig 的物理 target 身份验证。
        $target = $lastMonitors | Where-Object { (Get-MonitorTargetKey $_) -eq $TargetKey } | Select-Object -First 1
        $targetActive = [bool]($target -and (Test-MonitorIsActive $target))
        $activeMonitors = @($lastMonitors | Where-Object { Test-MonitorIsActive $_ })
        $hasPrimary = [bool]($activeMonitors | Where-Object { $_.IsPrimary } | Select-Object -First 1)
        if ($target -and $targetActive -eq $DesiredActive -and $activeMonitors.Count -eq $ExpectedActiveCount) {
            if ($hasPrimary) {
                return @{ success = $true; monitors = $lastMonitors; activeCount = $activeMonitors.Count; primaryObserved = $true }
            }
            # 断开原主显示器后，Windows 拓扑通常已生效，但 WinForms Screen.Primary
            # 可能在当前进程中延迟刷新。继续轮询，不能仅凭该缓存标记回滚成功的拓扑。
        }
    }
    $actualTarget = $lastMonitors | Where-Object { (Get-MonitorTargetKey $_) -eq $TargetKey } | Select-Object -First 1
    $actualActiveMonitors = @($lastMonitors | Where-Object { Test-MonitorIsActive $_ })
    $actualHasPrimary = [bool]($actualActiveMonitors | Where-Object { $_.IsPrimary } | Select-Object -First 1)
    if ($actualTarget -and
        [bool](Test-MonitorIsActive $actualTarget) -eq $DesiredActive -and
        $actualActiveMonitors.Count -eq $ExpectedActiveCount) {
        # 请求结果本身已经由 DisplayConfig 目标状态和活动路径数量双重确认。
        # Windows 必定会为活动桌面确定主显示器；这里只记录 WinForms 是否已观察到。
        return @{ success = $true; monitors = $lastMonitors; activeCount = $actualActiveMonitors.Count; primaryObserved = $actualHasPrimary }
    }
    return @{
        success = $false
        monitors = $lastMonitors
        activeCount = $actualActiveMonitors.Count
        targetFound = [bool]$actualTarget
        targetActive = [bool]($actualTarget -and (Test-MonitorIsActive $actualTarget))
        primaryObserved = $actualHasPrimary
    }
}

function Invoke-MonitorPowerCoreUnlocked {
    param([string]$MonitorSpec, [ValidateSet('on', 'off')][string]$Operation)
    $MonitorSpec = ([string]$MonitorSpec).Trim()
    if ([string]::IsNullOrWhiteSpace($MonitorSpec)) { return @{ success = $false; error = '请指定显示器（序号/ID/名称）' } }

    $monitors = Get-Monitors
    if ($monitors.Count -eq 0) { return @{ success = $false; error = '未检测到显示器' } }
    $target = Resolve-Monitor -Spec $MonitorSpec -Monitors $monitors
    if (-not $target) { return @{ success = $false; error = "未找到显示器 '$MonitorSpec'" } }
    if (-not $target.IsConnected) { return @{ success = $false; error = "系统当前未检测到显示器 '$($target.MonitorName)'，无法连接或断开" } }

    $targetIsActive = Test-MonitorIsActive $target
    if ($Operation -eq 'off' -and -not $targetIsActive) { return @{ success = $false; alreadySet = $true; error = "显示器 '$($target.MonitorName)' 已处于断开状态" } }
    if ($Operation -eq 'on' -and $targetIsActive) { return @{ success = $false; alreadySet = $true; error = "显示器 '$($target.MonitorName)' 已处于连接状态" } }

    $activeMonitors = @($monitors | Where-Object { Test-MonitorIsActive $_ })
    if ($Operation -eq 'off' -and $activeMonitors.Count -le 1) {
        return @{ success = $false; safetyBlocked = $true; error = '不能断开最后一台活动显示器，请先连接另一台显示器' }
    }

    $original = Get-DisplayConfigTopology -Flags $QDC_ONLY_ACTIVE_PATHS
    if (-not $original.success -or @($original.paths).Count -eq 0) {
        return @{ success = $false; error = if ($original.error) { $original.error } else { '无法读取当前活动显示拓扑' } }
    }

    $targetKey = Get-MonitorTargetKey $target
    $desiredPaths = @()
    if ($Operation -eq 'off') {
        foreach ($path in @($original.paths)) {
            if ((Get-DisplayPathTargetKey $path) -ne $targetKey) { $desiredPaths += $path }
        }
        if ($desiredPaths.Count -eq @($original.paths).Count) {
            return @{ success = $false; error = "未在活动拓扑中找到显示器 '$($target.MonitorName)'" }
        }
        if ($desiredPaths.Count -lt 1) {
            return @{ success = $false; safetyBlocked = $true; error = '不能断开最后一条活动显示路径' }
        }
    } else {
        $allTopology = Get-DisplayConfigTopology -Flags $QDC_ALL_PATHS
        if (-not $allTopology.success) { return @{ success = $false; error = $allTopology.error } }

        $activeSourceKeys = @{}
        foreach ($path in @($original.paths)) { $activeSourceKeys[(Get-DisplayPathSourceKey $path)] = $true }
        $candidates = @($allTopology.paths | Where-Object {
            (Get-DisplayPathTargetKey $_) -eq $targetKey -and $_.targetInfo.targetAvailable
        })
        $candidate = $candidates | Where-Object { -not $activeSourceKeys.ContainsKey((Get-DisplayPathSourceKey $_)) } | Select-Object -First 1
        if (-not $candidate) {
            return @{ success = $false; safetyBlocked = $true; error = "没有可用于独立连接 '$($target.MonitorName)' 的空闲显示源；请先在 Windows 显示设置中调整复制模式" }
        }
        $desiredPaths = @($original.paths) + @($candidate)
    }

    $change = Set-PathOnlyDisplayTopology -Paths $desiredPaths
    if (-not $change.success) {
        $rollback = Restore-DisplayTopology -Snapshot $original
        $operationText = if ($Operation -eq 'off') { '断开' } else { '连接' }
        return @{
            success = $false
            error = "显示器${operationText}失败 (code=$($change.code))"
            result = @{ operation = $Operation; method = $change.method; rollbackAttempted = $true; rollbackSuccess = [bool]$rollback.success; rollbackMessage = $rollback.message }
        }
    }

    $expectedActiveCount = $activeMonitors.Count + $(if ($Operation -eq 'on') { 1 } else { -1 })
    $verified = Wait-MonitorPowerState -TargetKey $targetKey -DesiredActive ($Operation -eq 'on') -ExpectedActiveCount $expectedActiveCount
    if (-not $verified.success) {
        $rollback = Restore-DisplayTopology -Snapshot $original
        return @{
            success = $false
            error = "显示器状态回读与预期不一致，已尝试恢复原始拓扑"
            result = @{ operation = $Operation; method = $change.method; rollbackAttempted = $true; rollbackSuccess = [bool]$rollback.success; rollbackMessage = $rollback.message }
        }
    }

    $primaryObserved = $true
    if ($verified -is [System.Collections.IDictionary] -and $verified.Contains('primaryObserved')) {
        $primaryObserved = [bool]$verified['primaryObserved']
    } elseif ($null -ne $verified.PSObject.Properties['primaryObserved']) {
        $primaryObserved = [bool]$verified.primaryObserved
    }

    return @{
        success = $true
        monitorId = [string]$target.MonitorId
        monitorName = [string]$target.MonitorName
        operation = $Operation
        state = if ($Operation -eq 'on') { 'on' } else { 'off' }
        method = $change.method
        activeCount = $verified.activeCount
        primaryObserved = $primaryObserved
    }
}

function Invoke-MonitorPowerCore {
    param([string]$MonitorSpec, [ValidateSet('on', 'off')][string]$Operation)
    try {
        return Invoke-WithNamedMutex -Name $DisplayMutexName -TimeoutMs 30000 -Action {
            Invoke-MonitorPowerCoreUnlocked -MonitorSpec $MonitorSpec -Operation $Operation
        }
    } catch {
        return @{ success = $false; error = "显示器电源操作失败: $($_.Exception.Message)" }
    }
}

# 保存指定显示器当前配置为模板（调用方必须已取得显示操作锁）
function Invoke-SaveTemplateCoreUnlocked {
    param([string]$MonitorSpec, [string]$TemplateName)
    $TemplateName = ([string]$TemplateName).Trim()
    $MonitorSpec = ([string]$MonitorSpec).Trim()
    if ([string]::IsNullOrWhiteSpace($TemplateName)) { return @{ success = $false; error = "请指定模板名称" } }
    if ($TemplateName.Length -gt 100 -or $TemplateName -match '[\r\n\t]') {
        return @{ success = $false; error = "模板名称不能超过 100 个字符，也不能包含换行或制表符" }
    }
    if ([string]::IsNullOrWhiteSpace($MonitorSpec)) { return @{ success = $false; error = "请指定显示器（序号/ID/名称）" } }

    $monitors = Get-Monitors
    if ($monitors.Count -eq 0) { return @{ success = $false; error = "未检测到显示器" } }

    $target = Resolve-Monitor -Spec $MonitorSpec -Monitors $monitors
    if (-not $target) { return @{ success = $false; error = "未找到显示器 '$MonitorSpec'（可用: 1-$($monitors.Count)）" } }
    if (-not (Test-MonitorIsActive $target)) { return @{ success = $false; error = "显示器 '$($target.MonitorName)' 当前未启用，无法保存当前配置" } }

    if (-not $target.MonitorId) { return @{ success = $false; error = "显示器无 MonitorId，无法保存" } }

    # 验证当前显示器数据有效性（防止 EnumDisplaySettingsEx 失败时的零值被保存）
    if ($target.Width -le 0 -or $target.Height -le 0) {
        return @{ success = $false; error = "无法获取显示器分辨率（当前: $($target.Width)x$($target.Height)），请重试" }
    }
    if ($target.RefreshRate -le 0) {
        return @{ success = $false; error = "无法获取显示器刷新率（当前: $($target.RefreshRate)Hz），请重试" }
    }
    if ($target.BitsPerPel -le 0) {
        return @{ success = $false; error = "无法获取显示器颜色深度（当前: $($target.BitsPerPel)bit），请重试" }
    }

    try {
        return Invoke-WithNamedMutex -Name $DataMutexName -Action {
            $templates = Load-Templates -ForWrite
            $existingTemplate = $null
            if ($null -ne $templates.monitors.PSObject.Properties[$target.MonitorId]) {
                $existingTemplate = @($templates.monitors.$($target.MonitorId).templates) |
                    Where-Object { $_.name -eq $TemplateName } |
                    Select-Object -First 1
            }

            $dpiScale = [int]$target.DpiScale
            $dpiPreserved = $false
            if ($dpiScale -le 0) {
                if ($existingTemplate -and $DpiScaleTable -contains [int]$existingTemplate.dpiScale) {
                    $dpiScale = [int]$existingTemplate.dpiScale
                    $dpiPreserved = $true
                } else {
                    return @{ success = $false; error = "无法读取当前缩放比例，已取消保存，避免生成不完整模板" }
                }
            } elseif ($DpiScaleTable -notcontains $dpiScale) {
                return @{ success = $false; error = "当前缩放比例 $dpiScale% 不受支持，已取消保存" }
            }

            $duplicateTemplate = $null
            if ($null -ne $templates.monitors.PSObject.Properties[$target.MonitorId]) {
                $duplicateTemplate = @($templates.monitors.$($target.MonitorId).templates) |
                    Where-Object {
                        Test-TemplateParametersMatch -Template $_ `
                            -Width ([int]$target.Width) -Height ([int]$target.Height) `
                            -RefreshRate ([int]$target.RefreshRate) -BitsPerPel ([int]$target.BitsPerPel) `
                            -DpiScale $dpiScale
                    } |
                    Select-Object -First 1
            }
            if ($duplicateTemplate) {
                return @{
                    success       = $false
                    duplicate     = $true
                    duplicateName = [string]$duplicateTemplate.name
                    error         = "相同参数的模板 '$($duplicateTemplate.name)' 已存在，无需重复添加"
                }
            }

            $template = [PSCustomObject]@{
                name        = $TemplateName
                created     = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                width       = $target.Width
                height      = $target.Height
                refreshRate = $target.RefreshRate
                bitsPerPel  = $target.BitsPerPel
                dpiScale    = $dpiScale
            }

            if ($null -eq $templates.monitors.PSObject.Properties[$target.MonitorId]) {
                $templates.monitors | Add-Member -MemberType NoteProperty -Name $target.MonitorId -Value ([PSCustomObject]@{ name = $target.MonitorName; templates = @() })
            }
            # 同名覆盖；锁覆盖整个“读取→修改→保存”，避免多实例互相覆盖。
            $templates.monitors.$($target.MonitorId).templates = @($templates.monitors.$($target.MonitorId).templates | Where-Object { $_.name -ne $TemplateName })
            $templates.monitors.$($target.MonitorId).templates += $template
            $templates.monitors.$($target.MonitorId).name = $target.MonitorName
            if (-not (Save-Templates $templates)) {
                return @{ success = $false; error = "模板 '$TemplateName' 未能写入 $TemplateFile" }
            }

            return @{ success = $true; name = $TemplateName; monitorId = $target.MonitorId; monitorName = $target.MonitorName; template = $template; dpiPreserved = $dpiPreserved }
        }
    } catch {
        return @{ success = $false; error = "保存模板失败: $($_.Exception.Message)" }
    }
}

function Save-TemplateCore {
    param([string]$MonitorSpec, [string]$TemplateName)
    try {
        # 锁住“读取当前显示状态→写入模板”的完整快照过程，避免保存到应用中的瞬态配置。
        return Invoke-WithNamedMutex -Name $DisplayMutexName -TimeoutMs 30000 -Action {
            Invoke-SaveTemplateCoreUnlocked -MonitorSpec $MonitorSpec -TemplateName $TemplateName
        }
    } catch {
        return @{ success = $false; error = "保存模板失败: $($_.Exception.Message)" }
    }
}

function Find-MonitorAfterChange {
    param($Monitors, $OriginalMonitor)
    $match = $Monitors | Where-Object { $_.MonitorId -and $_.MonitorId -eq $OriginalMonitor.MonitorId } | Select-Object -First 1
    if (-not $match) {
        $match = $Monitors | Where-Object { $_.DisplayName -eq $OriginalMonitor.DisplayName } | Select-Object -First 1
    }
    return $match
}

function Test-DisplayModeMatches {
    param($Monitor, [int]$Width, [int]$Height, [int]$RefreshRate, [int]$BitsPerPel)
    if (-not $Monitor) { return $false }
    $refreshMatches = [Math]::Abs(([int]$Monitor.RefreshRate) - $RefreshRate) -le 1
    $bppMatches = ($BitsPerPel -le 0 -or [int]$Monitor.BitsPerPel -eq $BitsPerPel)
    return ([int]$Monitor.Width -eq $Width -and [int]$Monitor.Height -eq $Height -and $refreshMatches -and $bppMatches)
}

function Test-AdapterIdAvailable {
    param($AdapterId)
    if (-not $AdapterId) { return $false }
    try {
        return ([uint32]$AdapterId.LowPart -ne 0 -or [int]$AdapterId.HighPart -ne 0)
    } catch {
        return $false
    }
}

# 集中封装会改变显示状态的原生调用，便于统一处理，也允许安全测试替换这些边界函数。
function Get-CurrentDisplayModeSnapshot {
    param([string]$DisplayName)
    try {
        $mode = New-Object DEVMODE
        $mode.dmSize = [System.Runtime.InteropServices.Marshal]::SizeOf([Type][DEVMODE])
        if (-not [DisplayApi]::EnumDisplaySettingsEx($DisplayName, $ENUM_CURRENT_SETTINGS, [ref]$mode, 0)) {
            return @{ success = $false; error = 'EnumDisplaySettingsEx 返回失败' }
        }
        return @{ success = $true; mode = $mode }
    } catch {
        return @{ success = $false; error = $_.Exception.Message }
    }
}

function Set-PendingDisplayMode {
    param([string]$DisplayName, $Mode)
    return [DisplayApi]::ChangeDisplaySettingsEx(
        $DisplayName, [ref]$Mode, [IntPtr]::Zero,
        $CDS_UPDATEREGISTRY -bor $CDS_NORESET, [IntPtr]::Zero
    )
}

function Commit-PendingDisplayModes {
    return [DisplayApi]::ChangeDisplaySettingsEx([NullString]::Value, [IntPtr]::Zero, [IntPtr]::Zero, 0, [IntPtr]::Zero)
}

# 将显示模式和缩放比例恢复到应用模板前的精确快照。
# 调用方必须已取得 DisplayMutex；本函数始终返回结构化结果，不向外抛出异常。
function Restore-DisplaySnapshot {
    param([string]$DisplayName, $OriginalMode, $OriginalMonitor)

    $rollback = @{
        attempted    = $true
        success      = $false
        modeRestored = $false
        dpiRestored  = $false
        message      = ''
    }

    try {
        if (-not $OriginalMode -or -not $OriginalMonitor) {
            $rollback.message = '自动回滚失败：缺少原始显示快照，请在 Windows 显示设置中检查'
            return $rollback
        }

        $restoreStage = Set-PendingDisplayMode -DisplayName $DisplayName -Mode $OriginalMode
        if ($restoreStage -ne 0 -and $restoreStage -ne 1) {
            $rollback.message = "自动回滚写入失败: $(Get-ChangeResultMessage $restoreStage)；请在 Windows 显示设置中检查"
            return $rollback
        }

        $restoreCommit = Commit-PendingDisplayModes
        if ($restoreCommit -ne 0) {
            $rollback.message = "自动回滚提交失败: $(Get-ChangeResultMessage $restoreCommit)；请在 Windows 显示设置中检查"
            return $rollback
        }

        $restoredMonitor = $null
        for ($modeTry = 0; $modeTry -lt 5; $modeTry++) {
            Start-Sleep -Milliseconds 500
            $restoredMonitors = Get-Monitors
            $restoredMonitor = Find-MonitorAfterChange -Monitors $restoredMonitors -OriginalMonitor $OriginalMonitor
            if (Test-DisplayModeMatches $restoredMonitor $OriginalMode.dmPelsWidth $OriginalMode.dmPelsHeight $OriginalMode.dmDisplayFrequency $OriginalMode.dmBitsPerPel) {
                $rollback.modeRestored = $true
                break
            }
        }
        if (-not $rollback.modeRestored) {
            $actual = if ($restoredMonitor) { "$($restoredMonitor.Width)x$($restoredMonitor.Height)@$($restoredMonitor.RefreshRate)Hz/$($restoredMonitor.BitsPerPel)bit" } else { '显示器未重新枚举' }
            $rollback.message = "自动回滚未通过显示模式验证（实际: $actual）；请在 Windows 显示设置中检查"
            return $rollback
        }

        $originalDpi = [int]$OriginalMonitor.DpiScale
        if ($originalDpi -le 0) {
            # 原始 DPI 无法可靠读取时不猜测；显示模式已精确恢复。
            $rollback.dpiRestored = $true
        } elseif (-not $restoredMonitor -or -not (Test-AdapterIdAvailable $restoredMonitor.AdapterId)) {
            $rollback.message = '显示模式已回滚，但缺少 AdapterId，无法恢复原始缩放比例；请在 Windows 显示设置中检查'
            return $rollback
        } else {
            $dpiRestore = Set-DpiScale $restoredMonitor.AdapterId $restoredMonitor.SourceId $originalDpi
            if (-not $dpiRestore.success) {
                $rollback.message = "显示模式已回滚，但缩放比例恢复失败: $($dpiRestore.message)；请在 Windows 显示设置中检查"
                return $rollback
            }
            for ($dpiTry = 0; $dpiTry -lt 4; $dpiTry++) {
                Start-Sleep -Milliseconds 400
                $dpiMonitors = Get-Monitors
                $dpiMonitor = Find-MonitorAfterChange -Monitors $dpiMonitors -OriginalMonitor $OriginalMonitor
                if ($dpiMonitor -and [int]$dpiMonitor.DpiScale -eq $originalDpi) {
                    $rollback.dpiRestored = $true
                    break
                }
            }
            if (-not $rollback.dpiRestored) {
                $actualDpi = if ($dpiMonitor) { "$($dpiMonitor.DpiScale)%" } else { '未知' }
                $rollback.message = "显示模式已回滚，但缩放比例未通过验证（实际: $actualDpi）；请在 Windows 显示设置中检查"
                return $rollback
            }
        }

        $rollback.success = $true
        $rollback.message = '已自动恢复并验证应用前的显示设置'
        return $rollback
    } catch {
        $rollback.message = "自动回滚异常: $($_.Exception.Message)；请在 Windows 显示设置中检查"
        return $rollback
    }
}

# 应用模板到指定显示器
function Invoke-ApplyTemplateCoreUnlocked {
    param([string]$MonitorSpec, [string]$TemplateName)
    if ([string]::IsNullOrWhiteSpace($TemplateName)) { return @{ success = $false; error = "请指定模板名称" } }
    if ([string]::IsNullOrWhiteSpace($MonitorSpec)) { return @{ success = $false; error = "请指定显示器（序号/ID/名称）" } }

    $originalMode = $null
    $target = $null
    $result = $null
    $rollbackEligible = $false

    try {
        if (-not ([System.Management.Automation.PSTypeName]'DisplayApi').Type) {
            return @{ success = $false; error = '系统显示 API 不可用，无法应用模板' }
        }
        $currentMonitors = Get-Monitors
        if ($currentMonitors.Count -eq 0) { return @{ success = $false; error = "未检测到显示器" } }

        $target = Resolve-Monitor -Spec $MonitorSpec -Monitors $currentMonitors
        if (-not $target) { return @{ success = $false; error = "未找到显示器 '$MonitorSpec'" } }
        if (-not (Test-MonitorIsActive $target)) { return @{ success = $false; error = "显示器 '$($target.MonitorName)' 当前未启用，无法应用模板" } }

        $templates = Load-Templates
        $monitorTemplates = @(Get-MonitorTemplates -MonitorId $target.MonitorId -Templates $templates)
        $template = $monitorTemplates | Where-Object { $_.name -eq $TemplateName } | Select-Object -First 1
        if (-not $template) { return @{ success = $false; error = "显示器 '$($target.DisplayName)' 下未找到模板 '$TemplateName'" } }

        $w = [int]($template.width -as [string])
        $h = [int]($template.height -as [string])
        $rr = [int]($template.refreshRate -as [string])
        $bpp = [int]($template.bitsPerPel -as [string])
        $dpi = [int]($template.dpiScale -as [string])

        if ($w -le 0 -or $h -le 0 -or $rr -le 0 -or $bpp -le 0) {
            return @{ success = $false; error = "模板数据无效（${w}x${h}@${rr}Hz/${bpp}bit），请重新保存模板" }
        }
        if ($dpi -gt 0 -and $DpiScaleTable -notcontains $dpi) {
            return @{ success = $false; error = "模板 DPI 值 $dpi% 不受支持，请重新保存模板" }
        }
        if ($dpi -gt 0 -and ([int]$target.DpiScale -le 0 -or $DpiScaleTable -notcontains [int]$target.DpiScale)) {
            return @{ success = $false; error = '无法可靠读取应用前的缩放比例，已取消操作以确保随时可以完整回滚' }
        }

        # 在任何写操作前保留完整 DEVMODE 与 DPI，用于提交后失败时自动回滚。
        $modeSnapshot = Get-CurrentDisplayModeSnapshot -DisplayName $target.DisplayName
        if (-not $modeSnapshot.success) {
            return @{ success = $false; error = "无法读取应用前的显示模式，已取消操作以避免无法回滚: $($modeSnapshot.error)" }
        }
        $originalMode = $modeSnapshot.mode

        $result = @{
            display          = $target.DisplayName
            monitorId        = $target.MonitorId
            config           = "${w}x${h}@${rr}Hz"
            dpiScale         = $dpi
            resSuccess       = $false
            resVerified      = $false
            resPendingRestart= $false
            dpiSuccess       = $false
            dpiVerified      = $false
            resMessage       = ""
            dpiMessage       = ""
            rollbackAttempted= $false
            rollbackSuccess  = $false
            rollbackMessage  = ""
        }

        # === 第一步：写入并提交分辨率/刷新率/色深 ===
        $dm = New-Object DEVMODE
        $dm.dmSize = [System.Runtime.InteropServices.Marshal]::SizeOf([Type][DEVMODE])
        $dm.dmPelsWidth        = $w
        $dm.dmPelsHeight       = $h
        $dm.dmDisplayFrequency = $rr
        $dm.dmBitsPerPel       = $bpp
        $dm.dmFields = $DM_PELSWIDTH -bor $DM_PELSHEIGHT -bor $DM_DISPLAYFREQUENCY -bor $DM_BITSPERPEL

        $code = Set-PendingDisplayMode -DisplayName $target.DisplayName -Mode $dm
        if ($code -ne 0 -and $code -ne 1) {
            $result.resMessage = Get-ChangeResultMessage $code
            return @{ success = $false; allSuccess = $false; result = $result; error = "分辨率切换失败: $($result.resMessage)" }
        }
        $rollbackEligible = $true

        $commitCode = Commit-PendingDisplayModes
        if ($commitCode -ne 0) {
            $result.resMessage = "提交失败: $(Get-ChangeResultMessage $commitCode)"
            $rollback = Restore-DisplaySnapshot -DisplayName $target.DisplayName -OriginalMode $originalMode -OriginalMonitor $target
            $result.rollbackAttempted = $true
            $result.rollbackSuccess = [bool]$rollback.success
            $result.rollbackMessage = $rollback.message
            $rollbackEligible = $false
            return @{ success = $false; allSuccess = $false; result = $result; error = "$($result.resMessage)；$($rollback.message)" }
        }

        $needsRestart = ($code -eq 1)
        $result.resPendingRestart = $needsRestart
        if ($needsRestart) {
            $result.resMessage = "已写入注册表，但需要重启后生效"
        }

        # === 第二步：重新枚举并验证显示模式 ===
        Start-Sleep -Milliseconds 1000
        $currentMonitors2 = Get-Monitors
        $target2 = Find-MonitorAfterChange -Monitors $currentMonitors2 -OriginalMonitor $target

        if (-not $needsRestart) {
            $retries = 0
            $maxRetries = 5
            while ($retries -lt $maxRetries -and -not (Test-DisplayModeMatches $target2 $w $h $rr $bpp)) {
                Start-Sleep -Milliseconds 800
                $currentMonitors2 = Get-Monitors
                $target2 = Find-MonitorAfterChange -Monitors $currentMonitors2 -OriginalMonitor $target
                $retries++
            }

            if (-not (Test-DisplayModeMatches $target2 $w $h $rr $bpp)) {
                $actual = if ($target2) { "$($target2.Width)x$($target2.Height)@$($target2.RefreshRate)Hz/$($target2.BitsPerPel)bit" } else { "显示器未重新枚举" }
                $result.resMessage = "提交返回成功，但最终配置不匹配（实际: $actual）"
                $rollback = Restore-DisplaySnapshot -DisplayName $target.DisplayName -OriginalMode $originalMode -OriginalMonitor $target
                $result.rollbackAttempted = $true
                $result.rollbackSuccess = [bool]$rollback.success
                $result.rollbackMessage = $rollback.message
                $rollbackEligible = $false
                return @{ success = $false; allSuccess = $false; result = $result; error = "$($result.resMessage)；$($rollback.message)" }
            }
            $result.resSuccess = $true
            $result.resVerified = $true
            $result.resMessage = "已应用并验证"
        }

        # === 第三步：应用并回读验证 DPI ===
        if ($dpi -le 0) {
            $result.dpiSuccess = $true
            $result.dpiVerified = $true
            $result.dpiMessage = "模板未保存 DPI，已跳过"
        } elseif (-not $target2 -or -not (Test-AdapterIdAvailable $target2.AdapterId)) {
            $result.dpiMessage = "无法获取显示器 AdapterId，未设置 DPI"
        } else {
            $dpiResult = Set-DpiScale $target2.AdapterId $target2.SourceId $dpi
            $result.dpiSuccess = [bool]$dpiResult.success
            $result.dpiMessage = $dpiResult.message

            if ($dpiResult.success) {
                for ($dpiTry = 0; $dpiTry -lt 4; $dpiTry++) {
                    Start-Sleep -Milliseconds 400
                    $afterDpiMonitors = Get-Monitors
                    $afterDpi = Find-MonitorAfterChange -Monitors $afterDpiMonitors -OriginalMonitor $target
                    if ($afterDpi -and [int]$afterDpi.DpiScale -eq $dpi) {
                        $result.dpiVerified = $true
                        $result.dpiMessage = "已应用并验证"
                        $target2 = $afterDpi
                        break
                    }
                }
                if (-not $result.dpiVerified) {
                    $actualDpi = if ($afterDpi) { "$($afterDpi.DpiScale)%" } else { "未知" }
                    $result.dpiSuccess = $false
                    $result.dpiMessage = "设置调用成功，但 DPI 回读不匹配（实际: $actualDpi）"
                }
            }
        }

        $allSuccess = $result.resSuccess -and $result.resVerified -and $result.dpiSuccess -and $result.dpiVerified
        $dpiComplete = $result.dpiSuccess -and $result.dpiVerified
        if (-not $dpiComplete) {
            $rollback = Restore-DisplaySnapshot -DisplayName $target.DisplayName -OriginalMode $originalMode -OriginalMonitor $target
            $result.rollbackAttempted = $true
            $result.rollbackSuccess = [bool]$rollback.success
            $result.rollbackMessage = $rollback.message
            $rollbackEligible = $false
            return @{
                success    = $false
                allSuccess = $false
                result     = $result
                error      = "DPI 应用失败: $($result.dpiMessage)；$($rollback.message)"
            }
        }

        $rollbackEligible = $false
        $message = if ($allSuccess) {
            "模板 '$TemplateName' 已应用到 $($target.DisplayName) 并完成验证"
        } elseif ($needsRestart) {
            "缩放比例已应用；显示模式需要重启后生效"
        } else {
            "模板已部分应用"
        }
        return @{
            success        = $true
            allSuccess     = $allSuccess
            pendingRestart = $needsRestart
            result         = $result
            message        = $message
        }
    } catch {
        $errorMessage = "应用模板失败: $($_.Exception.Message)"
        if ($rollbackEligible -and $originalMode -and $target) {
            $rollback = Restore-DisplaySnapshot -DisplayName $target.DisplayName -OriginalMode $originalMode -OriginalMonitor $target
            if ($result) {
                $result.rollbackAttempted = $true
                $result.rollbackSuccess = [bool]$rollback.success
                $result.rollbackMessage = $rollback.message
            }
            $errorMessage = "$errorMessage；$($rollback.message)"
        }
        return @{ success = $false; allSuccess = $false; result = $result; error = $errorMessage }
    }
}

function Apply-TemplateCore {
    param([string]$MonitorSpec, [string]$TemplateName)
    try {
        return Invoke-WithNamedMutex -Name $DisplayMutexName -TimeoutMs 30000 -Action {
            Invoke-ApplyTemplateCoreUnlocked -MonitorSpec $MonitorSpec -TemplateName $TemplateName
        }
    } catch {
        return @{ success = $false; error = "应用模板失败: $($_.Exception.Message)" }
    }
}

# 删除指定显示器下的模板
function Delete-TemplateCore {
    param([string]$MonitorSpec, [string]$TemplateName)
    if (-not $TemplateName) { return @{ success = $false; error = "请指定模板名称" } }
    if (-not $MonitorSpec) { return @{ success = $false; error = "请指定显示器（序号/ID/名称）" } }

    $monitors = Get-Monitors
    try {
        return Invoke-WithNamedMutex -Name $DataMutexName -Action {
            $templates = Load-Templates -ForWrite
            $entries = @(Get-TemplateMonitorEntries -Monitors $monitors -Templates $templates)
            $target = Resolve-Monitor -Spec $MonitorSpec -Monitors $entries
            if (-not $target) { return @{ success = $false; error = "未找到显示器或离线模板组 '$MonitorSpec'" } }

            if ($null -eq $templates.monitors.PSObject.Properties[$target.MonitorId]) {
                return @{ success = $false; error = "显示器 '$($target.MonitorName)' 下无模板" }
            }
            $before = @($templates.monitors.$($target.MonitorId).templates).Count
            $templates.monitors.$($target.MonitorId).templates = @($templates.monitors.$($target.MonitorId).templates | Where-Object { $_.name -ne $TemplateName })
            $after = @($templates.monitors.$($target.MonitorId).templates).Count
            if ($after -eq $before) {
                return @{ success = $false; error = "显示器 '$($target.MonitorName)' 下未找到模板 '$TemplateName'" }
            }
            # 最后一个模板删除后移除空的离线分组。
            if ($after -eq 0) { $templates.monitors.PSObject.Properties.Remove($target.MonitorId) }
            if (-not (Save-Templates $templates)) {
                return @{ success = $false; error = "删除结果未能写入 $TemplateFile" }
            }
            return @{ success = $true; name = $TemplateName; monitorId = $target.MonitorId }
        }
    } catch {
        return @{ success = $false; error = "删除模板失败: $($_.Exception.Message)" }
    }
}

# ============================================================
#  CLI 命令
# ============================================================

function Show-List {
    $monitors = Get-Monitors
    Write-Host ""
    Write-Host "=== 显示器列表 ===" -ForegroundColor Cyan
    Write-Host ""

    if ($monitors.Count -eq 0) {
        Write-Host "  未检测到显示器" -ForegroundColor Yellow
        $script:CommandExitCode = 1
        return
    }

    $i = 1
    foreach ($m in $monitors) {
        $primary = if ($m.IsPrimary) { " (主显示器)" } else { "" }
        Write-Host "[$i] $($m.DisplayName)$primary" -ForegroundColor Yellow
        Write-Host "    显示器名称: $($m.MonitorName)"
        Write-Host "    设备 ID:   $($m.MonitorId)"
        if (Test-MonitorIsActive $m) {
            Write-Host "    分辨率:    $($m.Width) x $($m.Height)"
            Write-Host "    刷新率:    $($m.RefreshRate) Hz"
            Write-Host "    颜色深度:  $($m.BitsPerPel) bit"
            $dpiDisplay = if ($m.DpiScale -gt 0) { "$($m.DpiScale)%" } else { "未知" }
            Write-Host "    缩放比例:  $dpiDisplay"
        } else {
            Write-Host "    状态:      已从 Windows 桌面断开（可重新连接）" -ForegroundColor DarkYellow
        }
        Write-Host ""
        $i++
    }
    Write-Host "提示: 使用序号 [1-$($monitors.Count)] 或显示器 ID 操作模板" -ForegroundColor Gray
    Write-Host "      例: .\MonitorManager.ps1 save 1 工作" -ForegroundColor Gray
    Write-Host ""
}

function Save-Template {
    param([string]$MonitorSpec, [string]$TemplateName)
    if ([string]::IsNullOrWhiteSpace($MonitorSpec) -or [string]::IsNullOrWhiteSpace($TemplateName)) {
        Write-Host "错误: 用法 save <显示器序号/ID> <模板名>" -ForegroundColor Red
        Write-Host "示例: .\MonitorManager.ps1 save 1 工作" -ForegroundColor Gray
        $script:CommandExitCode = 2
        return
    }
    $r = Save-TemplateCore $MonitorSpec $TemplateName
    if (-not $r.success) {
        Write-Host "错误: $($r.error)" -ForegroundColor Red
        $script:CommandExitCode = 1
        return
    }
    $t = $r.template
    $dpi = if ([int]$t.dpiScale -gt 0) { " DPI=$($t.dpiScale)%" } else { "" }
    Write-Host "模板 '$($r.name)' 已保存到 $($r.monitorName)" -ForegroundColor Green
    Write-Host "  配置: $($t.width)x$($t.height) @ $($t.refreshRate)Hz${dpi}" -ForegroundColor Gray
    if ($r.dpiPreserved) {
        Write-Host "  当前缩放比例暂时无法读取，已保留该模板原有的 $($t.dpiScale)% 缩放" -ForegroundColor Yellow
    }
    Write-Host ""
}

function Apply-Template {
    param([string]$MonitorSpec, [string]$TemplateName)
    if (-not $MonitorSpec -or -not $TemplateName) {
        Write-Host "错误: 用法 apply <显示器序号/ID> <模板名>" -ForegroundColor Red
        Write-Host "示例: .\MonitorManager.ps1 apply 1 工作" -ForegroundColor Gray
        $script:CommandExitCode = 2
        return
    }
    Write-Host "正在应用模板 '$TemplateName' 到 '$MonitorSpec'..." -ForegroundColor Cyan
    try {
        $r = Apply-TemplateCore $MonitorSpec $TemplateName
    } catch {
        Write-Host "应用过程异常: $($_.Exception.Message)" -ForegroundColor Red
        $script:CommandExitCode = 1
        return
    }
    if (-not $r.success) {
        Write-Host "错误: $($r.error)" -ForegroundColor Red
        $script:CommandExitCode = 1
        return
    }
    $res = $r.result
    $ok = [bool]$r.allSuccess
    if ($ok) {
        $dpi = if ([int]$res.dpiScale -gt 0) { " DPI=$($res.dpiScale)%" } else { "" }
        Write-Host "  $($res.display) : $($res.config)${dpi} - OK" -ForegroundColor Green
    } else {
        Write-Host "  $($res.display) : $($res.config) - 部分失败" -ForegroundColor Yellow
        if (-not $res.resSuccess) { Write-Host "    分辨率: $($res.resMessage)" -ForegroundColor Yellow }
        if (-not $res.dpiSuccess) { Write-Host "    DPI: $($res.dpiMessage)" -ForegroundColor Yellow }
        $script:CommandExitCode = 2
    }
    Write-Host ""
    Write-Host $r.message -ForegroundColor $(if ($ok) { 'Green' } else { 'Yellow' })
    Write-Host ""
}

function Set-MonitorPower {
    param([string]$MonitorSpec, [ValidateSet('on', 'off')][string]$Operation)
    if ([string]::IsNullOrWhiteSpace($MonitorSpec)) {
        Write-Host "错误: 用法 $Operation <显示器序号/ID/名称>" -ForegroundColor Red
        $script:CommandExitCode = 2
        return
    }

    $result = Invoke-MonitorPowerCore -MonitorSpec $MonitorSpec -Operation $Operation
    if (-not $result.success) {
        if ($result.result -and $result.result.rollbackAttempted) {
            $rollbackText = if ($result.result.rollbackSuccess) { '回滚成功' } else { "回滚失败: $($result.result.rollbackMessage)" }
            Write-Host "  $rollbackText" -ForegroundColor $(if ($result.result.rollbackSuccess) { 'Yellow' } else { 'Red' })
        }
        # 错误原因保持为最后一行，GUI 后台进程可以稳定提取，不会误把“回滚成功”显示成失败原因。
        Write-Host "错误: $($result.error)" -ForegroundColor Red
        $script:CommandExitCode = if ($result.alreadySet) { 2 } else { 1 }
        return
    }

    $actionText = if ($Operation -eq 'on') { '连接' } else { '断开' }
    Write-Host "显示器 '$($result.monitorName)' 已${actionText}；当前活动显示器: $($result.activeCount) 台" -ForegroundColor Green
    Write-Host "POWER_OK: $($result.monitorName) $Operation"
}

function Show-Templates {
    param([string]$MonitorSpec)
    $templates = Load-Templates
    $connectedMonitors = Get-Monitors
    $monitors = @(Get-TemplateMonitorEntries -Monitors $connectedMonitors -Templates $templates)
    Write-Host ""
    Write-Host "=== 已保存的模板 ===" -ForegroundColor Cyan
    Write-Host ""

    # 按显示器分组显示
    $displayMonitors = @()
    if ($MonitorSpec) {
        $m = Resolve-Monitor -Spec $MonitorSpec -Monitors $monitors
        if ($m) { $displayMonitors = @($m) }
        else { Write-Host "  未找到显示器 '$MonitorSpec'" -ForegroundColor Red; $script:CommandExitCode = 1; return }
    } else {
        $displayMonitors = @($monitors)
    }

    if ($displayMonitors.Count -eq 0) {
        Write-Host "  没有已连接显示器或已保存的模板组" -ForegroundColor Yellow
        return
    }

    $idx = 1
    foreach ($m in $displayMonitors) {
        $primary = if ($m.IsPrimary) { " (主)" } else { "" }
        $state = if (Test-MonitorIsActive $m) { $m.DisplayName } elseif ($m.IsConnected) { "已断开" } else { "系统未检测到" }
        Write-Host "[$idx] $state$primary  ($($m.MonitorName))" -ForegroundColor Yellow
        Write-Host "    ID: $($m.MonitorId)" -ForegroundColor DarkGray
        $mTemplates = @(Get-MonitorTemplates -MonitorId $m.MonitorId -Templates $templates)
        if ($mTemplates.Count -eq 0) {
            Write-Host "    (无模板)" -ForegroundColor Gray
        } else {
            foreach ($t in $mTemplates) {
                $dpi = if ([int]$t.dpiScale -gt 0) { " DPI=$($t.dpiScale)%" } else { "" }
                Write-Host "    - $($t.name): $($t.width)x$($t.height)@$($t.refreshRate)Hz${dpi}  ($($t.created))" -ForegroundColor White
            }
        }
        Write-Host ""
        $idx++
    }
}

function Show-Template {
    param([string]$MonitorSpec, [string]$TemplateName)
    if (-not $MonitorSpec -or -not $TemplateName) {
        Write-Host "错误: 用法 show <显示器序号/ID> <模板名>" -ForegroundColor Red
        $script:CommandExitCode = 2
        return
    }
    $templates = Load-Templates
    $connectedMonitors = Get-Monitors
    $monitors = @(Get-TemplateMonitorEntries -Monitors $connectedMonitors -Templates $templates)
    $target = Resolve-Monitor -Spec $MonitorSpec -Monitors $monitors
    if (-not $target) { Write-Host "错误: 未找到显示器或离线模板组 '$MonitorSpec'" -ForegroundColor Red; $script:CommandExitCode = 1; return }

    $mTemplates = @(Get-MonitorTemplates -MonitorId $target.MonitorId -Templates $templates)
    $t = $mTemplates | Where-Object { $_.name -eq $TemplateName } | Select-Object -First 1
    if (-not $t) { Write-Host "错误: 显示器 '$($target.DisplayName)' 下未找到模板 '$TemplateName'" -ForegroundColor Red; $script:CommandExitCode = 1; return }

    Write-Host ""
    Write-Host "=== 模板详情 ===" -ForegroundColor Cyan
    $state = if (Test-MonitorIsActive $target) { $target.DisplayName } elseif ($target.IsConnected) { '已断开' } else { '系统未检测到' }
    Write-Host "  显示器:   $state ($($target.MonitorName))" -ForegroundColor Yellow
    Write-Host "  设备 ID:  $($target.MonitorId)"
    Write-Host "  模板名:   $($t.name)"
    Write-Host "  创建时间: $($t.created)"
    Write-Host "  分辨率:   $($t.width) x $($t.height)"
    Write-Host "  刷新率:   $($t.refreshRate) Hz"
    Write-Host "  颜色深度: $($t.bitsPerPel) bit"
    $dpiDisplay = if ([int]$t.dpiScale -gt 0) { "$($t.dpiScale)%" } else { "未保存" }
    Write-Host "  缩放比例: $dpiDisplay"
    Write-Host ""
}

function Remove-Template {
    param([string]$MonitorSpec, [string]$TemplateName)
    if (-not $MonitorSpec -or -not $TemplateName) {
        Write-Host "错误: 用法 delete <显示器序号/ID> <模板名>" -ForegroundColor Red
        $script:CommandExitCode = 2
        return
    }
    $r = Delete-TemplateCore $MonitorSpec $TemplateName
    if (-not $r.success) {
        Write-Host "错误: $($r.error)" -ForegroundColor Red
        $script:CommandExitCode = 1
        return
    }
    Write-Host "模板 '$TemplateName' 已删除" -ForegroundColor Green
}

function Show-Menu {
    $monitors = Get-Monitors
    if ($monitors.Count -eq 0) {
        Write-Host "未检测到显示器" -ForegroundColor Yellow
        $script:CommandExitCode = 1
        return
    }
    while ($true) {
        Write-Host ""
        Write-Host "=== 快速切换（按显示器选择模板）===" -ForegroundColor Cyan
        $i = 1
        foreach ($m in $monitors) {
            $primary = if ($m.IsPrimary) { " (主)" } else { "" }
            Write-Host ("  {0}. {1}{2}  ({3}x{4}@{5}Hz)" -f $i, $m.DisplayName, $primary, $m.Width, $m.Height, $m.RefreshRate)
            $i++
        }
        Write-Host "  0. 退出"
        Write-Host ""

        $choice = Read-Host "选择显示器"
        if ($choice -eq "0" -or $choice -eq "q" -or [string]::IsNullOrWhiteSpace($choice)) { return }

        $target = $null
        $idx = 0
        if ([int]::TryParse($choice, [ref]$idx) -and $idx -ge 1 -and $idx -le $monitors.Count) {
            $target = $monitors[$idx - 1]
        }
        if (-not $target) {
            Write-Host "无效选择" -ForegroundColor Red
            continue
        }

        $templates = Load-Templates
        $mTemplates = @(Get-MonitorTemplates -MonitorId $target.MonitorId -Templates $templates)
        if ($mTemplates.Count -eq 0) {
            Write-Host "  显示器 '$($target.DisplayName)' 下无模板" -ForegroundColor Yellow
            continue
        }

        Write-Host ""
        Write-Host "=== $($target.DisplayName) 的模板 ===" -ForegroundColor Cyan
        $j = 1
        foreach ($t in $mTemplates) {
            $dpi = if ([int]$t.dpiScale -gt 0) { " DPI=$($t.dpiScale)%" } else { "" }
            Write-Host ("  {0}. {1}  ({2}x{3}@{4}Hz{5})" -f $j, $t.name, $t.width, $t.height, $t.refreshRate, $dpi)
            $j++
        }
        Write-Host "  0. 返回"
        Write-Host ""

        $tc = Read-Host "选择模板"
        if ($tc -eq "0" -or $tc -eq "q") { continue }
        $tidx = 0
        if ([int]::TryParse($tc, [ref]$tidx) -and $tidx -ge 1 -and $tidx -le $mTemplates.Count) {
            Apply-Template $target.MonitorId $mTemplates[$tidx - 1].name
        } else {
            Write-Host "无效选择" -ForegroundColor Red
        }
    }
}

# ============================================================
#  GUI（WinForms 原生窗口）
# ============================================================

function Show-Gui {
    Add-Type -AssemblyName System.Drawing

    # ===== 圆角辅助函数 =====
    function Set-RoundedRegion {
        param($Control, [int]$Radius)
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $w = $Control.Width
        $h = $Control.Height
        $r = $Radius
        $d = $r * 2
        # AddArc 的 width/height 是弧的包围椭圆尺寸，需用 2*R 才能得到半径 R 的圆角
        if ($d -gt $w) { $d = $w; $r = [int]($w / 2) }
        if ($d -gt $h) { $d = $h; $r = [int]($h / 2) }
        $path.AddArc(0, 0, $d, $d, 180, 90)
        $path.AddArc($w - $d, 0, $d, $d, 270, 90)
        $path.AddArc($w - $d, $h - $d, $d, $d, 0, 90)
        $path.AddArc(0, $h - $d, $d, $d, 90, 90)
        $path.CloseAllFigures()
        $Control.Region = New-Object System.Drawing.Region($path)
        $path.Dispose()
    }

    # ===== 配色方案（设计稿风格：深色侧栏 + 浅色主区）=====
    $cBg          = [System.Drawing.Color]::FromArgb(248, 250, 252)   # #f8fafc 主区背景
    $cSidebar     = [System.Drawing.Color]::FromArgb(15, 23, 42)      # #0f172a 侧栏背景
    $cStatusbar   = [System.Drawing.Color]::FromArgb(30, 41, 59)      # #1e293b 状态栏背景
    $cCard        = [System.Drawing.Color]::White                      # #ffffff 卡片背景
    $cCardBd      = [System.Drawing.Color]::FromArgb(226, 232, 240)   # #e2e8f0 卡片边框
    $cCardHv      = [System.Drawing.Color]::FromArgb(248, 250, 252)   # #f8fafc 悬浮背景
    $cCardSelBd   = [System.Drawing.Color]::FromArgb(59, 130, 246)    # #3b82f6 选中边框
    $cMonCardSel  = [System.Drawing.Color]::FromArgb(59, 130, 246)    # 选中主色（左边框）
    $cMonCardSelBg= [System.Drawing.Color]::FromArgb(30, 58, 138)     # 选中半透明背景 (近似 rgba(59,130,246,0.12))
    $cText        = [System.Drawing.Color]::FromArgb(15, 23, 42)      # #0f172a 主文字
    $cTextSec     = [System.Drawing.Color]::FromArgb(71, 85, 105)     # #475569 次要文字
    $cTextTh      = [System.Drawing.Color]::FromArgb(148, 163, 184)   # #94a3b8 辅助文字
    $cTextInv     = [System.Drawing.Color]::White                      # 反白文字
    $cTextInvSec  = [System.Drawing.Color]::FromArgb(203, 213, 225)   # #cbd5e1 侧栏次要文字
    $cTextInvTh   = [System.Drawing.Color]::FromArgb(148, 163, 184)   # #94a3b8 侧栏辅助文字
    $cAccent      = [System.Drawing.Color]::FromArgb(59, 130, 246)    # #3b82f6 主题蓝
    $cAccentDk    = [System.Drawing.Color]::FromArgb(37, 99, 235)     # #2563eb 深蓝
    $cSuccess     = [System.Drawing.Color]::FromArgb(22, 163, 74)     # #16a34a 成功绿
    $cSuccessDk   = [System.Drawing.Color]::FromArgb(21, 128, 61)     # #166534 深绿
    $cDanger      = [System.Drawing.Color]::FromArgb(220, 38, 38)     # #dc2626 危险红
    $cDangerBg    = [System.Drawing.Color]::FromArgb(254, 242, 242)   # #fef2f2 浅红背景
    $cDangerBd    = [System.Drawing.Color]::FromArgb(254, 202, 202)   # #fecaca 浅红边框
    $cWarn        = [System.Drawing.Color]::FromArgb(251, 191, 36)    # #fbbf24 警告黄
    $cInput       = [System.Drawing.Color]::FromArgb(241, 245, 249)   # #f1f5f9 输入框背景
    $cSidebarHv   = [System.Drawing.Color]::FromArgb(30, 41, 59)      # #1e293b 侧栏悬浮
    $cSidebarNum  = [System.Drawing.Color]::FromArgb(51, 65, 85)      # #334155 侧栏序号背景
    $cPreviewGrad1= [System.Drawing.Color]::FromArgb(30, 58, 95)      # #1e3a5f 预览渐变1
    $cPreviewGrad2= [System.Drawing.Color]::FromArgb(59, 31, 94)      # #3b1f5e 预览渐变2
    $cPreviewStand= [System.Drawing.Color]::FromArgb(203, 213, 225)   # #cbd5e1 底座颜色
    $cBadgeBg     = [System.Drawing.Color]::FromArgb(241, 245, 249)   # #f1f5f9 标签背景
    $cBadgeFg     = [System.Drawing.Color]::FromArgb(71, 85, 105)     # #475569 标签文字
    $cDivider     = [System.Drawing.Color]::FromArgb(241, 245, 249)   # #f1f5f9 分隔线

    # DPI 缩放因子（基于 96 DPI 基准）
    # 优先使用 GetDpiForSystem 获取 per-monitor DPI（最准确）
    # 级联检测：GetDpiForSystem → SystemInformation → 注册表 → 默认 96
    $dpiX = 0; $dpiY = 0
    try { $dpiX = [DpiAwareness]::GetDpiForSystem(); $dpiY = $dpiX } catch {}
    if ($dpiX -le 0) {
        $dpiX = [System.Windows.Forms.SystemInformation]::Dpi.X
        $dpiY = [System.Windows.Forms.SystemInformation]::Dpi.Y
    }
    if ($dpiX -le 0) {
        $dpiX = (Get-ItemProperty 'HKCU:\Control Panel\Desktop' -Name 'LogPixels' -ErrorAction SilentlyContinue).LogPixels
        if (-not $dpiX) { $dpiX = 96 }; $dpiY = $dpiX
    }
    $dpiScale = [double]$dpiY / 96.0

    # PER_MONITOR_AWARE_V2 模式下，字体 emSize 是逻辑单位，WinForms 渲染时会自动按 DPI 放大
    # 因此字体保持设计时逻辑值不变，只缩放容器尺寸
    # 所有控件复用这一组字体；窗口退出后统一 Dispose，避免反复刷新卡片时累积 GDI 句柄。
    $fontTiny       = New-Object System.Drawing.Font('Microsoft YaHei UI', 8)
    $fontBase       = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
    $fontBaseBold   = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Bold)
    $fontTitle      = New-Object System.Drawing.Font('Microsoft YaHei UI', 16, [System.Drawing.FontStyle]::Bold)
    $fontSub        = New-Object System.Drawing.Font('Microsoft YaHei UI', 10, [System.Drawing.FontStyle]::Bold)
    $fontMini       = New-Object System.Drawing.Font('Microsoft YaHei UI', 7.5)
    $fontMiniBold   = New-Object System.Drawing.Font('Microsoft YaHei UI', 7.5, [System.Drawing.FontStyle]::Bold)
    $fontMiniB      = New-Object System.Drawing.Font('Microsoft YaHei UI', 8, [System.Drawing.FontStyle]::Bold)
    $fontSymbol     = New-Object System.Drawing.Font('Segoe UI Symbol', 8)
    $sharedFonts = @($fontTiny, $fontBase, $fontBaseBold, $fontTitle, $fontSub, $fontMini, $fontMiniBold, $fontMiniB, $fontSymbol)

    # 事件处理器会被 GetNewClosure 放入独立动态模块；用闭包脚本块保存对话框及其 UI 依赖，
    # 避免运行时无法解析 Show-RenameMonitorDialog 这样的局部函数名。
    $showRenameMonitorDialog = {
        param($Owner, [string]$CurrentName)

        $dlg = New-Object System.Windows.Forms.Form
        $dlg.Text = '重命名显示器'
        $dlg.StartPosition = 'CenterParent'
        $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        $dlg.MaximizeBox = $false
        $dlg.MinimizeBox = $false
        $dlg.ShowInTaskbar = $false
        $dlg.BackColor = $cBg
        $dlg.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
        $dlg.ClientSize = New-Object System.Drawing.Size([int](380 * $dpiScale), [int](150 * $dpiScale))

        $label = New-Object System.Windows.Forms.Label
        $label.Text = '输入新名称（留空并确定可恢复系统默认名称）：'
        $label.Font = $fontBase
        $label.ForeColor = $cText
        $label.AutoSize = $true
        $label.Location = New-Object System.Drawing.Point([int](20 * $dpiScale), [int](18 * $dpiScale))
        $dlg.Controls.Add($label)

        $textBox = New-Object System.Windows.Forms.TextBox
        $textBox.Font = $fontBase
        $textBox.Text = $CurrentName
        $textBox.MaxLength = 100
        $textBox.Location = New-Object System.Drawing.Point([int](20 * $dpiScale), [int](48 * $dpiScale))
        $textBox.Size = New-Object System.Drawing.Size([int](340 * $dpiScale), [int](25 * $dpiScale))
        $dlg.Controls.Add($textBox)

        $ok = New-Object System.Windows.Forms.Button
        $ok.Text = '确定'
        $ok.Font = $fontBase
        $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $ok.Size = New-Object System.Drawing.Size([int](80 * $dpiScale), [int](30 * $dpiScale))
        $ok.Location = New-Object System.Drawing.Point([int](190 * $dpiScale), [int](96 * $dpiScale))
        $dlg.Controls.Add($ok)

        $cancel = New-Object System.Windows.Forms.Button
        $cancel.Text = '取消'
        $cancel.Font = $fontBase
        $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $cancel.Size = New-Object System.Drawing.Size([int](80 * $dpiScale), [int](30 * $dpiScale))
        $cancel.Location = New-Object System.Drawing.Point([int](280 * $dpiScale), [int](96 * $dpiScale))
        $dlg.Controls.Add($cancel)

        $dlg.AcceptButton = $ok
        $dlg.CancelButton = $cancel
        $dlg.Add_Shown({ $textBox.Focus(); $textBox.SelectAll() })
        try {
            $dialogResult = $dlg.ShowDialog($Owner)
            return [PSCustomObject]@{ Accepted = ($dialogResult -eq [System.Windows.Forms.DialogResult]::OK); Text = $textBox.Text }
        } finally {
            $dlg.Dispose()
        }
    }.GetNewClosure()
    $form = New-Object System.Windows.Forms.Form
    $form.Text = '显示器配置管理'
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'Sizable'
    $form.MaximizeBox = $true
    $form.Font = $fontBase
    $form.BackColor = $cBg
    $form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None

    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea

    # 窗口尺寸：设计基准 1100×720，按 DPI 缩放
    $baseW = [int](1100 * $dpiScale)
    $baseH = [int](720 * $dpiScale)
    $maxW = [int]($screen.Width * 0.80)
    $maxH = [int]($screen.Height * 0.85)
    if ($baseW -gt $maxW) { $baseW = $maxW }
    if ($baseH -gt $maxH) { $baseH = $maxH }
    $minW = [int](900 * $dpiScale)
    $minH = [int](600 * $dpiScale)
    $form.ClientSize = New-Object System.Drawing.Size($baseW, $baseH)
    $form.MinimumSize = New-Object System.Drawing.Size($minW, $minH)

    # ===== 底部状态栏 =====
    $statusBar = New-Object System.Windows.Forms.StatusStrip
    $statusBar.Dock = 'Bottom'
    $statusBar.BackColor = $cStatusbar
    $statusBar.SizingGrip = $false
    $statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
    $statusLabel.Text = '就绪'
    $statusLabel.ForeColor = $cTextInvTh
    $statusLabel.BackColor = $cStatusbar
    [void]$statusBar.Items.Add($statusLabel)
    $form.Controls.Add($statusBar)

    # ===== 主内容区：左右分栏 =====
    $rootLayout = New-Object System.Windows.Forms.TableLayoutPanel
    $rootLayout.Dock = 'Fill'
    $rootLayout.ColumnCount = 2
    $rootLayout.RowCount = 1
    $sideWidth = [int](260 * $dpiScale)
    if ($sideWidth -lt [int](240 * $dpiScale)) { $sideWidth = [int](240 * $dpiScale) }
    if ($sideWidth -gt [int](320 * $dpiScale)) { $sideWidth = [int](320 * $dpiScale) }
    $rootLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, $sideWidth)))
    $rootLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    $rootLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    $rootLayout.Padding = New-Object System.Windows.Forms.Padding(0)
    $rootLayout.BackColor = $cBg
    $form.Controls.Add($rootLayout)

    # ===== 左侧栏：当前显示器（设计稿风格）=====
    $sidebar = New-Object System.Windows.Forms.Panel
    $sidebar.Dock = 'Fill'
    $sidebar.BackColor = $cSidebar

    # 显示器卡片容器（FlowLayoutPanel 自动纵向堆叠）- 最先添加（Dock=Fill）
    $monFlow = New-Object System.Windows.Forms.FlowLayoutPanel
    $monFlow.Dock = 'Fill'
    $monFlow.FlowDirection = 'TopDown'
    $monFlow.WrapContents = $false
    $monFlow.AutoScroll = $true
    $monFlow.BackColor = $cSidebar
    $monFlow.Padding = New-Object System.Windows.Forms.Padding([int](12 * $dpiScale), [int](12 * $dpiScale), [int](12 * $dpiScale), [int](8 * $dpiScale))
    $monFlow.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'Instance, NonPublic').SetValue($monFlow, $true)
    $sidebar.Controls.Add($monFlow)

    # 侧栏顶部：标题栏（最后添加，Dock=Top 优先）
    $sidebarTop = New-Object System.Windows.Forms.Panel
    $sidebarTop.Dock = 'Top'
    $sidebarTop.Height = [int](56 * $dpiScale)
    $sidebarTop.BackColor = $cSidebar
    $sidebarTop.Padding = New-Object System.Windows.Forms.Padding([int](16 * $dpiScale), 0, [int](16 * $dpiScale), 0)
    $sidebar.Controls.Add($sidebarTop)

    # 标题文字
    $sidebarTitle = New-Object System.Windows.Forms.Label
    $sidebarTitle.Text = '显示器配置管理'
    $sidebarTitle.Font = $fontBaseBold
    $sidebarTitle.ForeColor = $cTextInv
    $sidebarTitle.AutoSize = $true
    $sidebarTitle.Location = New-Object System.Drawing.Point([int](16 * $dpiScale), [int](20 * $dpiScale))
    $sidebarTop.Controls.Add($sidebarTitle)

    # 侧栏底部：版本号（Dock=Bottom）
    $sidebarBottom = New-Object System.Windows.Forms.Panel
    $sidebarBottom.Dock = 'Bottom'
    $sidebarBottom.Height = [int](40 * $dpiScale)
    $sidebarBottom.BackColor = $cSidebar
    $sidebar.Controls.Add($sidebarBottom)

    $verLabel = New-Object System.Windows.Forms.Label
    $verLabel.Text = 'v1.0.0'
    $verLabel.Font = $fontTiny
    $verLabel.ForeColor = [System.Drawing.Color]::FromArgb(71, 85, 105)
    $verLabel.AutoSize = $true
    $verLabel.Location = New-Object System.Drawing.Point([int](16 * $dpiScale), [int](12 * $dpiScale))
    $sidebarBottom.Controls.Add($verLabel)

    $rootLayout.Controls.Add($sidebar, 0, 0)

    # ===== 右侧主区：模板卡片网格（设计稿风格）=====
    $mainArea = New-Object System.Windows.Forms.Panel
    $mainArea.Dock = 'Fill'
    $mainArea.BackColor = $cBg

    # 模板卡片 FlowLayoutPanel（自动换行排列）- Dock=Fill 最先添加
    $tplFlow = New-Object System.Windows.Forms.FlowLayoutPanel
    $tplFlow.Dock = 'Fill'
    $tplFlow.FlowDirection = 'LeftToRight'
    $tplFlow.WrapContents = $true
    $tplFlow.AutoScroll = $true
    $tplFlow.BackColor = $cBg
    $tplFlow.Padding = New-Object System.Windows.Forms.Padding([int](28 * $dpiScale), [int](24 * $dpiScale), [int](28 * $dpiScale), [int](24 * $dpiScale))
    $tplFlow.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'Instance, NonPublic').SetValue($tplFlow, $true)
    $mainArea.Controls.Add($tplFlow)

    # 顶部标题 + 按钮栏（Dock=Top 最后添加） - 设计稿风格：底部边框 + 面包屑标题
    $topBar = New-Object System.Windows.Forms.Panel
    $topBar.Dock = 'Top'
    $topBar.Height = [int](72 * $dpiScale)
    $topBar.BackColor = $cBg
    $topBar.Padding = New-Object System.Windows.Forms.Padding([int](28 * $dpiScale), 0, [int](28 * $dpiScale), 0)

    # 底部分隔线
    $topDivider = New-Object System.Windows.Forms.Panel
    $topDivider.Dock = 'Bottom'
    $topDivider.Height = 1
    $topDivider.BackColor = $cCardBd
    $topBar.Controls.Add($topDivider)

    # 右侧按钮 FlowLayoutPanel
    $btnFlow = New-Object System.Windows.Forms.FlowLayoutPanel
    $btnFlow.Dock = 'Right'
    $btnFlow.Width = [int](340 * $dpiScale)
    $btnFlow.FlowDirection = 'RightToLeft'
    $btnFlow.WrapContents = $false
    $btnFlow.BackColor = $cBg
    $btnFlow.Padding = New-Object System.Windows.Forms.Padding(0, [int](20 * $dpiScale), 0, 0)
    $topBar.Controls.Add($btnFlow)

    # 退出按钮（设计稿：白底灰边 + 圆角7px）
    $closeBtn = New-Object System.Windows.Forms.Button
    $closeBtn.Text = '退出'
    $closeBtn.Font = $fontBase
    $closeBtn.FlatStyle = 'Flat'
    $closeBtn.BackColor = $cCard
    $closeBtn.ForeColor = $cTextTh
    $closeBtn.Cursor = 'Hand'
    $closeBtn.FlatAppearance.BorderSize = 1
    $closeBtn.FlatAppearance.BorderColor = $cCardBd
    $closeBtn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(248, 250, 252)
    $btnH = [int](34 * $dpiScale)
    $closeBtn.Size = New-Object System.Drawing.Size([int](80 * $dpiScale), $btnH)
    $closeBtn.Margin = New-Object System.Windows.Forms.Padding([int](10 * $dpiScale), 0, 0, 0)
    $closeBtn.Add_HandleCreated({ Set-RoundedRegion -Control $this -Radius ([int](7 * $dpiScale)) })
    $btnFlow.Controls.Add($closeBtn)

    # 删除按钮（设计稿：浅红底红边 + 圆角7px）
    $deleteBtn = New-Object System.Windows.Forms.Button
    $deleteBtn.Text = '删除'
    $deleteBtn.Font = $fontBase
    $deleteBtn.FlatStyle = 'Flat'
    $deleteBtn.BackColor = $cDangerBg
    $deleteBtn.ForeColor = $cDanger
    $deleteBtn.Cursor = 'Hand'
    $deleteBtn.FlatAppearance.BorderSize = 1
    $deleteBtn.FlatAppearance.BorderColor = $cDangerBd
    $deleteBtn.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(254, 226, 226)
    $deleteBtn.Enabled = $false
    $deleteBtn.Size = New-Object System.Drawing.Size([int](80 * $dpiScale), $btnH)
    $deleteBtn.Margin = New-Object System.Windows.Forms.Padding([int](10 * $dpiScale), 0, 0, 0)
    $deleteBtn.Add_HandleCreated({ Set-RoundedRegion -Control $this -Radius ([int](7 * $dpiScale)) })
    $btnFlow.Controls.Add($deleteBtn)

    # 应用模板按钮（设计稿：绿底白字 + 圆角7px）
    $applyBtn = New-Object System.Windows.Forms.Button
    $applyBtn.Text = '应用模板'
    $applyBtn.Font = $fontBase
    $applyBtn.FlatStyle = 'Flat'
    $applyBtn.BackColor = $cSuccess
    $applyBtn.ForeColor = $cTextInv
    $applyBtn.Cursor = 'Hand'
    $applyBtn.FlatAppearance.BorderSize = 0
    $applyBtn.FlatAppearance.MouseOverBackColor = $cSuccessDk
    $applyBtn.Size = New-Object System.Drawing.Size([int](100 * $dpiScale), $btnH)
    $applyBtn.Margin = New-Object System.Windows.Forms.Padding(0)
    $applyBtn.Add_HandleCreated({ Set-RoundedRegion -Control $this -Radius ([int](7 * $dpiScale)) })
    $btnFlow.Controls.Add($applyBtn)

    # 左侧标题区：面包屑 + 主标题
    $titlePanel = New-Object System.Windows.Forms.Panel
    $titlePanel.Dock = 'Fill'
    $titlePanel.BackColor = $cBg
    $topBar.Controls.Add($titlePanel)

    # 面包屑（显示器名）
    $crumbLbl = New-Object System.Windows.Forms.Label
    $crumbLbl.Text = '显示器'
    $crumbLbl.Font = $fontBase
    $crumbLbl.ForeColor = $cTextTh
    $crumbLbl.AutoSize = $true
    $crumbLbl.Location = New-Object System.Drawing.Point(0, [int](20 * $dpiScale))
    $crumbLbl.BackColor = $cBg
    $titlePanel.Controls.Add($crumbLbl)

    # 主标题
    $mainTitle = New-Object System.Windows.Forms.Label
    $mainTitle.Text = '配置模板'
    $mainTitle.Font = $fontTitle
    $mainTitle.ForeColor = $cText
    $mainTitle.AutoSize = $true
    $mainTitle.Location = New-Object System.Drawing.Point(0, [int](38 * $dpiScale))
    $mainTitle.BackColor = $cBg
    $titlePanel.Controls.Add($mainTitle)

    $mainArea.Controls.Add($topBar)
    $rootLayout.Controls.Add($mainArea, 1, 0)

    # ===== 绘制迷你显示器图形（设计稿风格：渐变背景）=====
    function New-MonitorPreview {
        param(
            [int]$Width, [int]$Height, [int]$Refresh, [int]$Dpi, [bool]$IsPrimary,
            [string]$Name, [int]$AvailableWidth
        )
        # 计算缩略屏尺寸（保持比例，宽度自适应）
        $maxW = [int][Math]::Min([int]($AvailableWidth - [int](32 * $dpiScale)), [int](200 * $dpiScale))
        if ($maxW -lt [int](100 * $dpiScale)) { $maxW = [int](100 * $dpiScale) }
        $ratio = if ($Width -gt 0 -and $Height -gt 0) { [double]$Width / [double]$Height } else { 1.6 }
        # 极端但可解析的宽高值也不能产生零尺寸或超大预览控件。
        if ($ratio -lt 0.2) { $ratio = 0.2 }
        if ($ratio -gt 8.0) { $ratio = 8.0 }
        $scrW = [int]$maxW
        $scrH = [Math]::Max(1, [int]($scrW / $ratio))
        $maxH = [int](90 * $dpiScale)
        if ($scrH -gt $maxH) { $scrH = $maxH; $scrW = [Math]::Max(1, [int]($scrH * $ratio)) }

        $containerH = [int]($scrH + [int](20 * $dpiScale))

        # 捕获闭包变量
        $capScrW = $scrW; $capScrH = $scrH
        $capWidth = $Width; $capHeight = $Height
        $capRefresh = $Refresh; $capDpi = $Dpi
        $capPreviewGrad1 = $cPreviewGrad1; $capPreviewGrad2 = $cPreviewGrad2
        $capPreviewStand = $cPreviewStand
        $capDpiScale = $dpiScale
        $capFontMiniB = $fontMiniB; $capFontMini = $fontMini

        $container = New-Object System.Windows.Forms.Panel
        $container.Size = New-Object System.Drawing.Size($AvailableWidth, $containerH)

        $container.Add_Paint({
            $g = $_.Graphics
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

            $centerX = [int](($_.ClipRectangle.Width - $capScrW) / 2)
            $scrX = $centerX
            $scrY = 0

            # 渐变屏幕主体（135度渐变：#1e3a5f → #3b1f5e）
            $scrRect = New-Object System.Drawing.Rectangle($scrX, $scrY, $capScrW, $capScrH)
            $gradBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
                $scrRect,
                $capPreviewGrad1,
                $capPreviewGrad2,
                [System.Drawing.Drawing2D.LinearGradientMode]::ForwardDiagonal
            )
            $g.FillRectangle($gradBrush, $scrRect)
            $gradBrush.Dispose()

            # 分辨率文字（居中上半部分）
            $resText = "${capWidth}x${capHeight}"
            $resBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
            $resFont = New-Object System.Drawing.Font('Microsoft YaHei UI', 8, [System.Drawing.FontStyle]::Bold)
            $resSz = $g.MeasureString($resText, $resFont)
            $resX = $scrX + ($capScrW - $resSz.Width) / 2
            $resY = $scrY + ($capScrH * 0.35) - ($resSz.Height / 2)
            $g.DrawString($resText, $resFont, $resBrush, [float]$resX, [float]$resY)
            $resBrush.Dispose(); $resFont.Dispose()

            # 刷新率文字（居中下半部分）
            $refText = "@ ${capRefresh}Hz"
            $refBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 255, 255, 180))
            $refFont = New-Object System.Drawing.Font('Microsoft YaHei UI', 7)
            $refSz = $g.MeasureString($refText, $refFont)
            $refX = $scrX + ($capScrW - $refSz.Width) / 2
            $refY = $scrY + ($capScrH * 0.65) - ($refSz.Height / 2)
            $g.DrawString($refText, $refFont, $refBrush, [float]$refX, [float]$refY)
            $refBrush.Dispose(); $refFont.Dispose()

            # 底座
            $standW = [int]($capScrW * 0.25)
            $standX = $scrX + ($capScrW - $standW) / 2
            $standY = $scrY + $capScrH + [int](2 * $capDpiScale)
            $standRect = New-Object System.Drawing.Rectangle($standX, $standY, $standW, [int](4 * $capDpiScale))
            $standBrush = New-Object System.Drawing.SolidBrush($capPreviewStand)
            $g.FillRectangle($standBrush, $standRect)
            $standBrush.Dispose()
        }.GetNewClosure())

        return $container
    }

    # ===== 创建模板卡片（设计稿风格）=====
    function New-TemplateCard {
        param($Template, [int]$CardWidth, [bool]$IsPrimary)

        $pad = [int](16 * $dpiScale)
        $headH = [int](46 * $dpiScale)
        $cardHeight = [int](240 * $dpiScale)

        $card = New-Object System.Windows.Forms.Panel
        $card.Size = New-Object System.Drawing.Size($CardWidth, $cardHeight)
        $card.BackColor = $cCard
        $card.Padding = New-Object System.Windows.Forms.Padding(2)
        $card.Cursor = 'Hand'
        # Tag 只保存结构化状态，避免模板名与内部 add/-hover 标记冲突
        $card.Tag = [PSCustomObject]@{
            Kind      = 'template'
            Name      = [string]$Template.name
            IsSelected = ($script:selectedTemplate -eq [string]$Template.name)
        }
        # 双缓冲消除重绘闪烁
        $card.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'Instance, NonPublic').SetValue($card, $true)

        # 用 Paint 事件绘制圆角背景 + 边框 + 阴影（设计稿风格）
        $capDpiScale = $dpiScale
        $capCardSelBd = $cCardSelBd
        $capCardBd = $cCardBd
        $capCard = $cCard
        $card.BackColor = [System.Drawing.Color]::Transparent
        $card.Add_Paint({
            $g = $_.Graphics
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $tagInfo = $this.Tag
            $isSelected = [bool]$tagInfo.IsSelected
            $borderColor = if ($isSelected) { $capCardSelBd } else { $capCardBd }
            $borderWidth = if ($isSelected) { 2 } else { 1 }
            $bgColor = $capCard
            $w = $this.Width - 1
            $h = $this.Height - 1
            $r = [int](12 * $capDpiScale)

            # 阴影（底部偏移1px，透明度6%）
            $shadowRect = New-Object System.Drawing.Rectangle(1, 1, $w, $h)
            $shadowBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(15, 0, 0, 0))
            $shadowPath = New-Object System.Drawing.Drawing2D.GraphicsPath
            $sd = $r * 2
            $shadowPath.AddArc($shadowRect.X, $shadowRect.Y, $sd, $sd, 180, 90)
            $shadowPath.AddArc($shadowRect.X + $shadowRect.Width - $sd, $shadowRect.Y, $sd, $sd, 270, 90)
            $shadowPath.AddArc($shadowRect.X + $shadowRect.Width - $sd, $shadowRect.Y + $shadowRect.Height - $sd, $sd, $sd, 0, 90)
            $shadowPath.AddArc($shadowRect.X, $shadowRect.Y + $shadowRect.Height - $sd, $sd, $sd, 90, 90)
            $shadowPath.CloseAllFigures()
            $g.FillPath($shadowBrush, $shadowPath)
            $shadowBrush.Dispose(); $shadowPath.Dispose()

            # 圆角背景 + 边框（用两层FillPath模拟，比Pen更可靠）
            $bgRect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)

            # 外层：边框色
            $borderBrush = New-Object System.Drawing.SolidBrush($borderColor)
            $outerPath = New-Object System.Drawing.Drawing2D.GraphicsPath
            $od = $r * 2
            $outerPath.AddArc($bgRect.X, $bgRect.Y, $od, $od, 180, 90)
            $outerPath.AddArc($bgRect.X + $bgRect.Width - $od, $bgRect.Y, $od, $od, 270, 90)
            $outerPath.AddArc($bgRect.X + $bgRect.Width - $od, $bgRect.Y + $bgRect.Height - $od, $od, $od, 0, 90)
            $outerPath.AddArc($bgRect.X, $bgRect.Y + $bgRect.Height - $od, $od, $od, 90, 90)
            $outerPath.CloseAllFigures()
            $g.FillPath($borderBrush, $outerPath)
            $borderBrush.Dispose()
            $outerPath.Dispose()

            # 内层：背景色（向内缩进borderWidth，露出外层的边）
            $innerRect = New-Object System.Drawing.Rectangle($borderWidth, $borderWidth, ($w - $borderWidth * 2), ($h - $borderWidth * 2))
            $innerR = [Math]::Max(0, ($r - $borderWidth))
            $innerD = $innerR * 2
            $bgBrush = New-Object System.Drawing.SolidBrush($bgColor)
            $innerPath = New-Object System.Drawing.Drawing2D.GraphicsPath
            $innerPath.AddArc($innerRect.X, $innerRect.Y, $innerD, $innerD, 180, 90)
            $innerPath.AddArc($innerRect.X + $innerRect.Width - $innerD, $innerRect.Y, $innerD, $innerD, 270, 90)
            $innerPath.AddArc($innerRect.X + $innerRect.Width - $innerD, $innerRect.Y + $innerRect.Height - $innerD, $innerD, $innerD, 0, 90)
            $innerPath.AddArc($innerRect.X, $innerRect.Y + $innerRect.Height - $innerD, $innerD, $innerD, 90, 90)
            $innerPath.CloseAllFigures()
            $g.FillPath($bgBrush, $innerPath)
            $bgBrush.Dispose()
            $innerPath.Dispose()

            # 选中态右上角蓝色圆点
            if ($isSelected) {
                $dotSize = [int](8 * $capDpiScale)
                $dotX = $this.Width - [int](10 * $capDpiScale) - $dotSize
                $dotY = [int](10 * $capDpiScale)
                $dotBrush = New-Object System.Drawing.SolidBrush($capCardSelBd)
                $g.FillEllipse($dotBrush, $dotX, $dotY, $dotSize, $dotSize)
                $dotBrush.Dispose()
            }
        }.GetNewClosure())

        # 卡片头部：模板名 + 创建时间
        $head = New-Object System.Windows.Forms.Panel
        $head.Size = New-Object System.Drawing.Size(($CardWidth - $pad * 2), $headH)
        $head.Location = New-Object System.Drawing.Point($pad, 0)
        $head.BackColor = [System.Drawing.Color]::Transparent
        $card.Controls.Add($head)

        $nameLbl = New-Object System.Windows.Forms.Label
        $nameLbl.Text = $Template.name
        $nameLbl.Font = $fontSub
        $nameLbl.ForeColor = $cText
        $nameLbl.AutoSize = $true
        $nameLbl.BackColor = [System.Drawing.Color]::Transparent
        $nameLbl.Location = New-Object System.Drawing.Point(0, [int](14 * $dpiScale))
        $head.Controls.Add($nameLbl)

        $dateLbl = New-Object System.Windows.Forms.Label
        $dateLbl.Text = $Template.created
        $dateLbl.Font = $fontTiny
        $dateLbl.ForeColor = $cTextTh
        $dateLbl.AutoSize = $true
        $dateLbl.BackColor = [System.Drawing.Color]::Transparent
        $dateLbl.Location = New-Object System.Drawing.Point(($CardWidth - $pad * 2 - [int](130 * $dpiScale)), [int](16 * $dpiScale))
        $head.Controls.Add($dateLbl)

        # 分隔线
        $divider = New-Object System.Windows.Forms.Panel
        $divider.Size = New-Object System.Drawing.Size(($CardWidth - $pad * 2), 1)
        $divider.Location = New-Object System.Drawing.Point($pad, $headH)
        $divider.BackColor = $cDivider
        $card.Controls.Add($divider)

        # 预览区背景（浅灰）
        $previewY = $headH + [int](12 * $dpiScale)
        $previewH = [int](110 * $dpiScale)
        $previewBg = New-Object System.Windows.Forms.Panel
        $previewBg.Size = New-Object System.Drawing.Size(($CardWidth - [int](4 * $dpiScale)), $previewH)
        $previewBg.Location = New-Object System.Drawing.Point([int](2 * $dpiScale), $previewY)
        $previewBg.BackColor = $cBg
        $card.Controls.Add($previewBg)

        # 显示器预览（居中）
        $preview = New-MonitorPreview `
            -Width ([int]$Template.width) -Height ([int]$Template.height) `
            -Refresh ([int]$Template.refreshRate) -Dpi ([int]$Template.dpiScale) `
            -IsPrimary $IsPrimary `
            -Name '' `
            -AvailableWidth ($CardWidth - [int](32 * $dpiScale))
        $preview.Location = New-Object System.Drawing.Point([int](16 * $dpiScale), [int](12 * $dpiScale))
        $preview.BackColor = $cBg
        $previewBg.Controls.Add($preview)

        # 底部胶囊标签
        $badgeY = $previewY + $previewH + [int](10 * $dpiScale)
        $badgeFont = $fontMini
        $badgePadX = [int](10 * $dpiScale)
        $badgePadY = [int](3 * $dpiScale)
        $badgeH = [int](20 * $dpiScale)
        $badgeR = [int]($badgeH / 2)

        # 色深标签
        $bitsText = "色深 $([int]$Template.bitsPerPel) bit"
        $bitsSz = [System.Windows.Forms.TextRenderer]::MeasureText($bitsText, $badgeFont)
        $bitsW = $bitsSz.Width + $badgePadX * 2
        $bitsBadge = New-Object System.Windows.Forms.Label
        $bitsBadge.Text = $bitsText
        $bitsBadge.Font = $badgeFont
        $bitsBadge.ForeColor = $cBadgeFg
        $bitsBadge.BackColor = $cBadgeBg
        $bitsBadge.AutoSize = $false
        $bitsBadge.Size = New-Object System.Drawing.Size($bitsW, $badgeH)
        $bitsBadge.Location = New-Object System.Drawing.Point($pad, $badgeY)
        $bitsBadge.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        Set-RoundedRegion -Control $bitsBadge -Radius $badgeR
        $card.Controls.Add($bitsBadge)

        # 缩放标签
        if ([int]$Template.dpiScale -gt 0) {
            $dpiText = "缩放 $([int]$Template.dpiScale)%"
            $dpiSz = [System.Windows.Forms.TextRenderer]::MeasureText($dpiText, $badgeFont)
            $dpiW = $dpiSz.Width + $badgePadX * 2
            $dpiBadge = New-Object System.Windows.Forms.Label
            $dpiBadge.Text = $dpiText
            $dpiBadge.Font = $badgeFont
            $dpiBadge.ForeColor = $cBadgeFg
            $dpiBadge.BackColor = $cBadgeBg
            $dpiBadge.AutoSize = $false
            $dpiBadge.Size = New-Object System.Drawing.Size($dpiW, $badgeH)
            $dpiBadge.Location = New-Object System.Drawing.Point(($pad + $bitsW + [int](8 * $dpiScale)), $badgeY)
            $dpiBadge.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
            Set-RoundedRegion -Control $dpiBadge -Radius $badgeR
            $card.Controls.Add($dpiBadge)
        }

        # ===== 点击/悬浮事件 =====
        $clickAction = {
            $cardObj = if ($this -is [System.Windows.Forms.Panel] -and $this.Tag -is [PSCustomObject] -and $this.Tag.Kind -eq 'template') { $this } else { $this.Parent }
            while ($cardObj -and -not ($cardObj -is [System.Windows.Forms.Panel] -and $cardObj.Tag -is [PSCustomObject] -and $cardObj.Tag.Kind -eq 'template')) {
                $cardObj = $cardObj.Parent
            }
            if (-not $cardObj) { return }
            $script:selectedTemplate = [string]$cardObj.Tag.Name
            $script:selectedTemplateMonitorId = if ($script:selectedMonitor) { [string]$script:selectedMonitor.MonitorId } else { $null }
            $canApply = $script:selectedMonitor -and (Test-MonitorIsActive $script:selectedMonitor) -and -not $applyUiState.InProgress
            $applyBtn.Enabled = [bool]$canApply
            $deleteBtn.Enabled = $true
            $parent = $cardObj.Parent
            foreach ($c in $parent.Controls) {
                if ($c -is [System.Windows.Forms.Panel] -and $c.Tag -is [PSCustomObject] -and $c.Tag.Kind -eq 'template') {
                    $newSelected = ([string]$c.Tag.Name -eq [string]$cardObj.Tag.Name)
                    if ([bool]$c.Tag.IsSelected -ne $newSelected) {
                        $c.Tag.IsSelected = $newSelected
                        $c.Invalidate()
                    }
                }
            }
        }

        $capApplyBtn = $applyBtn
        $dblClickAction = {
            $capApplyBtn.PerformClick()
        }.GetNewClosure()

        $card.Add_Click($clickAction)
        $card.Add_DoubleClick($dblClickAction)

        # 模板卡片没有悬浮视觉变化，只绑定点击；避免鼠标经过内部子控件时重复重绘。
        foreach ($ctrl in $card.Controls) {
            $ctrl.Add_Click($clickAction)
            $ctrl.Add_DoubleClick($dblClickAction)
            if ($ctrl -is [System.Windows.Forms.Panel]) {
                foreach ($inner in $ctrl.Controls) {
                    $inner.Add_Click($clickAction)
                    $inner.Add_DoubleClick($dblClickAction)
                }
            }
        }

        return $card
    }

    # 统一更新显示器卡片的选中视觉，点击后无需重建整个列表。
    function Set-MonitorCardVisualState {
        param($Card, [bool]$IsSelected)
        if (-not $Card -or -not ($Card.Tag -is [PSCustomObject]) -or $Card.Tag.Kind -ne 'monitor') { return }

        $state = $Card.Tag
        $state.IsSelected = $IsSelected
        if ($IsSelected) { $state.IsHovered = $false }

        if ($state.Badge) {
            $state.Badge.BackColor = if ($IsSelected) { $cAccent } else { $cSidebarNum }
            $state.Badge.ForeColor = if ($IsSelected) { $cTextInv } else { $cTextInvTh }
        }
        if ($state.NameLabel) {
            $state.NameLabel.Font = if ($IsSelected) { $fontBaseBold } else { $fontBase }
            $state.NameLabel.ForeColor = if ($IsSelected) { $cTextInv } else { $cTextInvSec }
        }
        if ($state.ConfigLabel) {
            $state.ConfigLabel.ForeColor = if ($IsSelected) { $cTextInvTh } else { [System.Drawing.Color]::FromArgb(100, 116, 139) }
        }
        if ($state.SelectedLabel) {
            $state.SelectedLabel.Visible = $IsSelected
        }
        $Card.Invalidate()
    }

    # ===== 创建侧栏显示器卡片（设计稿风格）=====
    function New-CurrentMonitorCard {
        param($Monitor, [int]$AvailableWidth, [int]$Index, [bool]$IsSelected)

        $cardPad = [int](12 * $dpiScale)
        $cardH = [int](72 * $dpiScale)
        $leftBorderW = [int](3 * $dpiScale)

        # 卡片容器（透明背景，Paint 事件绘制圆角）
        $card = New-Object System.Windows.Forms.Panel
        $card.Width = $AvailableWidth
        $card.Height = $cardH
        $card.Cursor = 'Hand'
        $card.Tag = [PSCustomObject]@{
            Kind          = 'monitor'
            MonitorId     = [string]$Monitor.MonitorId
            IsSelected    = $IsSelected
            IsHovered     = $false
            Badge         = $null
            NameLabel     = $null
            ConfigLabel   = $null
            SelectedLabel = $null
            PowerButton   = $null
        }
        $card.BackColor = [System.Drawing.Color]::Transparent
        $card.Padding = New-Object System.Windows.Forms.Padding(0)
        # 双缓冲消除重绘闪烁
        $card.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'Instance, NonPublic').SetValue($card, $true)

        # Paint 事件绘制圆角背景 + 左边框
        # 将外部变量捕获为局部变量，确保 .GetNewClosure() 能正确绑定
        $capLeftBorderW = $leftBorderW
        $capDpiScale = $dpiScale
        $capSidebar   = $cSidebar
        $capMonCardSelBg = $cMonCardSelBg
        $capMonCardSel   = $cMonCardSel
        $capSidebarHv    = $cSidebarHv
        $card.Add_Paint({
            $g = $_.Graphics
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $w = $this.Width - 1
            $h = $this.Height - 1
            $r = [int](8 * $capDpiScale)

            # 确定背景色（根据选中/悬浮态）
            $bgColor = $capSidebar
            $leftBorderColor = [System.Drawing.Color]::Transparent
            $state = $this.Tag
            $isHover = ($state -is [PSCustomObject] -and [bool]$state.IsHovered)
            $isSelected = ($state -is [PSCustomObject] -and [bool]$state.IsSelected)

            # 选中态判断
            if ($isSelected) {
                $bgColor = $capMonCardSelBg
                $leftBorderColor = $capMonCardSel
            }
            # 悬浮态判断（未选中时）
            elseif ($isHover) {
                $bgColor = $capSidebarHv
            }

            # 圆角背景
            $bgRect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
            $bgBrush = New-Object System.Drawing.SolidBrush($bgColor)
            $bgPath = New-Object System.Drawing.Drawing2D.GraphicsPath
            $bd = $r * 2
            $bgPath.AddArc($bgRect.X, $bgRect.Y, $bd, $bd, 180, 90)
            $bgPath.AddArc($bgRect.X + $bgRect.Width - $bd, $bgRect.Y, $bd, $bd, 270, 90)
            $bgPath.AddArc($bgRect.X + $bgRect.Width - $bd, $bgRect.Y + $bgRect.Height - $bd, $bd, $bd, 0, 90)
            $bgPath.AddArc($bgRect.X, $bgRect.Y + $bgRect.Height - $bd, $bd, $bd, 90, 90)
            $bgPath.CloseAllFigures()
            $g.FillPath($bgBrush, $bgPath)
            $bgBrush.Dispose()

            # 选中卡片增加完整蓝色描边，避免只靠背景色造成状态不明显。
            if ($isSelected) {
                $outlineW = [Math]::Max(1.0, 1.2 * $capDpiScale)
                $outlinePen = New-Object System.Drawing.Pen($capMonCardSel, [single]$outlineW)
                $g.DrawPath($outlinePen, $bgPath)
                $outlinePen.Dispose()
            }

            # 左边框（3px 蓝色，只在左侧画一个圆角矩形条）
            if ($leftBorderColor -ne [System.Drawing.Color]::Transparent) {
                $lbW = $capLeftBorderW
                $lbRect = New-Object System.Drawing.Rectangle(0, 0, $lbW, $h)
                $lbBrush = New-Object System.Drawing.SolidBrush($leftBorderColor)
                $lbPath = New-Object System.Drawing.Drawing2D.GraphicsPath
                # 左侧两个圆角（使用独立小半径，避免弧超出边框宽度）
                $lbR = [int][Math]::Min($r, $lbW)
                $lbD = $lbR * 2
                $lbPath.AddArc($lbRect.X, $lbRect.Y, $lbD, $lbD, 180, 90)
                $lbPath.AddLine($lbD, 0, $lbW, 0)
                $lbPath.AddLine($lbW, 0, $lbW, $h)
                $lbPath.AddLine($lbW, $h, $lbD, $h)
                $lbPath.AddArc($lbRect.X, $lbRect.Y + $lbRect.Height - $lbD, $lbD, $lbD, 90, 90)
                $lbPath.CloseAllFigures()
                $g.FillPath($lbBrush, $lbPath)
                $lbBrush.Dispose(); $lbPath.Dispose()
            }

            $bgPath.Dispose()
        }.GetNewClosure())

        # 内容区（带左边距）
        $contentW = $AvailableWidth - $cardPad * 2
        $contentPanel = New-Object System.Windows.Forms.Panel
        $contentPanel.Dock = 'Fill'
        $contentPanel.Padding = New-Object System.Windows.Forms.Padding($cardPad, [int](10 * $dpiScale), $cardPad, [int](10 * $dpiScale))
        $contentPanel.BackColor = [System.Drawing.Color]::Transparent
        $card.Controls.Add($contentPanel)

        $displayTitle = if ($Monitor.MonitorName) { $Monitor.MonitorName } else { $Monitor.DisplayName }

        # ===== 第一行：序号徽章 + 显示器名 + 星标 + 铅笔 =====
        $topRow = New-Object System.Windows.Forms.Panel
        $topRow.Dock = 'Top'
        $topRow.Height = [int](24 * $dpiScale)
        $topRow.BackColor = [System.Drawing.Color]::Transparent
        $contentPanel.Controls.Add($topRow)

        # 序号徽章
        $numBadge = New-Object System.Windows.Forms.Label
        $numBadge.Text = [string]$Index
        $numBadge.Font = $fontMiniBold
        $numBadge.AutoSize = $false
        $numBadge.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $numBadge.Size = New-Object System.Drawing.Size([int](22 * $dpiScale), [int](18 * $dpiScale))
        $numBadge.Location = New-Object System.Drawing.Point(0, [int](2 * $dpiScale))
        if ($IsSelected) {
            $numBadge.BackColor = $cAccent
            $numBadge.ForeColor = $cTextInv
        } else {
            $numBadge.BackColor = $cSidebarNum
            $numBadge.ForeColor = $cTextInvTh
        }
        Set-RoundedRegion -Control $numBadge -Radius ([int](9 * $dpiScale))
        $topRow.Controls.Add($numBadge)

        # 显示器名称
        $nameLbl = New-Object System.Windows.Forms.Label
        $nameLbl.Text = $displayTitle
        if ($IsSelected) {
            $nameLbl.Font = $fontBaseBold
            $nameLbl.ForeColor = $cTextInv
        } else {
            $nameLbl.Font = $fontBase
            $nameLbl.ForeColor = $cTextInvSec
        }
        $nameLbl.AutoSize = $true
        $nameLbl.BackColor = [System.Drawing.Color]::Transparent
        $nameLbl.Location = New-Object System.Drawing.Point([int](30 * $dpiScale), [int](2 * $dpiScale))
        $topRow.Controls.Add($nameLbl)

        # 主显示器星标
        if ($Monitor.IsPrimary) {
            $starLbl = New-Object System.Windows.Forms.Label
            $starLbl.Text = [char]0x2605
            $starLbl.Font = $fontSymbol
            $starLbl.ForeColor = $cWarn
            $starLbl.AutoSize = $true
            $starLbl.BackColor = [System.Drawing.Color]::Transparent
            $nameTextSz = [System.Windows.Forms.TextRenderer]::MeasureText($displayTitle, $nameLbl.Font)
            $starX = [int](30 * $dpiScale) + $nameTextSz.Width + [int](4 * $dpiScale)
            $starLbl.Location = New-Object System.Drawing.Point($starX, [int](3 * $dpiScale))
            $topRow.Controls.Add($starLbl)
        }

        # 编辑按钮（铅笔）
        $renameBtn = New-Object System.Windows.Forms.Label
        $renameBtn.Text = [char]0x270E
        $renameBtn.Font = $fontSymbol
        $renameBtn.ForeColor = $cTextInvTh
        $renameBtn.BackColor = [System.Drawing.Color]::Transparent
        $renameBtn.AutoSize = $true
        $renameBtn.Cursor = 'Hand'
        $renameBtn.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $renameBtn.Size = New-Object System.Drawing.Size([int](16 * $dpiScale), [int](16 * $dpiScale))
        $renameBtn.Location = New-Object System.Drawing.Point(($contentW - [int](16 * $dpiScale)), [int](2 * $dpiScale))
        $renameBtn.Visible = [bool]$Monitor.IsConnected
        $topRow.Controls.Add($renameBtn)

        # 单屏连接开关：绿色表示已加入桌面，灰色表示已从 Windows 桌面断开。
        $powerBtn = New-Object System.Windows.Forms.Label
        $powerBtn.Text = [char]0x23FB
        $powerBtn.Font = $fontSymbol
        $powerBtn.ForeColor = if (Test-MonitorIsActive $Monitor) { [System.Drawing.Color]::FromArgb(74, 222, 128) } else { $cTextInvTh }
        $powerBtn.BackColor = [System.Drawing.Color]::Transparent
        $powerBtn.AutoSize = $false
        $powerBtn.Cursor = 'Hand'
        $powerBtn.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $powerBtn.Size = New-Object System.Drawing.Size([int](20 * $dpiScale), [int](20 * $dpiScale))
        $powerBtn.Location = New-Object System.Drawing.Point(($contentW - [int](44 * $dpiScale)), 0)
        $powerBtn.Visible = [bool]$Monitor.IsConnected
        $powerBtn.AccessibleName = if (Test-MonitorIsActive $Monitor) { '断开此显示器' } else { '连接此显示器' }
        $topRow.Controls.Add($powerBtn)

        # 明确的选中标识；与描边、左侧高亮共同形成稳定的多重反馈。
        $selectedLbl = New-Object System.Windows.Forms.Label
        $selectedLbl.Text = '已选'
        $selectedLbl.Font = $fontMiniBold
        $selectedLbl.ForeColor = $cTextInv
        $selectedLbl.BackColor = $cAccent
        $selectedLbl.AutoSize = $false
        $selectedLbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $selectedLbl.Size = New-Object System.Drawing.Size([int](38 * $dpiScale), [int](18 * $dpiScale))
        $selectedRightSpace = if ($Monitor.IsConnected) { [int](82 * $dpiScale) } else { [int](40 * $dpiScale) }
        $selectedLbl.Location = New-Object System.Drawing.Point(($contentW - $selectedRightSpace), [int](2 * $dpiScale))
        $selectedLbl.Visible = $IsSelected
        Set-RoundedRegion -Control $selectedLbl -Radius ([int](9 * $dpiScale))
        $topRow.Controls.Add($selectedLbl)

        # ===== 第二行：配置信息 =====
        $dpiStr = if ([int]$Monitor.DpiScale -gt 0) { " · $($Monitor.DpiScale)%" } else { "" }
        $cfgRow = New-Object System.Windows.Forms.Panel
        $cfgRow.Dock = 'Top'
        $cfgRow.Height = [int](20 * $dpiScale)
        $cfgRow.BackColor = [System.Drawing.Color]::Transparent
        $contentPanel.Controls.Add($cfgRow)

        $cfgLbl = New-Object System.Windows.Forms.Label
        $cfgLbl.Text = if (Test-MonitorIsActive $Monitor) {
            "$($Monitor.Width) x $($Monitor.Height) @ $($Monitor.RefreshRate)Hz${dpiStr}"
        } elseif ($Monitor.IsConnected) {
            '已断开 · 点击电源按钮可重新连接'
        } else {
            '系统未检测到 · 仅管理已保存模板'
        }
        $cfgLbl.Font = $fontMini
        if ($IsSelected) {
            $cfgLbl.ForeColor = $cTextInvTh
        } else {
            $cfgLbl.ForeColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
        }
        $cfgLbl.AutoSize = $true
        $cfgLbl.BackColor = [System.Drawing.Color]::Transparent
        $cfgLbl.Location = New-Object System.Drawing.Point([int](30 * $dpiScale), 0)
        $cfgRow.Controls.Add($cfgLbl)

        $card.Tag.Badge = $numBadge
        $card.Tag.NameLabel = $nameLbl
        $card.Tag.ConfigLabel = $cfgLbl
        $card.Tag.SelectedLabel = $selectedLbl
        $card.Tag.PowerButton = $powerBtn

        # 把变量捕获到闭包中
        $capMonitorId = $Monitor.MonitorId
        $capTargetKey = if ($Monitor.IsConnected) { Get-MonitorTargetKey $Monitor } else { $null }
        $capMonitorName = $Monitor.MonitorName
        $capRefreshMon = $refreshMonitors
        $capRefreshTpl = $refreshTemplates
        $capCard = $card
        $capShowRenameMonitorDialog = $showRenameMonitorDialog

        $renameBtn.Add_Click({
            $renameInput = & $capShowRenameMonitorDialog -Owner $capCard.FindForm() -CurrentName $capMonitorName
            if (-not $renameInput.Accepted) { return }
            $trimmedName = ([string]$renameInput.Text).Trim()
            $renameResult = Set-MonitorCustomName -MonitorId $capMonitorId -CustomName $trimmedName
            if (-not $renameResult.success) {
                [void][System.Windows.Forms.MessageBox]::Show(
                    $capCard.FindForm(),
                    $renameResult.error,
                    '重命名失败',
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                )
                return
            }
            & $capRefreshMon
            # RefreshMonitors 会按 MonitorId 保留并更新当前选择；随后始终重建模板区，
            # 避免在 GetNewClosure 的独立模块中读写 $script: 状态。
            & $capRefreshTpl
        }.GetNewClosure())

        # 编辑按钮悬浮效果
        $renameHoverFg = $cTextInv
        $renameLeaveFg = $cTextInvTh
        $renameBtn.Add_MouseEnter({
            $this.ForeColor = $renameHoverFg
        }.GetNewClosure())
        $renameBtn.Add_MouseLeave({
            $this.ForeColor = $renameLeaveFg
        }.GetNewClosure())

        $powerNormalFg = $powerBtn.ForeColor
        $powerHoverFg = $cTextInv
        $powerBtn.Add_MouseEnter({ $this.ForeColor = $powerHoverFg }.GetNewClosure())
        $powerBtn.Add_MouseLeave({ $this.ForeColor = $powerNormalFg }.GetNewClosure())
        $powerBtn.Add_Click({
            $ownerForm = $capCard.FindForm()
            if ($ownerForm -and $ownerForm.Tag -is [hashtable] -and $ownerForm.Tag.ContainsKey('PowerAction')) {
                & $ownerForm.Tag.PowerAction $capMonitorId $capTargetKey
            }
        }.GetNewClosure())

        # ===== 卡片点击/悬浮效果（通过Parent链查找卡片，与模板卡片一致）=====
        $clickAction = {
            $cardObj = $this
            while ($cardObj -and -not ($cardObj -is [System.Windows.Forms.Panel] -and $cardObj.Tag -is [PSCustomObject] -and $cardObj.Tag.Kind -eq 'monitor')) {
                if ($cardObj -is [System.Windows.Forms.FlowLayoutPanel]) { break }
                $cardObj = $cardObj.Parent
            }
            if (-not $cardObj -or -not ($cardObj.Tag -is [PSCustomObject])) { return }
            $monitorId = [string]$cardObj.Tag.MonitorId
            if ([string]::IsNullOrWhiteSpace($monitorId)) { return }

            # 设置选中的显示器
            $script:selectedMonitor = $script:monitors | Where-Object { $_.MonitorId -eq $monitorId } | Select-Object -First 1
            if (-not $script:selectedMonitor) { return }

            # 刷新所有显示器卡片的选中态
            $parent = $cardObj.Parent
            if ($parent) {
                foreach ($c in $parent.Controls) {
                    if ($c -is [System.Windows.Forms.Panel] -and $c.Tag -is [PSCustomObject] -and $c.Tag.Kind -eq 'monitor') {
                        Set-MonitorCardVisualState -Card $c -IsSelected ([string]$c.Tag.MonitorId -eq $monitorId)
                    }
                }
            }

            # 调用刷新模板列表（从Form.Tag获取）
            $form = $cardObj.FindForm()
            if ($form -and $form.Tag -is [hashtable] -and $form.Tag.ContainsKey('RefreshTemplates')) {
                & $form.Tag.RefreshTemplates
            }
        }

        $enterAction = {
            $cardObj = $this
            while ($cardObj -and -not ($cardObj -is [System.Windows.Forms.Panel] -and $cardObj.Tag -is [PSCustomObject] -and $cardObj.Tag.Kind -eq 'monitor')) {
                if ($cardObj -is [System.Windows.Forms.FlowLayoutPanel]) { break }
                $cardObj = $cardObj.Parent
            }
            if (-not $cardObj -or -not ($cardObj.Tag -is [PSCustomObject]) -or $cardObj.Tag.IsSelected) { return }
            if (-not $cardObj.Tag.IsHovered) {
                $cardObj.Tag.IsHovered = $true
                $cardObj.Invalidate()
            }
        }

        $leaveAction = {
            $cardObj = $this
            while ($cardObj -and -not ($cardObj -is [System.Windows.Forms.Panel] -and $cardObj.Tag -is [PSCustomObject] -and $cardObj.Tag.Kind -eq 'monitor')) {
                if ($cardObj -is [System.Windows.Forms.FlowLayoutPanel]) { break }
                $cardObj = $cardObj.Parent
            }
            if (-not $cardObj -or -not ($cardObj.Tag -is [PSCustomObject])) { return }
            # 检查鼠标是否还在卡片内（子控件间移动时不触发悬浮消失，避免闪烁）
            $mousePos = $cardObj.PointToClient([System.Windows.Forms.Control]::MousePosition)
            if ($cardObj.ClientRectangle.Contains($mousePos)) { return }
            if ($cardObj.Tag.IsHovered) {
                $cardObj.Tag.IsHovered = $false
                $cardObj.Invalidate()
            }
        }

        $card.Add_Click($clickAction)
        $card.Add_MouseEnter($enterAction)
        $card.Add_MouseLeave($leaveAction)

        # 子控件绑定点击和悬浮事件（leave中增加鼠标位置检查，避免闪烁）
        foreach ($ctrl in $contentPanel.Controls) {
            if ($ctrl -ne $renameBtn -and $ctrl -ne $powerBtn) {
                $ctrl.Add_Click($clickAction)
                $ctrl.Add_MouseEnter($enterAction)
                $ctrl.Add_MouseLeave($leaveAction)
            }
        }
        foreach ($ctrl in $topRow.Controls) {
            if ($ctrl -ne $renameBtn -and $ctrl -ne $powerBtn) {
                $ctrl.Add_Click($clickAction)
                $ctrl.Add_MouseEnter($enterAction)
                $ctrl.Add_MouseLeave($leaveAction)
            }
        }
        foreach ($ctrl in $cfgRow.Controls) {
            if ($ctrl -ne $renameBtn -and $ctrl -ne $powerBtn) {
                $ctrl.Add_Click($clickAction)
                $ctrl.Add_MouseEnter($enterAction)
                $ctrl.Add_MouseLeave($leaveAction)
            }
        }

        Set-MonitorCardVisualState -Card $card -IsSelected $IsSelected
        return $card
    }

    # ===== 状态变量 =====
    $script:templates = $null
    $script:monitors = @()
    $script:selectedMonitor = $null
    $script:selectedTemplate = $null
    $script:selectedTemplateMonitorId = $null
    # GetNewClosure 会创建独立动态模块，不能依赖其中的 $script: 作用域与主脚本相同。
    # 路径使用不可变局部值，异步任务状态使用可变引用对象在嵌套回调间共享。
    $guiScriptPath = [string]$script:MonitorManagerScriptPath
    if ([string]::IsNullOrWhiteSpace($guiScriptPath)) { $guiScriptPath = [string]$PSCommandPath }
    $applyUiState = @{ InProgress = $false; Process = $null; Timer = $null }
    $powerUiState = @{ InProgress = $false; Process = $null; Timer = $null }
    $resizeUiState = @{ Timer = $null }

    # 该脚本块保持创建它的主脚本会话状态，供 GetNewClosure 回调安全清除选择。
    $resetTemplateSelection = {
        $script:selectedTemplate = $null
        $script:selectedTemplateMonitorId = $null
    }

    # 辅助：安全清理 FlowLayoutPanel（先复制集合再 Dispose，防止集合修改异常）
    function Clear-FlowPanel {
        param($Panel)
        $children = @($Panel.Controls)
        foreach ($c in $children) {
            try { $c.Dispose() } catch {}
        }
        $Panel.Controls.Clear()
    }

    # ===== 刷新显示器 =====
    $refreshMonitors = {
        $monFlow.SuspendLayout()
        Clear-FlowPanel $monFlow
        try {
            $connectedMonitors = Get-Monitors
            $script:templates = Load-Templates
            $script:monitors = @(Get-TemplateMonitorEntries -Monitors $connectedMonitors -Templates $script:templates)
            $sideW = [int]$monFlow.ClientSize.Width
            if ($sideW -le 0) { $sideW = [int]$monFlow.Width }

            # 默认选中：保留原选中（若仍连接），否则选主显示器，否则选第一个
            $stillConnected = $false
            if ($script:selectedMonitor) {
                $matched = $script:monitors | Where-Object { $_.MonitorId -eq $script:selectedMonitor.MonitorId } | Select-Object -First 1
                if ($matched) {
                    $stillConnected = $true
                    $script:selectedMonitor = $matched
                } elseif (Test-MonitorIsActive $script:selectedMonitor) {
                    # 分辨率切换后 MonitorId 可能变化，尝试用 DisplayName 匹配
                    $matched = $script:monitors | Where-Object { (Test-MonitorIsActive $_) -and $_.DisplayName -eq $script:selectedMonitor.DisplayName } | Select-Object -First 1
                    if ($matched) {
                        $stillConnected = $true
                        $script:selectedMonitor = $matched
                    }
                }
            }
            if (-not $stillConnected) {
                $script:selectedMonitor = $script:monitors | Where-Object { $_.IsPrimary } | Select-Object -First 1
                if (-not $script:selectedMonitor -and $script:monitors.Count -gt 0) {
                    $script:selectedMonitor = $script:monitors[0]
                }
            }

            $i = 0
            foreach ($m in $script:monitors) {
                $i++
                $isSelected = ($script:selectedMonitor -and $m.MonitorId -eq $script:selectedMonitor.MonitorId)
                $card = New-CurrentMonitorCard -Monitor $m -AvailableWidth ($sideW - [int](8 * $dpiScale)) -Index $i -IsSelected $isSelected
                $card.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, [int](8 * $dpiScale))
                $monFlow.Controls.Add($card)
            }

            $primaryMon = $connectedMonitors | Where-Object { $_.IsPrimary } | Select-Object -First 1
            $primaryStr = if ($primaryMon) { "$($primaryMon.Width)x$($primaryMon.Height) @ $($primaryMon.RefreshRate)Hz" } else { '' }
            $activeCount = @($connectedMonitors | Where-Object { Test-MonitorIsActive $_ }).Count
            $offlineCount = $script:monitors.Count - $connectedMonitors.Count
            $offlineText = if ($offlineCount -gt 0) { "  |  $offlineCount 个离线模板组" } else { '' }
            $activeText = if ($activeCount -ne $connectedMonitors.Count) { "（$activeCount 台已启用）" } else { '' }
            $statusLabel.Text = "检测到 $($connectedMonitors.Count) 台显示器${activeText}${offlineText}  |  $primaryStr"
            $statusLabel.ForeColor = $cTextInvTh
        } catch {
            $statusLabel.Text = "刷新失败: $($_.Exception.Message)"
            $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(252, 165, 165)
        } finally {
            $monFlow.ResumeLayout($true)
        }
    }

    # ===== 刷新模板列表（按选中显示器过滤）=====
    $refreshTemplates = {
        $tplFlow.SuspendLayout()
        Set-ControlRedraw -Control $tplFlow -Enabled $false
        try {
            Clear-FlowPanel $tplFlow
            $script:templates = Load-Templates
            $previousSelectedTemplate = $script:selectedTemplate
            $previousSelectedMonitorId = $script:selectedTemplateMonitorId
            $script:selectedTemplate = $null
            $applyBtn.Enabled = $false
            $deleteBtn.Enabled = $false

            if (-not $script:selectedMonitor) {
                $script:selectedTemplateMonitorId = $null
                $crumbLbl.Text = '显示器'
                $mainTitle.Text = '配置模板'
                # 每次创建新的空状态标签（旧的已被 Clear-FlowPanel dispose）
                $emptyLabel = New-Object System.Windows.Forms.Label
                $emptyLabel.Text = "未选择显示器`n`n请在左侧点击一台显示器`n以查看该显示器的模板"
                $emptyLabel.Font = $fontSub
                $emptyLabel.ForeColor = $cTextTh
                $emptyLabel.AutoSize = $true
                $emptyLabel.BackColor = $cBg
                $emptyLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
                $tplFlow.Controls.Add($emptyLabel)
                return
            }

            $monitorId = $script:selectedMonitor.MonitorId
            $monitorName = $script:selectedMonitor.MonitorName
            if (-not $monitorName) { $monitorName = $script:selectedMonitor.DisplayName }
            # 面包屑 + 主标题动态显示当前显示器名
            $crumbLbl.Text = $monitorName
            $mainTitle.Text = "$monitorName 的模板"

            $monitorTpls = @(Get-MonitorTemplates -MonitorId $monitorId -Templates $script:templates)
            $script:selectedTemplate = Get-PreferredTemplateName -Templates $script:templates -Monitor $script:selectedMonitor `
                -PreviousTemplateName $previousSelectedTemplate -PreviousMonitorId $previousSelectedMonitorId
            $script:selectedTemplateMonitorId = [string]$monitorId
            if ($script:selectedTemplate) {
                $deleteBtn.Enabled = $true
                $applyBtn.Enabled = [bool]((Test-MonitorIsActive $script:selectedMonitor) -and -not $applyUiState.InProgress)
            }
            $count = $monitorTpls.Count

        if ($count -eq 0) {
            # 每次创建新的空状态标签（旧的已被 Clear-FlowPanel dispose）
            $emptyLabel = New-Object System.Windows.Forms.Label
            $emptyLabel.Text = if (Test-MonitorIsActive $script:selectedMonitor) {
                "当前显示器暂无模板`n`n点击下方 + 卡片`n保存当前配置为模板"
            } elseif ($script:selectedMonitor.IsConnected) {
                "该显示器已从 Windows 桌面断开`n`n重新连接后可保存或应用模板"
            } else {
                "该离线显示器暂无模板"
            }
            $emptyLabel.Font = $fontSub
            $emptyLabel.ForeColor = $cTextTh
            $emptyLabel.AutoSize = $true
            $emptyLabel.BackColor = $cBg
            $emptyLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
            $tplFlow.Controls.Add($emptyLabel)
        }

        # 根据主区宽度计算卡片宽度（提取公共逻辑，避免 if/else 分支重复）
        $areaW = [int]$tplFlow.ClientSize.Width
        if ($areaW -le 0) { $areaW = [int]$tplFlow.Width }
        $cardW = [int](320 * $dpiScale)
        $gap = [int](12 * $dpiScale)
        $cols = [int](($areaW + $gap) / ($cardW + $gap))
        if ($cols -lt 1) { $cols = 1 }
        if ($cols -gt 4) { $cols = 4 }
        $cardW = [int](($areaW - $gap * ($cols - 1)) / $cols) - [int](2 * $dpiScale)
        $minCardW = [int](260 * $dpiScale)
        $maxCardW = [int](400 * $dpiScale)
        if ($cardW -lt $minCardW) { $cardW = $minCardW }
        if ($cardW -gt $maxCardW) { $cardW = $maxCardW }

        if ($count -gt 0) {
            $isPrimary = [bool]$script:selectedMonitor.IsPrimary
            foreach ($t in $monitorTpls) {
                $card = New-TemplateCard -Template $t -CardWidth $cardW -IsPrimary $isPrimary
                $card.Margin = New-Object System.Windows.Forms.Padding(0, 0, $gap, $gap)
                $tplFlow.Controls.Add($card)
            }
        }

        # 已断开或系统未检测到的显示器只能查看和删除已有模板，不能应用或保存当前配置。
        if (-not (Test-MonitorIsActive $script:selectedMonitor)) { return }

        # 添加加号卡片（设计稿风格：虚线边框 + 圆形加号 + 圆角）
        $addCardH = [int](240 * $dpiScale)
        $addCard = New-Object System.Windows.Forms.Panel
        $addCard.Size = New-Object System.Drawing.Size($cardW, $addCardH)
        $addCard.BackColor = [System.Drawing.Color]::Transparent
        $addCard.Cursor = 'Hand'
        $addCard.Tag = [PSCustomObject]@{ Kind = 'add'; IsHovered = $false }
        $addCard.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'Instance, NonPublic').SetValue($addCard, $true)

        # Paint 事件绘制圆角背景 + 虚线边框
        $capDpiScaleAdd = $dpiScale
        $addCard.Add_Paint({
            $g = $_.Graphics
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $w = $this.Width - 1
            $h = $this.Height - 1
            $r = [int](12 * $capDpiScaleAdd)

            # 悬浮时背景色
            $normalBg = [System.Drawing.Color]::FromArgb(255, 255, 255)
            $hoverBg = [System.Drawing.Color]::FromArgb(248, 250, 252)
            $bgColor = if ($this.Tag -is [PSCustomObject] -and $this.Tag.Kind -eq 'add' -and $this.Tag.IsHovered) { $hoverBg } else { $normalBg }

            # 圆角背景
            $bgRect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
            $bgBrush = New-Object System.Drawing.SolidBrush($bgColor)
            $bgPath = New-Object System.Drawing.Drawing2D.GraphicsPath
            $ad = $r * 2
            $bgPath.AddArc($bgRect.X, $bgRect.Y, $ad, $ad, 180, 90)
            $bgPath.AddArc($bgRect.X + $bgRect.Width - $ad, $bgRect.Y, $ad, $ad, 270, 90)
            $bgPath.AddArc($bgRect.X + $bgRect.Width - $ad, $bgRect.Y + $bgRect.Height - $ad, $ad, $ad, 0, 90)
            $bgPath.AddArc($bgRect.X, $bgRect.Y + $bgRect.Height - $ad, $ad, $ad, 90, 90)
            $bgPath.CloseAllFigures()
            $g.FillPath($bgBrush, $bgPath)
            $bgBrush.Dispose()

            # 虚线边框
            $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(203, 213, 225), 2)
            $pen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
            $g.DrawPath($pen, $bgPath)
            $pen.Dispose()
            $bgPath.Dispose()
        }.GetNewClosure())

        # 圆形加号背景
        $plusCircleSize = [int](48 * $dpiScale)
        $plusCircle = New-Object System.Windows.Forms.Panel
        $plusCircle.Size = New-Object System.Drawing.Size($plusCircleSize, $plusCircleSize)
        $plusCircle.Location = New-Object System.Drawing.Point([int](($cardW - $plusCircleSize) / 2), [int](($addCardH - $plusCircleSize) / 2 - [int](20 * $dpiScale)))
        $plusCircle.BackColor = $cBadgeBg
        $plusCircle.Cursor = 'Hand'
        $plusCircle.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'Instance, NonPublic').SetValue($plusCircle, $true)

        # 用 Paint 事件画圆形
        $capDpiScalePlus = $dpiScale
        $plusCircle.Add_Paint({
            $g = $_.Graphics
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $w = $this.Width - 1
            $h = $this.Height - 1
            $rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
            $brush = New-Object System.Drawing.SolidBrush($this.BackColor)
            $g.FillEllipse($brush, $rect)
            $brush.Dispose()

            # 画 + 号
            $plusColor = [System.Drawing.Color]::FromArgb(148, 163, 184)
            $pen = New-Object System.Drawing.Pen($plusColor, [float](2.5 * $capDpiScalePlus))
            $centerX = $this.Width / 2
            $centerY = $this.Height / 2
            $lineLen = [int]($this.Width * 0.35)
            $g.DrawLine($pen, ($centerX - $lineLen), $centerY, ($centerX + $lineLen), $centerY)
            $g.DrawLine($pen, $centerX, ($centerY - $lineLen), $centerX, ($centerY + $lineLen))
            $pen.Dispose()
        }.GetNewClosure())

        $addCard.Controls.Add($plusCircle)

        # 添加模板文字
        $addHint = New-Object System.Windows.Forms.Label
        $addHint.Text = '添加模板'
        $addHint.Font = $fontBase
        $addHint.ForeColor = $cTextTh
        $addHint.AutoSize = $true
        $hintSize = [System.Windows.Forms.TextRenderer]::MeasureText('添加模板', $addHint.Font)
        $addHint.Location = New-Object System.Drawing.Point([int](($cardW - $hintSize.Width) / 2), [int]($addCardH / 2 + [int](24 * $dpiScale)))
        $addHint.BackColor = [System.Drawing.Color]::Transparent
        $addHint.Cursor = 'Hand'
        $addCard.Controls.Add($addHint)

        $addClickAction = {
            $dlgW = [int](360 * $dpiScale)
            $dlgH = [int](180 * $dpiScale)
            $dlg = New-Object System.Windows.Forms.Form
            $dlg.Text = '保存模板'
            $dlg.Size = New-Object System.Drawing.Size($dlgW, $dlgH)
            $dlg.StartPosition = 'CenterParent'
            $dlg.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
            $dlg.MaximizeBox = $false
            $dlg.MinimizeBox = $false
            $dlg.BackColor = $cBg
            $dlg.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None

            $dlgPad = [int](24 * $dpiScale)
            $label = New-Object System.Windows.Forms.Label
            $label.Text = '请输入模板名称：'
            $label.Font = $fontBase
            $label.ForeColor = $cText
            $label.AutoSize = $true
            $label.Location = New-Object System.Drawing.Point($dlgPad, [int](30 * $dpiScale))
            $dlg.Controls.Add($label)

            $txtName = New-Object System.Windows.Forms.TextBox
            $txtName.Font = $fontBase
            $txtName.MaxLength = 100
            $txtName.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
            $txtName.Location = New-Object System.Drawing.Point($dlgPad, [int](60 * $dpiScale))
            $txtName.Size = New-Object System.Drawing.Size([int](300 * $dpiScale), [int](24 * $dpiScale))
            $txtName.Padding = New-Object System.Windows.Forms.Padding([int](8 * $dpiScale), 0, [int](8 * $dpiScale), 0)
            $txtName.Focus()
            $dlg.Controls.Add($txtName)

            $btnPanel = New-Object System.Windows.Forms.Panel
            $btnPanel.Dock = 'Bottom'
            $btnPanel.Height = [int](50 * $dpiScale)
            $btnPanel.BackColor = $cBg
            $dlg.Controls.Add($btnPanel)

            $cancelBtn = New-Object System.Windows.Forms.Button
            $cancelBtn.Text = '取消'
            $cancelBtn.Font = $fontBase
            $cancelBtn.FlatStyle = 'Flat'
            $cancelBtn.BackColor = $cCard
            $cancelBtn.ForeColor = $cTextSec
            $cancelBtn.Size = New-Object System.Drawing.Size([int](80 * $dpiScale), [int](32 * $dpiScale))
            $cancelBtn.Dock = 'Right'
            $cancelBtn.Margin = New-Object System.Windows.Forms.Padding([int](8 * $dpiScale), 0, [int](16 * $dpiScale), [int](8 * $dpiScale))
            $cancelBtn.FlatAppearance.BorderSize = 1
            $cancelBtn.FlatAppearance.BorderColor = $cCardBd
            $cancelBtn.Add_Click({ $dlg.Close() })
            $btnPanel.Controls.Add($cancelBtn)

            $okBtn = New-Object System.Windows.Forms.Button
            $okBtn.Text = '确定'
            $okBtn.Font = $fontBase
            $okBtn.FlatStyle = 'Flat'
            $okBtn.BackColor = $cAccent
            $okBtn.ForeColor = $cTextInv
            $okBtn.Size = New-Object System.Drawing.Size([int](80 * $dpiScale), [int](32 * $dpiScale))
            $okBtn.Dock = 'Right'
            $okBtn.Margin = New-Object System.Windows.Forms.Padding(0, 0, [int](8 * $dpiScale), [int](8 * $dpiScale))
            $okBtn.FlatAppearance.BorderSize = 0
            $okBtn.Add_Click({
                $name = $txtName.Text.Trim()
                if (-not $name) {
                    [System.Windows.Forms.MessageBox]::Show('请输入模板名称', '提示', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
                    $txtName.Focus()
                    return
                }
                if (-not $script:selectedMonitor) {
                    [System.Windows.Forms.MessageBox]::Show('请先在左侧选择一台显示器', '提示', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
                    return
                }
                $mid = $script:selectedMonitor.MonitorId
                if (-not $mid) { $mid = $script:selectedMonitor.DisplayName }
                $dlg.Close()
                try {
                    $r = Save-TemplateCore -MonitorSpec $mid -TemplateName $name
                    if ($r.success) {
                        & $showStatus "模板 '$name' 保存成功" 'success'
                        $script:selectedTemplate = $null
                        $script:selectedTemplateMonitorId = $null
                        & $refreshTemplates
                    } else {
                        & $showStatus $r.error 'error'
                    }
                } catch {
                    & $showStatus "保存失败: $($_.Exception.Message)" 'error'
                }
            })
            $btnPanel.Controls.Add($okBtn)

            $txtName.Add_KeyDown({
                if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) { $okBtn.PerformClick() }
                if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { $dlg.Close() }
            })

            [void]$dlg.ShowDialog()
            $dlg.Dispose()
        }

        # 所有相关控件共享同一个 Click 逻辑
        $addHint.Add_Click($addClickAction)
        $addCard.Add_Click($addClickAction)
        $plusCircle.Add_Click($addClickAction)

        # 悬停效果
        $capPlusCircle = $plusCircle
        $capAddHint = $addHint
        $capAddCard = $addCard
        $hoverCardBg = [System.Drawing.Color]::FromArgb(248, 250, 252)
        $hoverTextFg = [System.Drawing.Color]::FromArgb(71, 85, 105)
        $normalPlusBg = [System.Drawing.Color]::FromArgb(241, 245, 249)
        $normalTextFg = [System.Drawing.Color]::FromArgb(148, 163, 184)
        $addEnterAction = {
            if ($capAddCard.Tag.IsHovered) { return }
            $capAddCard.Tag.IsHovered = $true
            $capPlusCircle.BackColor = $hoverCardBg
            $capPlusCircle.Invalidate()
            $capAddHint.ForeColor = $hoverTextFg
            $capAddCard.Invalidate()
        }.GetNewClosure()
        $addLeaveAction = {
            $mousePos = $capAddCard.PointToClient([System.Windows.Forms.Control]::MousePosition)
            if ($capAddCard.ClientRectangle.Contains($mousePos)) { return }
            $capAddCard.Tag.IsHovered = $false
            $capPlusCircle.BackColor = $normalPlusBg
            $capPlusCircle.Invalidate()
            $capAddHint.ForeColor = $normalTextFg
            $capAddCard.Invalidate()
        }.GetNewClosure()
        $plusCircle.Add_MouseEnter($addEnterAction)
        $plusCircle.Add_MouseLeave($addLeaveAction)
        $addHint.Add_MouseEnter($addEnterAction)
        $addHint.Add_MouseLeave($addLeaveAction)
        $addCard.Add_MouseEnter($addEnterAction)
        $addCard.Add_MouseLeave($addLeaveAction)

        $addCard.Margin = New-Object System.Windows.Forms.Padding(0, 0, $gap, $gap)
        $tplFlow.Controls.Add($addCard)
        } catch {
            # 任何意外的卡片构建/绘制准备错误都留在模板区域内展示，避免冒泡到 WinForms
            # 全局未处理异常对话框，并确保用户仍可切换显示器或退出。
            $refreshError = $_.Exception.Message
            Clear-FlowPanel $tplFlow
            $script:selectedTemplate = $null
            $script:selectedTemplateMonitorId = $null
            $applyBtn.Enabled = $false
            $deleteBtn.Enabled = $false
            $errorLabel = New-Object System.Windows.Forms.Label
            $errorLabel.Text = "模板区域刷新失败`n`n$refreshError"
            $errorLabel.Font = $fontBase
            $errorLabel.ForeColor = $cDanger
            $errorLabel.AutoSize = $true
            $errorLabel.BackColor = $cBg
            $tplFlow.Controls.Add($errorLabel)
            $statusLabel.Text = "模板区域刷新失败: $refreshError"
            $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(252, 165, 165)
        } finally {
            try {
                $tplFlow.ResumeLayout($true)
            } finally {
                # 即使布局阶段异常，也必须恢复 WM_SETREDRAW，避免模板区域永久冻结。
                Set-ControlRedraw -Control $tplFlow -Enabled $true
                if (-not $tplFlow.IsDisposed) {
                    $tplFlow.Invalidate($true)
                    $tplFlow.Update()
                }
            }
        }
    }

    $showStatus = {
        param([string]$msg, [string]$type)
        $statusLabel.Text = $msg
        if ($type -eq 'error') {
            $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(252, 165, 165)
        } elseif ($type -eq 'success') {
            $statusLabel.ForeColor = [System.Drawing.Color]::FromArgb(110, 231, 183)
        } else {
            $statusLabel.ForeColor = $cTextInvSec
        }
    }

    $powerAction = {
        param([string]$MonitorId, [string]$TargetKey)
        if ($powerUiState.InProgress -or $applyUiState.InProgress) {
            & $showStatus '另一项显示操作正在进行，请稍候' ''
            return
        }
        # 不读取其他闭包中的 $script:monitors；每次点击都重新获取 Windows 当前拓扑，
        # 并优先使用物理 target key，避免 inactive/active 切换导致 MonitorId 别名变化。
        $latestMonitors = Get-Monitors
        $targetMonitor = Resolve-MonitorByTargetIdentity -Monitors $latestMonitors -MonitorId $MonitorId -TargetKey $TargetKey
        if (-not $targetMonitor -or -not $targetMonitor.IsConnected) {
            & $showStatus '系统当前未检测到该显示器，无法连接或断开' 'error'
            return
        }

        $operation = if (Test-MonitorIsActive $targetMonitor) { 'off' } else { 'on' }
        $actionText = if ($operation -eq 'off') { '断开' } else { '连接' }
        $monitorTitle = if ($targetMonitor.MonitorName) { [string]$targetMonitor.MonitorName } else { [string]$targetMonitor.DisplayName }
        if ($operation -eq 'off') {
            $activeCount = @($latestMonitors | Where-Object { Test-MonitorIsActive $_ }).Count
            if ($activeCount -le 1) {
                & $showStatus '不能断开最后一台活动显示器' 'error'
                return
            }
            $primaryWarning = if ($targetMonitor.IsPrimary) { "`n`n这是主显示器，Windows 将把主显示器迁移到其他屏幕。" } else { '' }
            $confirm = [System.Windows.Forms.MessageBox]::Show(
                $form,
                "确认断开显示器 `"$monitorTitle`"？${primaryWarning}",
                '确认断开显示器',
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            if ($confirm -ne 'Yes') { return }
        }

        $powerUiState.InProgress = $true
        $monFlow.Enabled = $false
        $tplFlow.Enabled = $false
        $applyBtn.Enabled = $false
        $deleteBtn.Enabled = $false
        & $showStatus "正在${actionText}显示器 '$monitorTitle' ..." ''

        try {
            $encodedMonitor = ConvertTo-Base64Text ([string]$targetMonitor.MonitorId)
            $powershellCommand = Get-Command 'powershell.exe' -ErrorAction SilentlyContinue
            $hostPath = if ($powershellCommand) { $powershellCommand.Source } else { (Get-Process -Id $PID).Path }
            if (-not $hostPath -or -not (Test-Path $hostPath)) { $hostPath = 'powershell.exe' }
            if ([string]::IsNullOrWhiteSpace($guiScriptPath) -or -not (Test-Path -LiteralPath $guiScriptPath)) { throw '无法获取当前脚本路径' }

            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $hostPath
            $psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$guiScriptPath`" power-worker $operation $encodedMonitor"
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true

            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $psi
            if (-not $process.Start()) { throw '无法启动后台显示器电源进程' }
            # 启动后立即登记句柄，确保后续 Timer 构造/绑定失败时 catch 仍能释放父进程句柄。
            # Dispose 不会终止子进程，显示模式验证与回滚仍会在后台安全完成。
            $powerUiState.Process = $process
            $powerWatch = [System.Diagnostics.Stopwatch]::StartNew()
            $powerLongWaitShown = $false

            $pollTimer = New-Object System.Windows.Forms.Timer
            $powerUiState.Timer = $pollTimer
            $pollTimer.Interval = 180
            $processForPower = $process
            $timerForPower = $pollTimer
            $formForPower = $form
            $monFlowForPower = $monFlow
            $tplFlowForPower = $tplFlow
            $showStatusForPower = $showStatus
            $refreshMonitorsForPower = $refreshMonitors
            $refreshTemplatesForPower = $refreshTemplates
            $operationForPower = $operation
            $actionTextForPower = $actionText
            $monitorTitleForPower = $monitorTitle
            $watchForPower = $powerWatch
            $longWaitShownForPower = $powerLongWaitShown
            $stateForPower = $powerUiState
            $pollTimer.Add_Tick({
                if (-not $processForPower.HasExited) {
                    if (-not $longWaitShownForPower -and $watchForPower.Elapsed.TotalSeconds -ge 45) {
                        $longWaitShownForPower = $true
                        & $showStatusForPower '后台操作耗时较长，正在安全等待验证/回滚；可使用退出按钮关闭窗口' ''
                    }
                    return
                }
                try {
                    $timerForPower.Stop()
                    $watchForPower.Stop()
                    $processForPower.WaitForExit()
                    $stdout = $processForPower.StandardOutput.ReadToEnd()
                    $stderr = $processForPower.StandardError.ReadToEnd()
                    $exitCode = $processForPower.ExitCode
                    $processForPower.Dispose()
                    $timerForPower.Dispose()
                    $stateForPower.Process = $null
                    $stateForPower.Timer = $null
                    $stateForPower.InProgress = $false

                    if (-not $formForPower -or $formForPower.IsDisposed) { return }
                    if ($monFlowForPower -and -not $monFlowForPower.IsDisposed) { $monFlowForPower.Enabled = $true }
                    if ($tplFlowForPower -and -not $tplFlowForPower.IsDisposed) { $tplFlowForPower.Enabled = $true }
                    & $refreshMonitorsForPower
                    & $refreshTemplatesForPower

                    if ($exitCode -eq 0) {
                        & $showStatusForPower "显示器 '$monitorTitleForPower' 已${actionTextForPower}" 'success'
                    } else {
                        $detail = Get-WorkerResultMessage -StandardOutput $stdout -StandardError $stderr -Fallback "显示器${actionTextForPower}失败"
                        & $showStatusForPower $detail 'error'
                    }
                } catch {
                    $callbackError = $_.Exception.Message
                    try { $timerForPower.Stop(); $timerForPower.Dispose() } catch {}
                    try { $processForPower.Dispose() } catch {}
                    $stateForPower.Process = $null
                    $stateForPower.Timer = $null
                    $stateForPower.InProgress = $false
                    if ($formForPower -and -not $formForPower.IsDisposed) {
                        if ($monFlowForPower -and -not $monFlowForPower.IsDisposed) { $monFlowForPower.Enabled = $true }
                        if ($tplFlowForPower -and -not $tplFlowForPower.IsDisposed) { $tplFlowForPower.Enabled = $true }
                        try { & $showStatusForPower "处理显示器电源结果失败: $callbackError" 'error' } catch {}
                    }
                }
            }.GetNewClosure())
            $pollTimer.Start()
        } catch {
            $powerUiState.InProgress = $false
            if ($powerUiState.Timer) { $powerUiState.Timer.Dispose(); $powerUiState.Timer = $null }
            if ($powerUiState.Process) {
                try { $powerUiState.Process.Dispose() } catch {}
                $powerUiState.Process = $null
            }
            $monFlow.Enabled = $true
            $tplFlow.Enabled = $true
            & $showStatus "显示器${actionText}失败: $($_.Exception.Message)" 'error'
        }
    }.GetNewClosure()

    # ===== 事件绑定 =====
    $applyBtn.Add_Click({
        if (-not $script:selectedTemplate) { return }
        if (-not $script:selectedMonitor) {
            & $showStatus '请先在左侧选择一台显示器' 'error'
            return
        }
        if (-not (Test-MonitorIsActive $script:selectedMonitor)) {
            & $showStatus '该显示器当前已断开，请先点击左侧电源按钮重新连接' 'error'
            return
        }
        $name = $script:selectedTemplate
        $monitorSpec = $script:selectedMonitor.MonitorId
        if (-not $monitorSpec) { $monitorSpec = $script:selectedMonitor.DisplayName }
        $monitorName = $script:selectedMonitor.MonitorName
        if (-not $monitorName) { $monitorName = $script:selectedMonitor.DisplayName }

        $confirm = [System.Windows.Forms.MessageBox]::Show(
            $form,
            "确认将模板 `"$name`" 应用到显示器 `"$monitorName`" ?`n`n分辨率、刷新率和缩放比例将立即生效。",
            '确认',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        if ($confirm -ne 'Yes') { return }

        $applyUiState.InProgress = $true
        $applyBtn.Enabled = $false
        $deleteBtn.Enabled = $false
        $monFlow.Enabled = $false
        $tplFlow.Enabled = $false
        & $showStatus "正在应用模板 '$name' 到 $monitorName ..." ''

        try {
            # 在独立的 PowerShell 子进程中应用；WinForms 线程只用定时器轮询，不会卡住窗口。
            $encodedMonitor = ConvertTo-Base64Text $monitorSpec
            $encodedName = ConvertTo-Base64Text $name
            $powershellCommand = Get-Command 'powershell.exe' -ErrorAction SilentlyContinue
            $hostPath = if ($powershellCommand) { $powershellCommand.Source } else { (Get-Process -Id $PID).Path }
            if (-not $hostPath -or -not (Test-Path $hostPath)) { $hostPath = 'powershell.exe' }
            if ([string]::IsNullOrWhiteSpace($guiScriptPath) -or -not (Test-Path -LiteralPath $guiScriptPath)) { throw '无法获取当前脚本路径' }

            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $hostPath
            $psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$guiScriptPath`" apply-worker $encodedMonitor $encodedName"
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true

            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $psi
            if (-not $process.Start()) { throw '无法启动后台应用进程' }
            # 与电源任务相同：尽早登记句柄，任一后续初始化步骤失败都可统一清理。
            $applyUiState.Process = $process
            $applyWatch = [System.Diagnostics.Stopwatch]::StartNew()
            $applyLongWaitShown = $false

            $pollTimer = New-Object System.Windows.Forms.Timer
            $applyUiState.Timer = $pollTimer
            $pollTimer.Interval = 150
            $processForTimer = $process
            $timerForTimer = $pollTimer
            $nameForTimer = $name
            $monitorNameForTimer = $monitorName
            # GetNewClosure 只可靠捕获当前事件作用域中的局部变量。将外层 GUI 对象显式
            # 复制到当前作用域，避免分辨率切换引发窗口重排后回调取得 $null。
            $formForTimer = $form
            $monFlowForTimer = $monFlow
            $tplFlowForTimer = $tplFlow
            $showStatusForTimer = $showStatus
            $refreshMonitorsForTimer = $refreshMonitors
            $refreshTemplatesForTimer = $refreshTemplates
            $watchForTimer = $applyWatch
            $longWaitShownForTimer = $applyLongWaitShown
            $stateForApply = $applyUiState
            $resetTemplateSelectionForTimer = $resetTemplateSelection
            $pollTimer.Add_Tick({
                if (-not $processForTimer.HasExited) {
                    if (-not $longWaitShownForTimer -and $watchForTimer.Elapsed.TotalSeconds -ge 45) {
                        $longWaitShownForTimer = $true
                        & $showStatusForTimer '后台操作耗时较长，正在安全等待验证/回滚；可使用退出按钮关闭窗口' ''
                    }
                    return
                }
                try {
                    $timerForTimer.Stop()
                    $watchForTimer.Stop()
                    $processForTimer.WaitForExit()
                    $stdout = $processForTimer.StandardOutput.ReadToEnd()
                    $stderr = $processForTimer.StandardError.ReadToEnd()
                    $exitCode = $processForTimer.ExitCode
                    $processForTimer.Dispose()
                    $timerForTimer.Dispose()
                    $stateForApply.Process = $null
                    $stateForApply.Timer = $null
                    $stateForApply.InProgress = $false

                    if (-not $formForTimer -or $formForTimer.IsDisposed) { return }
                    if ($monFlowForTimer -and -not $monFlowForTimer.IsDisposed) { $monFlowForTimer.Enabled = $true }
                    if ($tplFlowForTimer -and -not $tplFlowForTimer.IsDisposed) { $tplFlowForTimer.Enabled = $true }

                    $detail = Get-WorkerResultMessage -StandardOutput $stdout -StandardError $stderr
                    if ($exitCode -eq 0) {
                        & $showStatusForTimer "模板 '$nameForTimer' 已应用到 $monitorNameForTimer" 'success'
                        $formForTimer.Close()
                        return
                    }

                    & $resetTemplateSelectionForTimer
                    & $refreshMonitorsForTimer
                    & $refreshTemplatesForTimer
                    if ($exitCode -eq 2) {
                        $message = if ($detail) { $detail } else { '模板已部分应用，请查看当前显示设置' }
                        & $showStatusForTimer $message ''
                    } else {
                        $message = if ($detail) { $detail } else { '应用模板失败' }
                        & $showStatusForTimer $message 'error'
                    }
                } catch {
                    # 后台进程已结束；结果处理本身也不能再冒泡到 WinForms 的全局异常框。
                    $callbackError = $_.Exception.Message
                    try { $timerForTimer.Stop(); $timerForTimer.Dispose() } catch {}
                    try { $processForTimer.Dispose() } catch {}
                    $stateForApply.Process = $null
                    $stateForApply.Timer = $null
                    $stateForApply.InProgress = $false
                    if ($formForTimer -and -not $formForTimer.IsDisposed) {
                        if ($monFlowForTimer -and -not $monFlowForTimer.IsDisposed) { $monFlowForTimer.Enabled = $true }
                        if ($tplFlowForTimer -and -not $tplFlowForTimer.IsDisposed) { $tplFlowForTimer.Enabled = $true }
                        try { & $showStatusForTimer "处理应用结果失败: $callbackError" 'error' } catch {}
                    }
                }
            }.GetNewClosure())
            $pollTimer.Start()
        } catch {
            $applyUiState.InProgress = $false
            if ($applyUiState.Timer) { $applyUiState.Timer.Dispose(); $applyUiState.Timer = $null }
            if ($applyUiState.Process) {
                try { $applyUiState.Process.Dispose() } catch {}
                $applyUiState.Process = $null
            }
            $monFlow.Enabled = $true
            $tplFlow.Enabled = $true
            & $showStatus "应用失败: $($_.Exception.Message)" 'error'
            if ($script:selectedTemplate -and (Test-MonitorIsActive $script:selectedMonitor)) { $applyBtn.Enabled = $true }
            if ($script:selectedTemplate) { $deleteBtn.Enabled = $true }
        }
    })

    $deleteBtn.Add_Click({
        if (-not $script:selectedTemplate) { return }
        if (-not $script:selectedMonitor) {
            & $showStatus '请先在左侧选择一台显示器' 'error'
            return
        }
        $name = $script:selectedTemplate
        $monitorSpec = $script:selectedMonitor.MonitorId
        if (-not $monitorSpec) { $monitorSpec = $script:selectedMonitor.DisplayName }
        $monitorName = $script:selectedMonitor.MonitorName
        if (-not $monitorName) { $monitorName = $script:selectedMonitor.DisplayName }

        $confirm = [System.Windows.Forms.MessageBox]::Show(
            $form,
            "确认从显示器 `"$monitorName`" 下删除模板 `"$name`" ?",
            '确认删除',
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($confirm -ne 'Yes') { return }
        try {
            $r = Delete-TemplateCore $monitorSpec $name
            if ($r.success) {
                & $refreshMonitors
                & $refreshTemplates
                & $showStatus "模板 '$name' 已从 $monitorName 删除" 'success'
            } else {
                & $showStatus $r.error 'error'
            }
        } catch {
            & $showStatus "删除失败: $($_.Exception.Message)" 'error'
        }
    })

    # 显式捕获窗体，避免按钮事件进入独立作用域后丢失外层引用。
    $formForCloseButton = $form
    $closeBtn.Add_Click({
        if ($formForCloseButton -and -not $formForCloseButton.IsDisposed) {
            $formForCloseButton.Close()
        }
    }.GetNewClosure())

    # 窗口大小改变时重新布局模板卡片（300ms 防抖）
    $form.Add_SizeChanged({
        # 应用模板时分辨率变化会连续触发 SizeChanged；应用完成路径会自行关闭或刷新，
        # 此时不重建模板区，避免与后台完成回调交叉修改控件。
        $powerStateForResize = if ($form.Tag -is [hashtable] -and $form.Tag.ContainsKey('PowerState')) { $form.Tag.PowerState } else { $null }
        if ($applyUiState.InProgress -or ($powerStateForResize -and $powerStateForResize.InProgress) -or -not $script:templates) { return }
        if ($resizeUiState.Timer) {
            $resizeUiState.Timer.Stop()
            $resizeUiState.Timer.Dispose()
        }
        $resizeUiState.Timer = New-Object System.Windows.Forms.Timer
        $resizeUiState.Timer.Interval = 300
        $resizeTimerForTick = $resizeUiState.Timer
        $resizeStateForTick = $resizeUiState
        $refreshTemplatesForResize = $refreshTemplates
        $resizeTimerForTick.Add_Tick({
            $resizeTimerForTick.Stop()
            $resizeTimerForTick.Dispose()
            if ($resizeStateForTick.Timer -eq $resizeTimerForTick) { $resizeStateForTick.Timer = $null }
            & $refreshTemplatesForResize
        }.GetNewClosure())
        $resizeUiState.Timer.Start()
    })

    # 窗口关闭时清理 resize timer 和 script 变量
    $form.Add_FormClosed({
        if ($resizeUiState.Timer) {
            $resizeUiState.Timer.Stop()
            $resizeUiState.Timer.Dispose()
            $resizeUiState.Timer = $null
        }
        if ($applyUiState.Timer) {
            $applyUiState.Timer.Stop()
            $applyUiState.Timer.Dispose()
            $applyUiState.Timer = $null
        }
        if ($applyUiState.Process) {
            # 关闭窗口不强杀正在提交显示模式的子进程，让其完成验证和清理。
            try { $applyUiState.Process.Dispose() } catch {}
            $applyUiState.Process = $null
        }
        $powerStateForClose = if ($this.Tag -is [hashtable] -and $this.Tag.ContainsKey('PowerState')) { $this.Tag.PowerState } else { $null }
        if ($powerStateForClose -and $powerStateForClose.Timer) {
            $powerStateForClose.Timer.Stop()
            $powerStateForClose.Timer.Dispose()
            $powerStateForClose.Timer = $null
        }
        if ($powerStateForClose -and $powerStateForClose.Process) {
            # 与模板应用一致：仅释放父进程句柄，不终止正在验证/回滚拓扑的子进程。
            try { $powerStateForClose.Process.Dispose() } catch {}
            $powerStateForClose.Process = $null
        }
        $applyUiState.InProgress = $false
        if ($powerStateForClose) { $powerStateForClose.InProgress = $false }
        $script:templates = $null
        $script:monitors = @()
        $script:selectedMonitor = $null
        $script:selectedTemplate = $null
        $script:selectedTemplateMonitorId = $null
    })

    # 存储刷新函数引用到 Form.Tag，供子控件事件调用
    $form.Tag = @{
        RefreshMonitors = $refreshMonitors
        RefreshTemplates = $refreshTemplates
        PowerAction = $powerAction
        PowerState = $powerUiState
        ApplyState = $applyUiState
        ResizeState = $resizeUiState
    }

    # 初始加载
    & $refreshMonitors
    & $refreshTemplates

    try {
        [void]$form.ShowDialog()
    } finally {
        $form.Dispose()
        foreach ($font in $sharedFonts) {
            try { $font.Dispose() } catch {}
        }
    }
}

# ============================================================
#  桌面快捷方式
# ============================================================

# 生成圆角矩形路径的辅助函数
function Get-RoundedRectPath {
    param([int]$X, [int]$Y, [int]$W, [int]$H, [int]$R)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $R * 2
    $path.AddArc($X, $Y, $d, $d, 180, 90)
    $path.AddArc($X + $W - $d, $Y, $d, $d, 270, 90)
    $path.AddArc($X + $W - $d, $Y + $H - $d, $d, $d, 0, 90)
    $path.AddArc($X, $Y + $H - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    return $path
}

# 生成自定义 ICO 图标文件（紫色渐变 + 多显示器图形）
function New-IconFile {
    Add-Type -AssemblyName System.Drawing

    $iconPath = Join-Path $TemplateDir 'MonitorManager.ico'
    if (-not (Test-Path $TemplateDir)) {
        New-Item -Path $TemplateDir -ItemType Directory -Force | Out-Null
    }

    $size = 256
    $bmp = New-Object System.Drawing.Bitmap $size, $size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode    = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode  = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)

    # 1. 圆角渐变背景（紫 → 靛蓝，呼应 GUI 主题色）
    $bgRect  = New-Object System.Drawing.Rectangle 6, 6, ($size - 12), ($size - 12)
    $bgPath  = Get-RoundedRectPath 6 6 ($size - 12) ($size - 12) 56
    $bgBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $bgRect,
        [System.Drawing.Color]::FromArgb(168, 85, 247),  # 紫 #A855F7
        [System.Drawing.Color]::FromArgb(79, 70, 229),   # 靛 #4F46E5
        45
    )
    $g.FillPath($bgBrush, $bgPath)
    $bgBrush.Dispose()
    $bgPath.Dispose()

    # 内部高光（左上柔光，增加立体感）
    $highlightPath = Get-RoundedRectPath 24 18 130 70 36
    $highlightBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Rectangle 24, 18, 130, 70),
        [System.Drawing.Color]::FromArgb(60, 255, 255, 255),
        [System.Drawing.Color]::FromArgb(0, 255, 255, 255),
        90
    )
    $g.FillPath($highlightBrush, $highlightPath)
    $highlightBrush.Dispose()
    $highlightPath.Dispose()

    # 2. 副显示器（后右，较小，浅色）
    $subPath = Get-RoundedRectPath 138 58 96 76 10
    $g.FillPath([System.Drawing.Brushes]::White, $subPath)
    $subPath.Dispose()
    $subScreenPath = Get-RoundedRectPath 146 66 80 56 5
    $subScreenBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(196, 181, 253))
    $g.FillPath($subScreenBrush, $subScreenPath)
    $subScreenBrush.Dispose()
    $subScreenPath.Dispose()
    # 副显示器底座
    $subStand = New-Object System.Drawing.Drawing2D.GraphicsPath
    $subStand.AddPolygon(@(
        (New-Object System.Drawing.PointF 176, 134),
        (New-Object System.Drawing.PointF 196, 134),
        (New-Object System.Drawing.PointF 202, 146),
        (New-Object System.Drawing.PointF 170, 146)
    ))
    $g.FillPath([System.Drawing.Brushes]::White, $subStand)
    $subStand.Dispose()

    # 3. 主显示器（前左，较大）
    $mainPath = Get-RoundedRectPath 28 100 148 108 12
    $g.FillPath([System.Drawing.Brushes]::White, $mainPath)
    $mainPath.Dispose()
    # 主显示器屏幕（渐变蓝色，更有质感）
    $mainScreenRect = New-Object System.Drawing.Rectangle 38, 110, 128, 80
    $mainScreenPath = Get-RoundedRectPath 38 110 128 80 6
    $mainScreenBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $mainScreenRect,
        [System.Drawing.Color]::FromArgb(129, 140, 248),  # 蓝 #818CF8
        [System.Drawing.Color]::FromArgb(99, 102, 241),   # 靛 #6366F1
        90
    )
    $g.FillPath($mainScreenBrush, $mainScreenPath)
    $mainScreenBrush.Dispose()
    $mainScreenPath.Dispose()

    # 主显示器底座（梯形 + 底板）
    $mainStand = New-Object System.Drawing.Drawing2D.GraphicsPath
    $mainStand.AddPolygon(@(
        (New-Object System.Drawing.PointF 84, 208),
        (New-Object System.Drawing.PointF 120, 208),
        (New-Object System.Drawing.PointF 134, 228),
        (New-Object System.Drawing.PointF 70, 228)
    ))
    $g.FillPath([System.Drawing.Brushes]::White, $mainStand)
    $g.FillRectangle([System.Drawing.Brushes]::White, 54, 226, 96, 10)
    $mainStand.Dispose()

    # 4. 保存为标准 ICO 格式（嵌入 PNG，Vista+ 支持）
    $pngStream = New-Object System.IO.MemoryStream
    $bmp.Save($pngStream, [System.Drawing.Imaging.ImageFormat]::Png)
    $pngBytes = $pngStream.ToArray()
    $pngStream.Close()

    $icoStream = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter $icoStream
    # ICO Header (6 bytes)
    $bw.Write([uint16]0)        # Reserved
    $bw.Write([uint16]1)        # Type = 1 (icon)
    $bw.Write([uint16]1)        # Image count
    # Directory entry (16 bytes)
    $bw.Write([byte]0)          # Width (0 = 256)
    $bw.Write([byte]0)          # Height (0 = 256)
    $bw.Write([byte]0)          # Color palette
    $bw.Write([byte]0)          # Reserved
    $bw.Write([uint16]1)        # Color planes
    $bw.Write([uint16]32)       # Bits per pixel
    $bw.Write([uint32]$pngBytes.Length)  # Image size
    $bw.Write([uint32]22)       # Offset (6 + 16)
    # Image data
    $bw.Write($pngBytes)
    $bw.Flush()

    [System.IO.File]::WriteAllBytes($iconPath, $icoStream.ToArray())
    $bw.Close()
    $icoStream.Close()
    $g.Dispose()
    $bmp.Dispose()

    return $iconPath
}

function New-DesktopShortcut {
    # 加载 Shell32 用于刷新桌面
    if (-not ([System.Management.Automation.PSTypeName]'Shell32Api').Type) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Shell32Api {
    [DllImport("shell32.dll")]
    public static extern void SHChangeNotify(int wEventId, int uFlags, IntPtr dwItem1, IntPtr dwItem2);
}
"@
    }

    $scriptPath = $PSCommandPath
    if (-not $scriptPath) { $scriptPath = $MyInvocation.MyCommand.Path }
    if (-not $scriptPath) {
        Write-Host "错误: 无法获取脚本路径" -ForegroundColor Red
        $script:CommandExitCode = 1
        return
    }

    # 生成（或复用）自定义图标
    $iconPath = New-IconFile

    $desktop = [Environment]::GetFolderPath('Desktop')
    $shortcutPath = Join-Path $desktop '显示器配置管理.lnk'
    $tempShortcutPath = Join-Path $desktop (".显示器配置管理.{0}.tmp.lnk" -f [Guid]::NewGuid().ToString('N'))
    $wsh = $null
    $sc = $null

    try {
        $wsh = New-Object -ComObject WScript.Shell
        # 先完整生成并验证临时快捷方式，再原子替换；失败时保留原有快捷方式。
        $sc = $wsh.CreateShortcut($tempShortcutPath)
        $sc.TargetPath = 'powershell.exe'
        $sc.Arguments = "-WindowStyle Minimized -ExecutionPolicy Bypass -File `"$scriptPath`" gui"
        $sc.WorkingDirectory = Split-Path $scriptPath
        $sc.IconLocation = "$iconPath, 0"
        $sc.Description = '多显示器配置管理工具'
        $sc.WindowStyle = 7
        $sc.Save()
        if (-not (Test-Path $tempShortcutPath)) { throw '临时快捷方式文件未创建' }

        if (Test-Path $shortcutPath) {
            [System.IO.File]::Replace($tempShortcutPath, $shortcutPath, $null, $true)
        } else {
            [System.IO.File]::Move($tempShortcutPath, $shortcutPath)
        }
    } catch {
        if (Test-Path $tempShortcutPath) { Remove-Item $tempShortcutPath -Force -ErrorAction SilentlyContinue }
        Write-Host "错误: 创建快捷方式失败 - $($_.Exception.Message)" -ForegroundColor Red
        $script:CommandExitCode = 1
        return
    } finally {
        if ($sc -and [System.Runtime.InteropServices.Marshal]::IsComObject($sc)) {
            [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($sc)
        }
        if ($wsh -and [System.Runtime.InteropServices.Marshal]::IsComObject($wsh)) {
            [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($wsh)
        }
    }

    # 验证文件是否创建成功
    if (-not (Test-Path $shortcutPath)) {
        Write-Host "错误: 快捷方式文件未创建 - $shortcutPath" -ForegroundColor Red
        $script:CommandExitCode = 1
        return
    }

    $fileInfo = Get-Item $shortcutPath

    # 刷新桌面（SHCNE_ASSOCCHANGED = 0x08000000）
    [Shell32Api]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null

    Write-Host "桌面快捷方式已创建（自定义图标）:" -ForegroundColor Green
    Write-Host "  路径: $shortcutPath" -ForegroundColor Gray
    Write-Host "  图标: $iconPath" -ForegroundColor Gray
    Write-Host "  大小: $($fileInfo.Length) 字节" -ForegroundColor Gray
    Write-Host ""
    Write-Host "双击快捷方式将打开图形界面程序" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "提示: 如果图标显示不正确，请按 F5 刷新桌面" -ForegroundColor Yellow
}

# ============================================================
#  DPI 设置（CLI 命令：dpi）
# ============================================================

function Set-DpiInteractive {
    param([string]$MonitorSpec)
    if (-not ([System.Management.Automation.PSTypeName]'DisplayApi').Type) {
        Write-Host "系统显示 API 不可用，无法设置缩放比例" -ForegroundColor Red
        $script:CommandExitCode = 1
        return
    }
    $monitors = Get-Monitors
    if ($monitors.Count -eq 0) {
        Write-Host "未检测到显示器" -ForegroundColor Red
        $script:CommandExitCode = 1
        return
    }

    # 如果通过命令行参数指定了显示器序号，直接使用
    $preSelected = $null
    if ($MonitorSpec) {
        $preSelected = Resolve-Monitor -Spec $MonitorSpec -Monitors $monitors
        if (-not $preSelected) {
            Write-Host "未找到显示器 '$MonitorSpec'" -ForegroundColor Red
            $script:CommandExitCode = 1
            return
        }
    }

    Write-Host ""
    Write-Host "=== 设置显示器缩放比例 ===" -ForegroundColor Cyan
    Write-Host "支持的缩放档位: $($UserDpiScaleTable -join ' / ') %" -ForegroundColor Gray
    Write-Host ""

    for ($i = 0; $i -lt $monitors.Count; $i++) {
        $m = $monitors[$i]
        $primary = if ($m.IsPrimary) { " (主)" } else { "" }
        $curDpi = if ($m.DpiScale -gt 0) { "$($m.DpiScale)%" } else { "未知" }
        Write-Host "[$($i+1)] $($m.DisplayName)$primary" -ForegroundColor Yellow
        Write-Host "    $($m.MonitorName)  当前缩放: $curDpi"
        Write-Host "    $($m.Width)x$($m.Height)@$($m.RefreshRate)Hz"
        Write-Host ""
    }

    if ($preSelected) {
        $target = $preSelected
    } else {
        Write-Host "输入显示器编号（1-$($monitors.Count)），或 q 退出: " -NoNewline
        $choice = Read-Host
        if ($choice -eq 'q' -or $choice -eq 'Q') { return }

        $idx = 0
        if (-not [int]::TryParse($choice, [ref]$idx) -or $idx -lt 1 -or $idx -gt $monitors.Count) {
            Write-Host "无效编号" -ForegroundColor Red
            $script:CommandExitCode = 2
            return
        }

        $target = $monitors[$idx - 1]
    }
    Write-Host ""
    Write-Host "选择目标缩放档位:" -ForegroundColor Cyan
    for ($j = 0; $j -lt $UserDpiScaleTable.Count; $j++) {
        $mark = if ($UserDpiScaleTable[$j] -eq $target.DpiScale) { " (当前)" } else { "" }
        Write-Host "  $($j+1). $($UserDpiScaleTable[$j])%$mark"
    }
    Write-Host ""
    $scaleChoice = Read-Host "选择 (1-$($UserDpiScaleTable.Count))"
    $scaleIdx = 0
    if (-not [int]::TryParse($scaleChoice, [ref]$scaleIdx) -or $scaleIdx -lt 1 -or $scaleIdx -gt $UserDpiScaleTable.Count) {
        Write-Host "无效选择" -ForegroundColor Red
        $script:CommandExitCode = 2
        return
    }

    $targetScale = $UserDpiScaleTable[$scaleIdx - 1]
    Write-Host ""
    Write-Host "正在设置 $($target.DisplayName) → $targetScale% ..." -ForegroundColor Cyan
    $targetSpec = if ($target.MonitorId) { $target.MonitorId } else { $target.DisplayName }
    $r = Set-DpiScaleVerified -MonitorSpec $targetSpec -TargetScale $targetScale
    if ($r.success) {
        Write-Host $r.message -ForegroundColor Green
    } else {
        Write-Host "失败: $($r.message)" -ForegroundColor Red
        $script:CommandExitCode = 1
    }
}

# ============================================================
#  帮助
# ============================================================

function Show-Help {
    Write-Host ""
    Write-Host "=== 显示器配置管理工具 ===" -ForegroundColor Cyan
    Write-Host "  （按单个显示器保存和应用模板）"
    Write-Host ""
    Write-Host "图形界面:" -ForegroundColor Yellow
    Write-Host "  .\MonitorManager.ps1                 打开 GUI 程序（默认）"
    Write-Host "  .\MonitorManager.ps1 gui              打开 GUI 程序"
    Write-Host "  .\MonitorManager.ps1 shortcut         创建桌面快捷方式"
    Write-Host ""
    Write-Host "命令行:" -ForegroundColor Yellow
    Write-Host "  .\MonitorManager.ps1 list                       列出所有显示器（带序号）"
    Write-Host "  .\MonitorManager.ps1 save <序号> <名称>          保存指定显示器当前配置"
    Write-Host "  .\MonitorManager.ps1 apply <序号> <名称>         应用模板到指定显示器"
    Write-Host "  .\MonitorManager.ps1 disconnect <序号>          从 Windows 桌面断开指定显示器"
    Write-Host "  .\MonitorManager.ps1 connect <序号>             将指定显示器重新连接到 Windows 桌面"
    Write-Host "  .\MonitorManager.ps1 templates [序号]           列出模板（可选指定显示器）"
    Write-Host "  .\MonitorManager.ps1 show <序号> <名称>          查看模板详情"
    Write-Host "  .\MonitorManager.ps1 delete <序号> <名称>        删除指定显示器的模板"
    Write-Host "  .\MonitorManager.ps1 dpi [序号]                 设置显示器缩放（5 档: 100/125/150/175/200）"
    Write-Host "  .\MonitorManager.ps1 menu                       交互式菜单"
    Write-Host "  .\MonitorManager.ps1 diagnose                   诊断当前显示环境"
    Write-Host ""
    Write-Host "说明:" -ForegroundColor Yellow
    Write-Host "  <序号> 可以是 list/templates 显示的序号，也可以是显示器 ID、设备名或唯一友好名称"
    Write-Host "  已断开显示器的模板仍会在 templates 中显示，并可通过 show/delete 管理"
    Write-Host "  每个显示器的模板独立保存，互不影响"
    Write-Host "  为避免桌面完全不可用，工具不会断开最后一台活动显示器"
    Write-Host ""
    Write-Host "示例:" -ForegroundColor Yellow
    Write-Host "  .\MonitorManager.ps1 list"
    Write-Host "  .\MonitorManager.ps1 save 1 2k_240               # 保存 1 号显示器当前配置"
    Write-Host "  .\MonitorManager.ps1 save 1 1080p_60"
    Write-Host "  .\MonitorManager.ps1 apply 1 2k_240               # 应用模板到 1 号显示器"
    Write-Host "  .\MonitorManager.ps1 disconnect 2                 # 断开 2 号显示器"
    Write-Host "  .\MonitorManager.ps1 connect 2                    # 重新连接 2 号显示器"
    Write-Host "  .\MonitorManager.ps1 templates                    # 列出所有显示器的模板"
    Write-Host "  .\MonitorManager.ps1 templates 1                  # 只看 1 号显示器的模板"
    Write-Host "  .\MonitorManager.ps1 delete 1 1080p_60"
    Write-Host ""
    Write-Host "模板存储: $TemplateDir" -ForegroundColor Gray
    Write-Host ""
}

# ============================================================
#  诊断
# ============================================================

function Start-Diagnose {
    Write-Host "========== 诊断开始 ==========" -ForegroundColor Cyan

    # 1. 当前显示器状态
    Write-Host "`n[1] 当前显示器状态:" -ForegroundColor Yellow
    $monitors = Get-Monitors
    foreach ($m in $monitors) {
        $pri = if ($m.IsPrimary) { " (主)" } else { "" }
        Write-Host "  $($m.DisplayName)$pri"
        Write-Host "    $($m.MonitorName)"
        Write-Host "    $($m.Width)x$($m.Height) @ $($m.RefreshRate)Hz, $($m.BitsPerPel)bit"
        Write-Host "    ID: $($m.MonitorId)"
    }

    # 2. 所有模板
    Write-Host "`n[2] 已保存的模板（按显示器分组）:" -ForegroundColor Yellow
    $templates = Load-Templates
    $monitorKeys = @($templates.monitors.PSObject.Properties | ForEach-Object { $_.Name })
    if ($monitorKeys.Count -eq 0) {
        Write-Host "  (无模板)"
    } else {
        foreach ($mid in $monitorKeys) {
            $mon = $templates.monitors.$mid
            Write-Host "  显示器: $($mon.name)  (ID: $mid)" -ForegroundColor Cyan
            if ($mon.templates.Count -eq 0) {
                Write-Host "    (无模板)"
            } else {
                foreach ($t in $mon.templates) {
                    $dpi = if ([int]$t.dpiScale -gt 0) { " DPI=$($t.dpiScale)%" } else { "" }
                    Write-Host "    - $($t.name): $($t.width)x$($t.height)@$($t.refreshRate)Hz${dpi}  ($($t.created))"
                }
            }
        }
    }

    # 3. 检查模板内容是否和当前相同
    Write-Host "`n[3] 模板与当前配置对比:" -ForegroundColor Yellow
    $monitorKeys = @($templates.monitors.PSObject.Properties | ForEach-Object { $_.Name })
    if ($monitorKeys.Count -eq 0) {
        Write-Host "  (无模板可对比)"
    } else {
        foreach ($mid in $monitorKeys) {
            $mon = $templates.monitors.$mid
            $current = $monitors | Where-Object { $_.MonitorId -eq $mid } | Select-Object -First 1
            if (-not $current) {
                Write-Host "  显示器 $mid ($($mon.name)): 系统当前未检测到!" -ForegroundColor Red
                continue
            }
            Write-Host "  显示器 $($current.DisplayName):"
            foreach ($t in $mon.templates) {
                $sameW = ($current.Width -eq [int]$t.width)
                $sameH = ($current.Height -eq [int]$t.height)
                $sameR = ($current.RefreshRate -eq [int]$t.refreshRate)
                Write-Host "    模板 $($t.name): $($t.width)x$($t.height)@$($t.refreshRate)Hz"
                Write-Host "    当前:            $($current.Width)x$($current.Height)@$($current.RefreshRate)Hz"
                Write-Host "    相同: W=$sameW H=$sameH R=$sameR"
            }
        }
    }

    # 4. 测试 API 调用
    Write-Host "`n[4] 测试 API 调用:" -ForegroundColor Yellow
    $primary = $monitors | Where-Object { $_.IsPrimary } | Select-Object -First 1
    if (-not $primary) {
        Write-Host "  未找到主显示器，跳过测试" -ForegroundColor Red
    } else {
        Write-Host "  主显示器: $($primary.DisplayName)"
        Write-Host "  当前: $($primary.Width)x$($primary.Height)@$($primary.RefreshRate)Hz"

        if (-not ([System.Management.Automation.PSTypeName]'DisplayApi').Type -or $primary.RefreshRate -le 0) {
            Write-Host "  系统显示 API 不可用，跳过切换测试" -ForegroundColor Yellow
        } else {
            $testRefresh = if ($primary.RefreshRate -gt 60) { 60 } else { 30 }
            Write-Host ""
            $confirm = Read-Host "  是否进行刷新率切换测试（切换到 ${testRefresh}Hz 再恢复）？(y/n)"
            if ($confirm -ne 'y' -and $confirm -ne 'Y') {
                Write-Host "  已跳过刷新率切换测试" -ForegroundColor Gray
            } else {
                $diagnoseState = @{ ExitCode = 0 }
                try {
                    Invoke-WithNamedMutex -Name $DisplayMutexName -TimeoutMs 30000 -Action {
                        # 从系统重新读取完整 DEVMODE，恢复时不依赖简化后的显示器对象。
                        $original = New-Object DEVMODE
                        $original.dmSize = [System.Runtime.InteropServices.Marshal]::SizeOf([Type][DEVMODE])
                        if (-not [DisplayApi]::EnumDisplaySettingsEx($primary.DisplayName, $ENUM_CURRENT_SETTINGS, [ref]$original, 0)) {
                            throw '无法读取原始显示模式，已取消测试'
                        }

                        $testMode = New-Object DEVMODE
                        $testMode.dmSize = [System.Runtime.InteropServices.Marshal]::SizeOf([Type][DEVMODE])
                        if (-not [DisplayApi]::EnumDisplaySettingsEx($primary.DisplayName, $ENUM_CURRENT_SETTINGS, [ref]$testMode, 0)) {
                            throw '无法构造测试显示模式，已取消测试'
                        }
                        $testMode.dmDisplayFrequency = $testRefresh
                        $testMode.dmFields = $testMode.dmFields -bor $DM_PELSWIDTH -bor $DM_PELSHEIGHT -bor $DM_DISPLAYFREQUENCY -bor $DM_BITSPERPEL

                        Write-Host "`n  --- 测试: 切换到 $($original.dmPelsWidth)x$($original.dmPelsHeight)@$testRefresh Hz ---"
                        $testCode = [DisplayApi]::ChangeDisplaySettingsEx($primary.DisplayName, [ref]$testMode, [IntPtr]::Zero, $CDS_TEST, [IntPtr]::Zero)
                        Write-Host "    模式预检返回值: $testCode"
                        if ($testCode -ne 0) {
                            Write-Host "    目标模式不可用，未进行实际切换" -ForegroundColor Yellow
                            return
                        }

                        try {
                            Write-Host "    写入并提交测试模式..."
                            $stageCode = [DisplayApi]::ChangeDisplaySettingsEx(
                                $primary.DisplayName, [ref]$testMode, [IntPtr]::Zero,
                                $CDS_UPDATEREGISTRY -bor $CDS_NORESET, [IntPtr]::Zero
                            )
                            Write-Host "    写入返回值: $stageCode"
                            if ($stageCode -ne 0 -and $stageCode -ne 1) { throw "写入测试模式失败: $(Get-ChangeResultMessage $stageCode)" }

                            $commitCode = [DisplayApi]::ChangeDisplaySettingsEx([NullString]::Value, [IntPtr]::Zero, [IntPtr]::Zero, 0, [IntPtr]::Zero)
                            Write-Host "    提交返回值: $commitCode"
                            if ($commitCode -ne 0) { throw "提交测试模式失败: $(Get-ChangeResultMessage $commitCode)" }

                            Write-Host "    等待 4 秒观察变化..." -ForegroundColor Magenta
                            Start-Sleep -Seconds 4
                            $after = Get-Monitors | Where-Object { $_.DisplayName -eq $primary.DisplayName } | Select-Object -First 1
                            if ($after) { Write-Host "    切换后: $($after.Width)x$($after.Height)@$($after.RefreshRate)Hz" }
                            if ($after -and [Math]::Abs([int]$after.RefreshRate - $testRefresh) -le 1) {
                                Write-Host "    [OK] 切换成功，API 工作正常" -ForegroundColor Green
                            } else {
                                $actual = if ($after) { "$($after.RefreshRate)Hz" } else { '显示器未重新枚举' }
                                Write-Host "    [FAIL] 切换未生效 (期望 ${testRefresh}Hz, 实际 $actual)" -ForegroundColor Red
                            }
                        } finally {
                            Write-Host "`n  --- 恢复原始 $($original.dmDisplayFrequency)Hz ---"
                            $restoreStage = [DisplayApi]::ChangeDisplaySettingsEx(
                                $primary.DisplayName, [ref]$original, [IntPtr]::Zero,
                                $CDS_UPDATEREGISTRY -bor $CDS_NORESET, [IntPtr]::Zero
                            )
                            $restoreCommit = [DisplayApi]::ChangeDisplaySettingsEx([NullString]::Value, [IntPtr]::Zero, [IntPtr]::Zero, 0, [IntPtr]::Zero)
                            Write-Host "    恢复写入返回值: $restoreStage；恢复提交返回值: $restoreCommit"
                            Start-Sleep -Seconds 2
                            $restored = Get-Monitors | Where-Object { $_.DisplayName -eq $primary.DisplayName } | Select-Object -First 1
                            if ($restored) { Write-Host "    恢复后: $($restored.Width)x$($restored.Height)@$($restored.RefreshRate)Hz" }
                            $restoredOk = $restored -and (Test-DisplayModeMatches $restored $original.dmPelsWidth $original.dmPelsHeight $original.dmDisplayFrequency $original.dmBitsPerPel)
                            if ($restoreStage -ne 0 -or $restoreCommit -ne 0 -or -not $restoredOk) {
                                Write-Host "    [严重] 原始显示模式恢复未通过验证，请立即在 Windows 显示设置中检查" -ForegroundColor Red
                                $diagnoseState.ExitCode = 1
                            } else {
                                Write-Host "    [OK] 原始显示模式已恢复并验证" -ForegroundColor Green
                            }
                        }
                    }.GetNewClosure()
                    if ([int]$diagnoseState.ExitCode -ne 0) { $script:CommandExitCode = [int]$diagnoseState.ExitCode }
                } catch {
                    Write-Host "  刷新率测试失败: $($_.Exception.Message)" -ForegroundColor Red
                    $script:CommandExitCode = 1
                }
            }
        }
    }

    Write-Host "`n========== 诊断结束 ==========" -ForegroundColor Cyan
}

# ============================================================
#  主入口
# ============================================================
$normalizedCommand = $Command.ToLowerInvariant()
if ($normalizedCommand -eq 'source') {
    return  # 内部用：仅加载函数，不退出调用方 PowerShell 进程
}

try {
    switch ($normalizedCommand) {
        'gui'       { Show-Gui }
        'list'      { Show-List }
        'save'      { Save-Template $Arg1 $Arg2 }
        'apply'     { Apply-Template $Arg1 $Arg2 }
        'off'       { Set-MonitorPower $Arg1 'off' }
        'on'        { Set-MonitorPower $Arg1 'on' }
        'disconnect' { Set-MonitorPower $Arg1 'off' }
        'connect'    { Set-MonitorPower $Arg1 'on' }
        'apply-worker' {
            try {
                $workerMonitor = ConvertFrom-Base64Text $Arg1
                $workerTemplate = ConvertFrom-Base64Text $Arg2
                $workerRecords = @(& { Apply-Template $workerMonitor $workerTemplate } *>&1)
                Complete-WorkerOutput -Records $workerRecords -Fallback '模板应用完成'
            } catch {
                $workerError = "后台应用参数无效: $($_.Exception.Message)"
                Write-Output $workerError
                $script:CommandExitCode = 2
                Write-WorkerResult -Message $workerError
            }
        }
        'power-worker' {
            try {
                $workerOperation = ([string]$Arg1).ToLowerInvariant()
                if ($workerOperation -ne 'on' -and $workerOperation -ne 'off') { throw '操作必须是 on 或 off' }
                $workerMonitor = ConvertFrom-Base64Text $Arg2
                $workerRecords = @(& { Set-MonitorPower $workerMonitor $workerOperation } *>&1)
                Complete-WorkerOutput -Records $workerRecords -Fallback '显示器状态切换完成'
            } catch {
                $workerError = "后台显示器电源参数无效: $($_.Exception.Message)"
                Write-Output $workerError
                $script:CommandExitCode = 2
                Write-WorkerResult -Message $workerError
            }
        }
        'templates' { Show-Templates $Arg1 }
        'show'      { Show-Template $Arg1 $Arg2 }
        'delete'    { Remove-Template $Arg1 $Arg2 }
        'menu'      { Show-Menu }
        'shortcut'  { New-DesktopShortcut }
        'help'      { Show-Help }
        'dpi'       { Set-DpiInteractive $Arg1 }
        'diagnose'  { Start-Diagnose }
        default {
            Write-Host "错误: 未知命令 '$Command'" -ForegroundColor Red
            Show-Help
            $script:CommandExitCode = 2
        }
    }
} catch {
    Write-Host "执行失败: $($_.Exception.Message)" -ForegroundColor Red
    $script:CommandExitCode = 1
}
exit ([int]$script:CommandExitCode)
