# Security Policy

## 漏洞报告 / Reporting a Vulnerability

如果你发现安全漏洞，请**不要**在公开 Issue 中报告。请通过以下方式私下报告：

1. 在 GitHub 上创建私有安全公告（Security Advisory）：
   - 进入仓库 → Security → Advisories → New draft security advisory
2. 或发送邮件到项目维护者（如有）

我们将尽力在 48 小时内确认收到报告，并在修复后公开致谢。

## 显示器拓扑操作的风险说明

本工具通过 Win32 API 直接操作 Windows 显示配置，包括：

- `ChangeDisplaySettingsEx` — 修改分辨率和刷新率
- `SetDisplayConfig` — 修改显示器连接/断开拓扑
- `DisplayConfigSetDeviceInfo` — 修改 Per-Monitor DPI 缩放（使用未公开的 API type 值）

### 安全措施

本工具已实施以下安全措施：

| 措施 | 说明 |
|------|------|
| 操作前快照 | 每次应用前保存完整 DEVMODE 快照 |
| 回读验证 | 应用后多次轮询验证显示模式 |
| DPI 验证 | DPI 设置后独立回读验证 |
| 自动回滚 | 任一步骤失败自动恢复原始配置 |
| 最后显示器保护 | 拒绝断开最后的活动显示器 |
| 文件原子写入 | 临时文件 + rename 防止损坏 |
| 多实例互斥 | 命名互斥锁防止并发写入 |

### 用户责任

- 本工具直接修改 Windows 显示配置。虽然已实施多层安全措施，但显示驱动或 Windows 更新可能导致意外行为
- 建议在使用 `apply`、`disconnect`、`dpi`、`diagnose`（刷新率测试）等写操作前保存工作
- 如遇显示异常，可在 Windows 显示设置中手动恢复，或重启系统

## 隐私声明 / Privacy

### 本工具不会：

- ❌ 连接互联网
- ❌ 上传任何数据到远程服务器
- ❌ 收集或传输显示器配置信息
- ❌ 收集或传输用户数据
- ❌ 包含任何遥测或分析代码
- ❌ 访问网络

### 数据存储：

- ✅ 所有数据仅存储在 `%USERPROFILE%\.monitormanager\` 目录
- ✅ `templates.json` — 用户手动保存的显示器配置模板
- ✅ `monitor_names.json` — 用户自定义的显示器友好名称
- ✅ 用户可以随时删除这些文件，不影响系统功能

## 依赖安全

本工具**零外部依赖**。所有功能通过以下实现：

- PowerShell 5.1 内置 cmdlet
- .NET Framework（`System.Windows.Forms`、`System.Drawing`）
- Win32 API（通过 `Add-Type` 动态编译 C# 代码）

不依赖任何第三方模块、NuGet 包或外部可执行文件。

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |
