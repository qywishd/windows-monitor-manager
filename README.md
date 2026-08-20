# Windows Monitor Manager

<p align="center">
  <img src="preview_icon.png" alt="Windows Monitor Manager" width="128" height="128">
</p>

<p align="center">
  <strong>🖥️ Windows 多显示器配置管理工具</strong>
</p>

<p align="center">
  <em>A native PowerShell GUI tool for saving per-monitor profiles and switching complete multi-monitor scenes on Windows.</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-Windows%2010%2F11-blue" alt="Platform">
  <img src="https://img.shields.io/badge/PowerShell-7%20preferred%20%7C%205.1%20compatible-blue" alt="PowerShell">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
  <img src="https://img.shields.io/badge/version-1.1.0-blue" alt="Version">
</p>

---

## 📖 简介 / Introduction

**Windows Monitor Manager** 是一个纯 PowerShell + WinForms 的原生 GUI 工具，帮助你：

- 识别已连接显示器的分辨率、刷新率、颜色深度和 DPI 缩放
- 按**单个显示器**保存配置模板（不影响其他显示器）
- 保存**多显示器场景**，一键切换多台显示器的连接状态与显示参数
- 一键切换模板（GUI / CLI / 交互菜单）
- 单独连接或断开显示器（等同 Windows"扩展桌面/断开此显示器"）
- 安全回滚：应用失败时自动恢复原始配置

优先使用 PowerShell 7；未安装时会自动回退到 Windows 10/11 自带的 PowerShell 5.1，无需第三方模块。

**Windows Monitor Manager** is a native PowerShell + WinForms GUI tool that lets you save per-monitor display profiles (resolution, refresh rate, color depth, DPI scaling) and switch between them instantly — all without third-party dependencies.

---

## ✨ 功能列表 / Features

| 功能 | 说明 |
|------|------|
| 🖥️ **显示器识别** | 检测所有已连接显示器及其当前分辨率、刷新率、色深、DPI 缩放 |
| 💾 **单显示器模板** | 为每台显示器独立保存配置，互不影响 |
| 🎛️ **多显示器场景** | 保存全部显示器的开/关状态，并一键恢复活动显示器的分辨率、刷新率、色深和缩放 |
| ⚡ **一键应用** | GUI 双击或 CLI 命令快速切换模板 |
| 🔌 **连接/断开** | 从 Windows 桌面单独断开或重新连接指定显示器 |
| 🔒 **安全保护** | 拒绝断开最后一台活动显示器；应用失败自动回滚 |
| ✅ **回读验证** | 每次应用后验证显示模式与 DPI 是否与模板一致 |
| 🎨 **现代 GUI** | 深色侧栏 + 浅色主区设计，显示器预览图形 |
| ⌨️ **CLI 完整** | 所有操作均支持命令行，可编写脚本批量管理 |
| 📋 **桌面快捷方式** | 一键创建自定义图标的桌面快捷方式 |
| 📝 **自定义名称** | 为显示器设置友好名称，方便识别 |
| 🏷️ **旧格式兼容** | 自动迁移旧版模板格式到新版按显示器分组结构 |
| 🔍 **诊断模式** | `diagnose` 命令检查显示器状态、模板与当前配置对比 |
| 📊 **离线模板管理** | 已断开显示器的模板仍可查看和删除 |

---

## 🚀 安装与启动 / Installation

### 系统要求 / Requirements

| 项目 | 要求 |
|------|------|
| 操作系统 | Windows 10 / Windows 11 |
| PowerShell | 推荐 7；兼容 Windows PowerShell 5.1 |
| 权限 | 当前用户权限即可（无需管理员） |
| 依赖 | 无任何第三方依赖 |

> **注意：** 本工具使用 Win32 API（`ChangeDisplaySettingsEx`、`SetDisplayConfig`、`DisplayConfigGetDeviceInfo` 等），这些 API 是 Windows 原生组件，无需额外安装。所有 Win32 结构体定义均在脚本内通过 `Add-Type` 动态编译。

### 下载与启动 / Download & Run

```powershell
# 1. 下载 MonitorManager.ps1 到本地目录
# 2. 在 PowerShell 中运行：
.\MonitorManager.ps1

# 或指定命令：
.\MonitorManager.ps1 gui        # 打开 GUI（默认）
.\MonitorManager.ps1 list       # 列出所有显示器
.\MonitorManager.ps1 help       # 查看帮助
```

> **提示：** 首次运行建议执行 `.\MonitorManager.ps1 shortcut` 创建桌面快捷方式，之后双击即可启动 GUI。

程序的 GUI 后台任务和新建桌面快捷方式会优先使用 `pwsh.exe`（PowerShell 7），找不到时自动回退到 `powershell.exe`（Windows PowerShell 5.1）。修改系统默认终端不是必要条件；升级旧版本后可重新运行 `shortcut` 更新已有快捷方式。

---

## 📋 使用方法 / Usage

### GUI 图形界面

```
.\MonitorManager.ps1
```

1. 左侧栏显示所有已连接显示器（含离线模板组）
2. 点击显示器 → 右侧显示该显示器的所有模板
3. 双击模板卡片 → 立即应用
4. 点击 **+ 添加模板** → 保存当前配置
5. 点击 ⏻ 电源按钮 → 连接/断开该显示器
6. 点击 ✎ 铅笔按钮 → 重命名显示器
7. 点击 **多屏场景** → 保存当前多屏配置，或一键切换已有场景

### CLI 命令行

```powershell
# 列出所有显示器（带序号）
.\MonitorManager.ps1 list

# 保存 1 号显示器的当前配置为模板
.\MonitorManager.ps1 save 1 工作

# 应用模板到 1 号显示器
.\MonitorManager.ps1 apply 1 工作

# 断开 2 号显示器
.\MonitorManager.ps1 disconnect 2

# 重新连接 2 号显示器
.\MonitorManager.ps1 connect 2

# 保存当前全部显示器为“办公”场景
.\MonitorManager.ps1 scene-save 办公

# 一键切换到“单屏游戏”场景
.\MonitorManager.ps1 scene-apply 单屏游戏

# 列出或删除多显示器场景
.\MonitorManager.ps1 scenes
.\MonitorManager.ps1 scene-delete 办公

# 列出所有模板
.\MonitorManager.ps1 templates

# 查看 1 号显示器的模板详情
.\MonitorManager.ps1 show 1 工作

# 删除 1 号显示器的模板
.\MonitorManager.ps1 delete 1 工作

# 设置 1 号显示器缩放比例（100/125/150/175/200）
.\MonitorManager.ps1 dpi 1

# 交互式菜单
.\MonitorManager.ps1 menu

# 诊断当前显示环境
.\MonitorManager.ps1 diagnose

# 创建桌面快捷方式
.\MonitorManager.ps1 shortcut
```

> **参数 `<序号>` 说明：** 可以是 `list` 或 `templates` 输出中的数字序号（1-based），也可以是显示器 ID、设备名（如 `\\.\DISPLAY1`）或唯一友好名称。

---

## 📁 模板存储位置 / Template Storage

模板文件保存在用户目录下：

```
%USERPROFILE%\.monitormanager\
├── templates.json        # 模板数据（按显示器 ID 分组）
├── scenes.json           # 多显示器场景（连接状态与活动显示参数）
└── monitor_names.json    # 自定义显示器名称
```

- 所有数据仅存储在本地，**不会上传到任何服务器**
- 模板按显示器设备 ID 分组，换接口或换线缆后只要设备 ID 不变即可继续使用
- 文件损坏时自动创建备份（`.corrupted.*.bak`），不会静默覆盖

---

## 🔒 安全机制 / Safety Mechanisms

### 断开保护
- **不会断开最后一台活动显示器**，避免桌面完全不可用
- 断开主显示器前会弹出确认对话框，提示 Windows 将迁移主显示器

### 应用回滚
- 应用模板前**保存当前完整 DEVMODE 快照**
- 提交后**回读验证**分辨率、刷新率、色深是否与模板一致
- DPI 设置后**独立回读验证**
- 任一步骤失败 → **自动恢复原始模式 + 原始 DPI**
- 回滚本身也经过**多次轮询验证**
- 场景切换先一次性提交最终拓扑，再逐台恢复显示参数；任一步失败会尝试恢复切换前的完整拓扑和活动显示器快照

### 数据完整性
- 所有文件写入使用 **临时文件 + 原子 Move**，防止中断损坏
- 读取时校验 JSON 结构和字段有效性，损坏时**创建备份并阻止写入**
- 多实例通过**命名互斥锁**串行化读写

### 并发保护
- 数据互斥锁：保护 `templates.json`、`scenes.json` 和 `monitor_names.json` 的读写
- 显示互斥锁：保护显示器模式切换，避免并发写入显示配置

---

## ❓ 常见问题 / FAQ

**Q: 为什么我的显示器显示了"已断开"？**
A: 该显示器物理连接正常，但已从 Windows 桌面逻辑断开。点击侧栏的 ⏻ 电源按钮即可重新连接。

**Q: 应用模板后分辨率没有变化？**
A: 请检查模板参数是否与显示器支持的模式兼容。可以先用 `diagnose` 命令检查。某些显示器需要重启才能应用特定模式。

**Q: 模板文件可以手动编辑吗？**
A: 不建议。文件包含校验逻辑，格式错误会导致写入被阻止。如需批量管理，建议使用 CLI 命令。

**Q: 支持笔记本内屏吗？**
A: 支持。所有 Windows 识别的显示器均可管理，包括笔记本内屏（eDP）和外接显示器。

**Q: 为什么保存时提示"无法读取当前缩放比例"？**
A: 这通常发生在某些特殊的显示配置下。如果是覆盖已有模板，工具会保留原有的 DPI 设置。

---

## ⚠️ 已知限制 / Known Limitations

1. **仅支持 Windows** — 依赖 Win32 API（`ChangeDisplaySettingsEx`、`SetDisplayConfig` 等）
2. **不支持自定义缩放** — DPI 仅支持 Windows 标准档位（100/125/150/175/200%）
3. **不支持 HDR 切换** — HDR 需通过 Windows 显示设置单独管理
4. **不支持 GPU 颜色设置** — 如 NVIDIA 控制面板中的颜色调整
5. **刷新率 1Hz 回读误差** — 部分显示器/驱动回读刷新率可能与设定值差 1Hz，模板匹配已容差处理
6. **DisplayConfig 逆向 API** — 部分 DPI 功能使用了未公开的 `DisplayConfigGetDeviceInfo` type 值（-3/-4），未来 Windows 更新可能改变行为
7. **场景不保存桌面布局** — v1.1.0 场景保存连接状态和显示参数，不改变显示器位置、旋转、主显示器或扩展/复制模式；复制模式下缺少独立显示源时会安全拒绝切换

---

## 🧪 测试 / Testing

### PowerShell 7（推荐）

```powershell
pwsh.exe -NoProfile -File .\check_syntax.ps1
pwsh.exe -NoProfile -File .\safe_tests.ps1
```

### Windows PowerShell 5.1 兼容验证

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\check_syntax.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\safe_tests.ps1
```

> **安全测试不会：**
> - 改变真实显示器分辨率、刷新率或 DPI
> - 连接或断开真实显示器
> - 修改用户的模板文件或显示器名称文件
>
> 所有显示写入调用（`SetDisplayConfig`、`ChangeDisplaySettingsEx`）均被测试替身替换。

### 运行只读命令（验证枚举正常）

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\MonitorManager.ps1 help
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\MonitorManager.ps1 list
```

### 测试覆盖范围

| 测试项 | 说明 |
|--------|------|
| 语法解析 | `check_syntax.ps1` — PowerShell AST 解析错误检测 |
| 结构体 ABI 大小 | 验证所有 Win32 结构体内存布局 |
| 模板保存/去重 | 同名保存、参数去重、无效值拒绝 |
| 模板应用/回滚 | 提交失败回滚、模式验证失败回滚、DPI 失败回滚 |
| DPI 设置 | 设置验证、偏移计算、回读不匹配回滚 |
| 显示器电源 | 断开/连接逻辑、最后显示器保护、空闲源检测 |
| 多显示器场景 | 保存/去重、物理目标映射、原子拓扑规划、缺失硬件保护、整场景回滚 |
| 拓扑操作 | Path-only 拓扑、数据库回退、快照恢复 |
| 数据完整性 | 损坏文件备份、无效 JSON 拒绝写入、旧格式迁移 |
| 闭包安全 | `GetNewClosure` 不访问 `$script:` 状态 |

---

## 🤝 贡献 / Contributing

详见 [CONTRIBUTING.md](CONTRIBUTING.md)。

- 欢迎提交 Issue 和 Pull Request
- 提交前请运行 `check_syntax.ps1` 和 `safe_tests.ps1`
- **禁止在测试中直接改变真实显示器拓扑**
- 如需添加新功能，请先开 Issue 讨论

---

## 🔐 安全 / Security

详见 [SECURITY.md](SECURITY.md)。

### 隐私承诺
- ✅ 所有数据仅存储在本地 `%USERPROFILE%\.monitormanager\` 目录
- ✅ 不包含任何网络通信代码
- ✅ 不上传显示器配置、设备 ID 或任何用户数据

---

## 📄 许可证 / License

本项目采用 [MIT License](LICENSE)。

Copyright (c) 2026 qywishd

---

## 📝 更新日志 / Changelog

详见 [CHANGELOG.md](CHANGELOG.md)。

### v1.1.0 (2026-08-15)

- 新增多显示器场景保存、管理与一键切换
- 场景切换失败时恢复原始拓扑与显示参数
- 新增 GUI 场景管理窗口及 `scene-*` CLI 命令
- GUI 后台进程和桌面快捷方式优先使用 PowerShell 7，缺失时回退到 5.1

### v1.0.0 (2026-07-21)

- 🎉 首次公开发布
- 完整 GUI（WinForms 原生窗口，深色侧栏设计）
- 按显示器分组的模板管理
- DisplayConfig API 精确显示器识别
- 单显示器连接/断开（含安全保护和回滚）
- CLI 完整命令集
- 安全回滚（模式 + DPI 双验证）
- 全面安全测试套件
