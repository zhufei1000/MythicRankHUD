# MythicRankHUD

魔兽世界（Midnight）大秘境排名 HUD 插件：基于区域数据包估算 M+ 评分排名、百分比区间，并集成组队面板的赛季/周常信息与顶部货币栏。

World of Warcraft (Midnight) Mythic+ rank HUD. Estimates regional M+ rank and progress from published percentile data packs, and integrates season/weekly info plus a season currency bar into supported Group Finder windows.

## 两个变体 / Two Variants

| 目录 | 说明 | 命令 |
| --- | --- | --- |
| `MythicRankHUD/` | 国际版（英文界面） | `/myrank` |
| `QFXMythicRankHUD/` | 中文版（zhCN / zhTW / enUS 本地化） | `/qfxrank` |

两个变体功能基本一致，本地化与部分集成细节不同，分别对应两个发布包。当前版本 / Current version: **1.3.22**。

## 安装 / Install

将所需目录（`MythicRankHUD` 或 `QFXMythicRankHUD`）复制到 `Interface\AddOns\` 下，重启游戏或 `/reload`。

Copy the folder of the variant you want into `Interface\AddOns\`, then restart the client or `/reload`.

数据包（可选，用于排名估算）：`QFXMythicRankData_CN / _US / _EU / _KR / _TW`。

## 测试 / Tests

```bash
cd MythicRankHUD
lua tests/MythicDetailResources_test.lua   # 等四个测试
```

## 自动发布 / Automated Release（国际版 → CurseForge）

推版本号 tag（不带 `v` 前缀）即触发 [release.yml](.github/workflows/release.yml)：跑测试 → BigWigs packager 打包 `MythicRankHUD/` → 上传 CurseForge 并附到 GitHub Release。

```bash
git tag 1.3.23
git push origin 1.3.23
```

一次性准备 / One-time setup：

1. 在 [CurseForge](https://legacy.curseforge.com/wow/addons/start) 创建 WoW 插件项目（需人工审核通过），记下项目页右侧的数字 **Project ID**。
2. 在 `MythicRankHUD/MythicRankHUD.toc` 中取消注释 `## X-Curse-Project-ID:` 并填入该 ID。
3. CurseForge 网站 → Settings → **Upload API Tokens** 创建 token，然后在仓库 Settings → Secrets and variables → Actions 添加 secret：`CF_API_KEY`。

说明 / Notes：

- CurseForge 的文件版本号取自 tag 名，所以 tag 必须与 TOC 的 `## Version` 一致且不带 `v` 前缀。
- 未配置 `CF_API_KEY` 或 Project ID 时，workflow 仍会跑测试并发布 GitHub Release，只是跳过 CurseForge 上传。
- QFXMythicRankHUD（中文版）不发布到 CurseForge，工作流只打包国际版目录。


## 更新日志 / Changelog

- **1.3.22** — 修复晦暗虚空核心数量显示错误：正式服可收集货币沿用 ID 3418（3511/3513 为客户端数据中的未使用重复条目）。
- **1.3.21** — Midnight 第二赛季货币（迷雾纹章 3442-3446、毒疫魔流 3465）。
