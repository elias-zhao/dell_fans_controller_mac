# Dell Fans Controller for macOS — 开发计划

> 参考项目：`../dell_fans_controller`（Windows / WinForms 版，cw1997）
> 创建日期：2026-11-24

## 1. 项目目标

在 macOS 上实现戴尔服务器风扇转速控制工具：通过 IPMI over LAN 连接 iDRAC，手动设定风扇转速、恢复自动模式、查看传感器数据。形式为 **菜单栏常驻 App + 详情窗口**。

## 2. 支持范围

| 平台 | 服务器代数 | 支持 |
|---|---|---|
| iDRAC6 / 7 / 8 | 11–13 代（R610/R710、R620/R720、R630/R730 等） | ✅ |
| iDRAC9 固件 ≤ 3.30.30.30 | 14 代（R640/R740 等） | ✅ |
| iDRAC9 固件 ≥ 3.34.34.34、15/16 代、iDRAC10 | — | ❌ 不支持，仅检测并提示 |

> 不支持的原因：Dell 在新固件中从服务器端封禁了 `raw 0x30 0x30` 手动调速命令，客户端无法绕过。版本分界点以实测为准。

## 3. 技术方案

- **语言 / 框架**：Swift + SwiftUI
- **系统要求**：macOS 13+（使用 `MenuBarExtra`）
- **IPMI 实现**：调用系统 `ipmitool`（`brew install ipmitool`），通过 `Process` 以参数数组方式执行，不经过 shell
- **密码传递**：使用 `-E` + 环境变量 `IPMI_PASSWORD`，避免密码出现在 `ps` 进程列表中
- **配置存储**：IP / 用户名存 `UserDefaults`，密码存 Keychain
- **App 形态**：`LSUIElement = YES`（不显示 Dock 图标），可选开机自启（`SMAppService`）

### 核心 IPMI 命令

| 功能 | 命令 |
|---|---|
| 关闭自动调速 | `ipmitool -I lanplus -H <ip> -U <user> -E raw 0x30 0x30 0x01 0x00` |
| 设定转速 | `... raw 0x30 0x30 0x02 0xff 0x<百分比hex>` |
| 恢复自动 | `... raw 0x30 0x30 0x01 0x01` |
| 读传感器 | `... sensor` |
| 读固件版本 | `... mc info` |

## 4. 功能清单

### 第一版（MVP）

- [ ] 连接配置：IP、用户名、密码（Keychain），"测试连接"
- [ ] 固件版本检测，不支持时提示
- [ ] 滑块设定转速百分比（应用前先关闭自动模式）
- [ ] 一键恢复自动模式
- [ ] 读取并解析传感器（Temp / RPM / Voltage / Current）
- [ ] 定时自动刷新（间隔可配置）
- [ ] 命令执行失败时的错误提示（ipmitool 未安装、连接超时、认证失败等）
- [ ] 一键打开 iDRAC 网页控制台
- [ ] 菜单栏图标显示当前温度

### 后续版本（暂不做）

- [ ] 温控曲线：按温度自动调整转速
- [ ] 安全兜底：温度超过阈值自动切回 iDRAC 自动模式
- [ ] 开机自启
- [ ] 多台服务器管理

## 5. 界面设计

### 菜单栏面板

```
┌─────────────────────────────┐
│ R730 · 192.168.1.100   ● 在线 │
├─────────────────────────────┤
│ 🌡 CPU1 45°C   CPU2 47°C     │
│ 🌀 风扇 3600 RPM             │
├─────────────────────────────┤
│ 转速  ━━━━●━━━━━━━  30%       │
│ [ 应用 ]      [ 恢复自动 ]    │
├─────────────────────────────┤
│ 打开详情…   刷新    退出      │
└─────────────────────────────┘
```

### 详情窗口（侧边栏 + 内容区）

```
┌──────────┬──────────────────────────────────────┐
│ 传感器    │ 名称        数值     单位   状态       │
│ 连接设置  │ Inlet Temp  23      °C     ok        │
│ 关于      │ CPU1 Temp   45      °C     ok        │
│          │ Fan1 RPM    3600    RPM    ok        │
│          │ ...                                  │
│          │            自动刷新：[ 10 ] 秒  [刷新] │
└──────────┴──────────────────────────────────────┘
```

- 使用原生控件（`Form` / `Slider` / `Table` / `NavigationSplitView`），自动适配深色模式，不做额外视觉设计。

## 6. 代码结构（规划）

```
dell_fans_controller_mac/
├── PLAN.md
├── Package.swift / *.xcodeproj
└── Sources/
    ├── App/
    │   └── DellFansApp.swift        # 入口，MenuBarExtra + Window
    ├── IPMI/
    │   ├── IPMIClient.swift         # 封装 ipmitool 调用
    │   ├── SensorParser.swift       # 解析 sensor 输出
    │   └── FirmwareCheck.swift      # mc info 解析与支持判断
    ├── Store/
    │   ├── AppState.swift           # 全局状态、定时刷新
    │   └── KeychainHelper.swift
    └── Views/
        ├── MenuBarPanel.swift
        ├── SensorTableView.swift
        ├── ConnectionSettingsView.swift
        └── AboutView.swift
```

## 7. 开发步骤

| 步骤 | 内容 | 负责 | 预计 |
|---|---|---|---|
| 1 | 建项目骨架，菜单栏 + 窗口跑起来 | Claude | 15 分钟 |
| 2 | IPMIClient + 传感器解析 + 固件检测 | Claude | 30 分钟 |
| 3 | 菜单栏面板、详情窗口、设置页 | Claude | 30 分钟 |
| 4 | 错误处理、Keychain、自动刷新 | Claude | 20 分钟 |
| 5 | 安装 ipmitool，连接真机联调 | 用户 | — |
| 6 | 根据实测输出修正解析与兼容问题 | Claude + 用户 | 视情况 |

## 8. 相比 Windows 原版的改进

- 实现了原版界面上有但未实现的"自动刷新"
- 密码不再明文出现在命令行和 INI 文件中
- 命令失败有明确提示（原版静默失败）
- 固件不支持时有提示
- 菜单栏常驻，状态一目了然

## 9. 前置条件 / 风险

- 服务器需开启 **IPMI over LAN**（iDRAC 设置中）
- Mac 需安装 ipmitool：`brew install ipmitool`
- 不同代 iDRAC 的 `sensor` 输出字段名可能不同，需按实测调整解析
- 手动固定低转速有过热风险，使用者需自行关注温度
