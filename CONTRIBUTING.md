# Contributing

感谢你的贡献兴趣！/ Thank you for your interest in contributing!

## 开发环境 / Development Environment

| 项目 | 要求 |
|------|------|
| 操作系统 | Windows 10 / Windows 11 |
| PowerShell | 5.1+ |
| 编辑器 | 任意文本编辑器（VS Code 推荐） |

无需安装额外依赖。所有开发通过直接编辑 `MonitorManager.ps1` 完成。

## 提交规范 / Commit Conventions

- 使用中文或英文提交信息均可
- 推荐格式：`类型: 简短描述`
  - `feat: 添加新功能`
  - `fix: 修复某问题`
  - `docs: 更新文档`
  - `test: 添加测试`
  - `refactor: 重构某模块`

## 测试要求 / Testing Requirements

提交任何代码变更前，必须通过以下测试：

```powershell
# 1. 语法检查
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\check_syntax.ps1

# 2. 安全测试
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\safe_tests.ps1

# 3. 只读功能验证
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\MonitorManager.ps1 help
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\MonitorManager.ps1 list
```

### ⛔ 严格禁止 / Strictly Prohibited

**在测试中禁止以下操作（包括 CI）：**

- ❌ 改变真实显示器分辨率、刷新率、颜色深度
- ❌ 设置或改变真实显示器 DPI 缩放
- ❌ 连接或断开真实显示器
- ❌ 调用 `ChangeDisplaySettingsEx`（带写入标志）
- ❌ 调用 `SetDisplayConfig`（带 `SDC_APPLY` 标志）
- ❌ 修改用户的 `templates.json` 或 `monitor_names.json`

`safe_tests.ps1` 已将所有显示写入函数替换为测试替身（test doubles），新增测试必须遵循相同模式。

### 添加新测试

如需添加测试，请参考 `safe_tests.ps1` 中的模式：

1. 使用临时目录存储测试数据（`[IO.Path]::GetTempPath()` + GUID）
2. 替换所有会改变显示状态的函数为 mock
3. 在 `finally` 块中清理临时目录
4. 测试不改变真实显示器拓扑

## Pull Request 流程

1. **先开 Issue 讨论** — 对于新功能或重大变更，请先创建 Issue 描述你的想法
2. **Fork 仓库**
3. **创建功能分支** — `git checkout -b feat/my-feature`
4. **编写代码和测试**
5. **运行测试套件** — 确保 `check_syntax.ps1` 和 `safe_tests.ps1` 全部通过
6. **提交 PR** — 描述变更内容和测试结果

### PR 检查清单

- [ ] `check_syntax.ps1` 通过
- [ ] `safe_tests.ps1` 通过（输出包含 `SAFE_TESTS_OK`）
- [ ] 未修改用户的模板或显示器名称文件
- [ ] 新增功能有对应的安全测试覆盖
- [ ] 文档已更新（如适用）
- [ ] 未包含任何真实显示器数据或用户路径

## 代码风格 / Code Style

- 保持与现有代码一致的风格
- PowerShell 函数名使用 PascalCase（动词-名词）
- Win32 结构体和常量使用 UPPER_SNAKE_CASE
- 中文注释可以保留，新代码建议使用中英双语注释
- 显示器核心逻辑（Win32 API、回滚、识别）不应仅为风格而重构

## 版本号 / Versioning

本项目遵循 [Semantic Versioning](https://semver.org/)。版本号在 `MonitorManager.ps1` 的 `$verLabel.Text` 中定义。
