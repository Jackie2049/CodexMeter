<div align="center">

# CodexMeter

**轻量的 macOS 菜单栏 Codex 额度监控工具**

[简体中文](README.md) | [English](README.en.md)

[![CI](https://github.com/Jackie2049/CodexMeter/actions/workflows/ci.yml/badge.svg)](https://github.com/Jackie2049/CodexMeter/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/Jackie2049/CodexMeter)](https://github.com/Jackie2049/CodexMeter/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black)

</div>

CodexMeter 把 Codex 的剩余额度放进 macOS 菜单栏——两行文本实时显示 5 小时窗口与周度额度的剩余比例和重置时间，悬停即览、点击固定，不打断你的工作流。

<!-- TODO: 截图（来自实际应用并遮挡个人信息），由维护者补充 -->

## 功能

- **两行状态栏**：`⚡ 5小时 84% · ↻ 3 小时 12 分后` / `⚡ 周度 81% · ↻ 6 天 8 小时后`——每行一个窗口，额度与重置时间同行展示
- **悬停即览**：鼠标悬停 0.15s 弹出详情面板（进度条、大字号百分比、重置时间），移开自动收回；点击可固定面板
- **阈值通知**：5小时/周度额度低于阈值时提醒（默认 80%/90%，每窗口每阈值只提醒一次），触顶立即提醒
- **恢复提醒**：额度触顶后，一旦新数据确认恢复，通知"可以继续使用 Codex 了"（独立开关）
- **数据新鲜度**：刷新失败或数据过期时状态栏出现 ⚠️ 标记，绝不冒充实时的假数字
- **三语界面**：简体中文 / English / 繁體中文，设置中切换
- **安静**：本地运行、无 Dock 图标、轮询可调（30s/1m/5m）、随系统休眠暂停

## 安装

1. 从 [Releases](https://github.com/Jackie2049/CodexMeter/releases) 下载 `CodexMeter-vX.Y.Z.zip` 并解压
2. 将 `CodexMeter.app` 拖入 `/Applications`
3. 终端执行 `xattr -cr /Applications/CodexMeter.app`（构建未签名未公证，Gatekeeper 会拦截，此命令解除隔离）
4. 启动 CodexMeter——前提是你已用 `codex login` 登录过 Codex CLI（应用读取 `~/.codex/auth.json`）

> ⚠️ 本项目**未做 Apple 公证**（需要开发者账号）。移除隔离后即可正常使用，介意者可从源码构建。

## 使用

| 交互 | 行为 |
|---|---|
| 悬停菜单栏图标 | 0.15s 后弹出详情面板 |
| 鼠标移开 | 面板自动收回 |
| 点击图标 | 弹出并**钉住**面板（再点一次或点击面板外收回） |
| 面板内齿轮 | 轮询间隔 / 阈值通知 / 重置提醒 / 界面语言 / 开机自启 |

登录、token 刷新等完全复用 Codex CLI 的凭据体系，本工具不干预 Codex 主客户端的使用。

## 数据与隐私

CodexMeter 完全本地运行：读取 `~/.codex/auth.json` 中的 OAuth 凭据（与 Codex CLI 共享），请求 OpenAI 的 usage 接口获取额度数据。**除该接口外不连接任何服务器，不收集、不上传任何数据**。token 刷新结果会写回 `auth.json`（与官方客户端行为一致）。

## 构建

依赖：Swift 6 工具链（Xcode 16 或 Command Line Tools 均可，无需完整 Xcode）。

```bash
git clone https://github.com/Jackie2049/CodexMeter.git
cd CodexMeter
swift build                 # 构建
bash Scripts/test.sh        # 运行测试（49 个）
bash Scripts/make_app.sh    # 打包 CodexMeter.app 到 build/
```

## 架构

见 [docs/architecture.md](docs/architecture.md)——模块划分、数据流与关键设计决策（状态栏为何不用 MenuBarExtra、恢复语义、测试 harness 取舍等）。

## 声明与致谢

- 本项目是**非官方**的个人工具，与 OpenAI 无从属关系；OpenAI、Codex、ChatGPT 等名称与标志归其所有者所有
- 设计与实现参考了 [steipete/CodexBar](https://github.com/steipete/CodexBar)（同领域更完整的开源作品）
- 使用中遇到问题欢迎提 Issue；功能方向见代码库的演进讨论

## 许可证

[MIT](LICENSE) © 2025 Jackie2049
