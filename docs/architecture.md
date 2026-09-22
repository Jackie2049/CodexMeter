# CodexMeter 架构

> 本文记录 CodexMeter 的模块划分、数据流与关键设计决策。代码结构变动时同步更新本文件。

## 总览

三个 SPM target：核心逻辑库（可独立测试）、应用壳（AppKit/SwiftUI）、自建测试入口。

```
┌───────────────────────────────────────────────────────────────┐
│ CodexMeter.app                                                │
│                                                               │
│  StatusItemController ──┬── StatusItemContentView（两行状态栏）│
│  (NSStatusItem+Popover) ├── MenuPanelView（SwiftUI 详情面板）  │
│  (悬停/点击/钉住状态机)  └── NSHostingController               │
│                                                               │
│  UsageMonitor（@MainActor 单一状态源：轮询/退避/恢复/通知调度）│
│  NotificationManager / AppSettings / CodexMark·CodexGlyph     │
└───────────────┬───────────────────────────────────────────────┘
                │ import
┌───────────────▼───────────────────────────────────────────────┐
│ CodexMeterCore（纯逻辑，无 UI 依赖，全部可单测）                │
│                                                               │
│  Auth/   CodexAuthStore（auth.json 读写 + OAuth 刷新）         │
│          JWT（exp 解析）、RefreshDecision                      │
│  Net/    CodexUsageClient（wham/usage，URLSessioning 注入）    │
│  Model/  UsageSnapshot（解析 + limitReachedKnown）             │
│          QuotaDisplay（窗口识别/剩余语义/状态栏/时间格式）       │
│  Sys/    NotificationGate（阈值告警+去重）                     │
│          RecoveryTracker（触顶/恢复状态机，持久化）             │
│  Monitor/ BackoffPolicy、Staleness                             │
│  Localization.swift（L10n：zh-Hans / en / zh-Hant）            │
└───────────────────────────────────────────────────────────────┘
```

## 数据流

```
~/.codex/auth.json ──► CodexAuthStore（读凭据；JWT exp ≤24h 或 401 时刷新，
                        原子写回，保留未知字段与 0600 权限）
                          │
                          ▼
              CodexUsageClient ── GET chatgpt.com/backend-api/wham/usage
                          │        （Bearer + chatgpt-account-id）
                          ▼
              UsageSnapshot（解析；limitReachedKnown 区分字段缺失）
                          │
                          ▼
              UsageMonitor（@MainActor）
                ├─ snapshot / lastError / lastRefresh / isStale / authState
                ├─ 401 → 刷新 token → 重试一次
                ├─ 失败 → BackoffPolicy 指数退避（30s→10min）
                └─ Staleness 30s ticker（菜单栏 ⚠️ 与时钟同步）
                          │
        ┌─────────────────┼──────────────────────┐
        ▼                 ▼                      ▼
 StatusItemContentView  MenuPanelView   NotificationGate（阈值告警，
 （两行状态栏+悬停/点击）  （详情面板）     每窗口每阈值去重）
                                        RecoveryTracker（触顶→恢复
                                        一次性事件，UserDefaults 持久化）
                                                │
                                                ▼
                                     NotificationManager（UNUserNotificationCenter）
```

## 关键设计决策

### 1. NSStatusItem 替代 SwiftUI MenuBarExtra

MenuBarExtra 的 label 视图不随 ObservableObject 变化重绘（标题冻结在启动时的状态），且空标题按钮会高度塌缩为 0（内容靠溢出可见、点击命中测试落空）。现状：`NSStatusItem.button` 上叠加 `StatusItemContentView`（两个标签 + 约束定位），`render()` 直接写内容；按钮高度显式约束为 `NSStatusBar.system.thickness`。

### 2. Popover 必须显式设置 contentSize

NSPopover 依赖 contentViewController 视图的 fittingSize，但 SwiftUI 高度在首次 show 时可能尚未解析——零高度 popover 表现为"点了没反应"。`showPopover` 在 show 前强制 `layoutSubtreeIfNeeded()` 并钉住 `popover.contentSize`。

### 3. 悬停/点击双模式展示（StatusItemController 状态机）

- 悬停 0.15s → 弹出（未钉住）；鼠标离开「图标 ∪ 面板」区域 0.15s → 收回（全局+本地 mouseMoved 监听实时判定，容忍图标与面板间的移动间隙）
- 点击 → 弹出并钉住（`isPinned`），点击图标或面板外才收回
- 所有关闭路径（显式/系统 transient）经 `presentationDidClose` 统一重置状态
- NSPopover 内置动画时长不可调，改为瞬时 show + 0.1s 内容淡入

### 4. 窗口按 `limit_window_seconds` 识别，不按字段位置

Pro 套餐的响应中 5 小时窗口可能整体缺失、周度窗口出现在 `primary_window`。所有展示与阈值逻辑按 duration 分派（`QuotaDisplay.shortLabel/longLabel`），不做 primary/secondary 位置假设。

### 5. 剩余额度语义

对外只讲"剩余"（`remainingPercent = 100 - used`），已用百分比不出现。触顶状态不替换数字，由图标/状态条单独表达。

### 6. 恢复语义（RecoveryTracker）

- 只相信**成功获取的快照**：倒计时归零不等于恢复；网络失败、登录失效、字段缺失都不产生事件
- `limit_reached` 字段缺失 → `limitReachedKnown=false` → `record(nil)`：状态不变、不触发（防止解析缺口伪造恢复）
- 事件持久化于 UserDefaults，跨重启保持"曾触顶"状态；同一触顶段落的恢复只通知一次
- 跟踪独立于两个通知开关运行；开关只控制投递，重新开启不补发已过事件

### 7. 数据新鲜度

`Staleness.isStale`：上次成功刷新距今超过 2× 轮询间隔即标记过期（30s 独立 ticker，与轮询解耦）。失败时保留旧数字 + ⚠️ 标记 + 上次成功时间，不冒充实时。

### 8. 自建测试 harness

本机只有 Command Line Tools（无 XCTest、无 swift-testing 模块）。`CodexMeterTestRunner` 是一个可执行 target：`TestEntry` 数组 + 极简断言（失败抛错、非零退出码）。CI 用 `swift run CodexMeterTestRunner` 跑测试。迁回 swift-testing 的前提是拥有完整 Xcode。

### 9. L10n

`L10n.language` 是核心库中的静态值，App 启动与切换时从 `AppSettings.language`（UserDefaults `appLanguage`）单向同步；切换后发 `.codexMeterLanguageChanged` 通知，状态栏重渲染、SwiftUI 面板经 @AppStorage 自动刷新。新增用户可见文案必须走 `L10n`（三列式 `str(简, en, 繁)`）。

## 版本与发布

版本单一来源 = git tag `vX.Y.Z`（semver）。`Scripts/make_app.sh` 用 `git describe` 把 tag 注入 `CFBundleShortVersionString`（pre-tag 开发构建为 `0.1.0-dev`），`CFBundleVersion` 为提交计数；面板齿轮菜单显示应用内版本。发版入口：`Scripts/release.sh <version>`（测试 → tag → push，CI 接管）。

## 已知取舍与未来方向

- **未签名未公证**：无 Apple 开发者账号；安装需 `xattr -cr`。公证是"值得做但需要账号"的事项
- **无应用内自动更新**：刻意不做（AGENTS.md §10）；Sparkle 是候选但需要签名配合
- **测试 harness**：无参数化、无并发用例隔离——当前规模（50 上下）够用
- **QuotaDisplay 体量**：窗口标签、状态栏文本、时间格式聚在一个文件——当前内聚尚可，继续膨胀时按职责拆分
- **轮询而非事件驱动**：无官方推送接口，轮询 + 退避是唯一选择
