# MythicRankHUD

魔兽世界（Midnight）大秘境排名 HUD 插件：基于区域数据包估算 M+ 评分排名、百分比区间，并集成组队面板的赛季/周常信息与顶部货币栏。

World of Warcraft (Midnight) Mythic+ rank HUD. Estimates regional M+ rank and progress from published percentile data packs, and integrates season/weekly info plus a season currency bar into supported Group Finder windows.

## 两个变体 / Two Variants

两个变体共用同一套 Lua 源码，只有 TOC 与本地化文件不同；`tools/build_release.ps1` 会一次打出两个发布包到 `releases/`。

| 位置 | 说明 | 命令 |
| --- | --- | --- |
| 仓库根目录（`MythicRankHUD.toc`） | 国际版（英文界面） | `/myrank` |
| `releases/QFXMythicRankHUD/`（叠加层） | 中文版（zhCN / zhTW / enUS 本地化） | `/qfxrank` |

当前版本 / Current version: **1.3.30**。

## 安装 / Install

把发布包里的 `MythicRankHUD`（国际版）或 `QFXMythicRankHUD`（中文版）目录复制到 `Interface\AddOns\` 下，重启游戏或 `/reload`。

Copy the `MythicRankHUD` or `QFXMythicRankHUD` folder into `Interface\AddOns\`, then restart the client or `/reload`.

数据包（可选，用于排名估算）：`QFXMythicRankData_CN / _US / _EU / _KR / _TW`。

## 测试 / Tests

```bash
for t in tests/*_test.lua; do lua5.3 "$t"; done
```

## 打包 / Packaging

```powershell
.\tools\build_release.ps1   # 生成 releases/MythicRankHUD-<版本>.zip 与 releases/QFXMythicRankHUD-<版本>.zip
```

## 自动发布 / Automated Release（国际版 → CurseForge）

推版本号 tag（不带 `v` 前缀）即触发 [release.yml](.github/workflows/release.yml)：跑测试 → BigWigs packager 打包仓库根目录（`.pkgmeta`）→ 上传 CurseForge（项目 ID `1616156`，已写入 TOC）并附到 GitHub Release。

```bash
git tag 1.3.30
git push origin 1.3.30
```

一次性准备 / One-time setup：

1. CurseForge 网站 → Settings → **Upload API Tokens** 创建 token。
2. 在仓库 Settings → Secrets and variables → Actions 添加 secret：`CF_API_KEY`（或 `gh secret set CF_API_KEY -R zhufei1000/MythicRankHUD`）。

说明 / Notes：

- CurseForge 的文件版本号取自 tag 名，所以 tag 必须与 TOC 的 `## Version` 一致且不带 `v` 前缀。
- 未配置 `CF_API_KEY` 时，workflow 仍会跑测试并发布 GitHub Release，只是跳过 CurseForge 上传。
- QFXMythicRankHUD（中文版）不发布到 CurseForge，工作流只打包国际版。

## 更新日志 / Changelog

- **1.3.30** — 传送完成喊话默认关闭（新安装；老用户已有设置不受影响）；接入 tag 触发的自动发布流程。
- **1.3.23–1.3.29** — 副本结束与队友进队播报、设置界面分区与文案自定义、双变体统一源码。
- **1.3.22** — 修复晦暗虚空核心数量显示错误：正式服可收集货币沿用 ID 3418（3511/3513 为客户端数据中的未使用重复条目）。
- **1.3.21** — Midnight 第二赛季货币（迷雾纹章 3442-3446、毒疫魔流 3465）。
