# CodexMeter — 设计文档

日期：2026-09-21
状态：已批准（用户确认方案 A：SwiftUI 原生 + SPM；双数字状态栏；含阈值通知/倒计时/开机自启/credits 显示）

## 目标

常驻 macOS 菜单栏的小工具（形态类似 cc-switch / SakuraCat），实时显示 Codex 客户端"剩余用量"面板中的余额：5 小时窗口与 1 周窗口的用量百分比、重置时间，并提供阈值通知、重置倒计时、开机自启、credits 余额等附加功能。

## 已验证的技术事实（全部本机实测）

1. **数据源**：`GET https://chatgpt.com/backend-api/wham/usage`
   - Headers：`Authorization: Bearer <access_token>`、`chatgpt-account-id: <account_id>`、`Accept: application/json`
   - 实测返回 200，字段与 Codex 客户端截图一一对应：
     - `rate_limit.primary_window`: `{used_percent, limit_window_seconds: 18000, reset_at}` → 5 小时窗口
     - `rate_limit.secondary_window`: `{used_percent, limit_window_seconds: 604800, reset_at}` → 1 周窗口
     - `rate_limit.limit_reached` / `allowed`：是否已触顶
     - `rate_limit_reset_credits.available_count` → "1 次可用重置"
     - `credits`: `{has_credits, balance, ...}` → credits 余额
     - `plan_type`: "plus"
2. **凭据**：`~/.codex/auth.json`（Codex 客户端共享登录）
   - 结构：`{auth_mode, tokens: {id_token, access_token, refresh_token, account_id}, last_refresh}`
   - `access_token` 为 JWT（aud=`https://api.openai.com/v1`，约 10 天有效期）
3. **Token 刷新**：`POST https://auth.openai.com/oauth/token`，JSON body：
   `{grant_type: "refresh_token", client_id: "app_EMoamEEZ73f0CkXaXp7hrann", refresh_token: "...", scope: "openid profile email"}`
   → 返回新 access_token，需写回 auth.json（openai/codex 官方同款逻辑）
4. **工具链**：Swift 6.3（arm64-apple-macosx26.0），无完整 Xcode（仅 CLT）→ `swift build` 路线；打包脚本组装 .app + ad-hoc 签名
5. **参考**：steipete/CodexBar（SwiftUI MenuBarExtra + SPM 同路线，仅借鉴 auth/刷新思路）

## 架构

单 target SPM executable + SwiftUI `MenuBarExtra(.window)` 自定义面板。`Info.plist`: `LSUIElement=true`。

```
~/.codex/auth.json → CodexAuthStore(含静默刷新) → CodexUsageClient(GET wham/usage)
  → UsageMonitor(@MainActor 唯一状态源，默认60s轮询+失败退避+打开面板即刷)
    → 状态栏 label ⚡33% | 5%   → 面板 UI   → NotificationManager(阈值通知)
```

### 组件职责

- **CodexAuthStore**：读 auth.json、解析 access_token JWT 的 `exp`、提前 24h 或 401 时刷新、原子写回（.tmp+rename、保留 600 权限、只更新 tokens/last_refresh）
- **CodexUsageClient**：GET wham/usage，401 → `UnauthorizedError`
- **UsageMonitor**：定时轮询（默认 60s，可选 30/60/300s）、失败退避 30s→10min、面板打开即刷、唤醒即刷
- **NotificationManager**：阈值 primary 80% / weekly 90% / limit_reached；去重 key=(window, resetAt, threshold)
- **LoginItem**：`SMAppService.mainApp` 开关

## UI

- **状态栏**：`⚡ 33% | 5%`（左 5h 右周），颜色 <70 默认 / 70–89 橙 / ≥90 红；错误 ⚠️、无数据 –
- **面板**：5h 行（大百分比+进度条+重置倒计时）、周行（+重置日期）、「1 次可用重置」徽标、credits 余额（仅 has_credits 时显示）、plan 徽标、立即刷新/上次刷新时间、设置（轮询间隔/通知/自启）、打开 Codex、退出

## 错误处理

- 无 auth.json / 非 OAuth 模式 → 菜单引导 `codex login`
- 刷新失效（400 invalid_grant）→ 提示重新登录，10 分钟退避
- 网络/5xx → 退避重试（30s→10min），状态栏保留旧值+⚠️

## 测试

swift-testing（`import Testing`）：JSON 解析（真实响应脱敏 fixture）、JWT exp 解析、401→刷新→重试决策（MockURLProtocol）、通知去重。UI 手动验收。

## 错误边界与写回安全

刷新成功后：读 → 仅更新 tokens/last_refresh → 写 `.tmp` → `rename` 原子替换 → `chmod 600`。不缓存文件内容，每次轮询重新读取，容忍 Codex 客户端并发改写。

## 范围外（YAGNI）

多账户切换、OAuth 登录 UI（复用 codex login）、历史用量曲线、Claude/其他 provider、菜单栏进度环动画。
