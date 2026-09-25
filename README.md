# MythicRankHUD

魔兽世界（Midnight）大秘境排名 HUD 插件：基于区域数据包估算 M+ 评分排名、百分比区间，并集成组队面板的赛季/周常信息与顶部货币栏。

World of Warcraft (Midnight) Mythic+ rank HUD. Estimates regional M+ rank and progress from published percentile data packs, and integrates season/weekly info plus a season currency bar into supported Group Finder windows.

## 两个变体 / Two Variants

两个变体共用同一套 Lua 源码，只有 TOC 与本地化文件不同；`tools/build_release.ps1` 会一次打出两个发布包到 `releases/`。

| 位置 | 说明 | 命令 |
| --- | --- | --- |
| 仓库根目录（`MythicRankHUD.toc`） | 国际版（英文界面） | `/myrank` |
| `releases/QFXMythicRankHUD/`（叠加层） | 中文版（zhCN / zhTW / enUS 本地化） | `/qfxrank` |

当前版本 / Current version: **1.6.6**。

## 安装 / Install

把发布包里的 `MythicRankHUD`（国际版）或 `QFXMythicRankHUD`（中文版）目录复制到 `Interface\AddOns\` 下，重启游戏或 `/reload`。

Copy the `MythicRankHUD` or `QFXMythicRankHUD` folder into `Interface\AddOns\`, then restart the client or `/reload`.

数据包（可选，用于排名估算）：`QFXMythicRankData_CN / _US / _EU / _KR / _TW`。

大秘境结束时会显示整合的胜利/失败结算图。分数使用本次结算后的赛季总分，加分优先使用暴雪结算信息中的跑前、跑后总分差；当前排名和本次提升名次由已选区域数据包分别估算跑后、跑前分数。排名前的 `~` 表示估算值；数据不足时隐藏对应数值，不填入测试数字。结算图默认顶部相对屏幕中心偏移 X=-1.11、Y=274.44；保持 10 秒，最后 2 秒淡出，锁定后鼠标可穿透。无需再安装独立的 QFXMythicCeremony。

原版完成横幅保留，并显示在整合结算图之上。小队喊话在开钥匙时记录四名队友的完整名字、服务器、分数和预计排名；结算后只显示角色名，每位队友一行，报告当前分数、本次加分、当前预计排名、本次预计提升名次，以及距下一个目标（下一条分数线或成就线，如「距前10%差123分」）的分数差，最后发送一行广告。队友离队或游戏没有返回其结算后分数时，对应值显示 `--`，不猜测数据。队友进队欢迎会读取其分数与排名：所有待欢迎的队友共用一个每 2 秒的慢刷新队列，分数可读时立即发出完整欢迎，插钥匙、离队或关闭欢迎时自动停止；若你在组队查找器开组，队友申请时的分数（暴雪申请者列表数据）会被缓存并直接用于进队欢迎。

设置页的“大秘境结算图片”区块有“解锁结算图片”勾选框：勾选后关闭设置窗口，用鼠标左键拖动预览图；取消勾选即可保存并锁定。也可输入 `/qfxmc unlock` 和 `/qfxmc lock` 完成同样操作。`/qfxmc resetpos` 只重置图片位置。测试命令：`/qfxmc live` 显示当前分数和预计排名（不显示本次增量）；`/qfxmc victory`、`/qfxmc defeat`、`/qfxmc longrank` 使用固定测试数字。`/qfxmc sound`、`/qfxmc scale 0.5-1.5`、`/qfxmc reset` 调整结算显示。

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

- **1.6.6** — 将当前游戏保存的结算图位置设为插件默认位置；重置位置命令同步使用新默认值。
- **1.6.5** — 设置页加入“解锁结算图片”勾选框，无需输入命令即可拖动并锁定结算图。
- **1.6.4** — 结算图默认从屏幕中心向下显示；新增解锁拖动、锁定保存和单独重置位置命令。
- **1.6.3** — 大秘境完成时立即按限时或超时结果播放插件结算图片和音效，不再校验地图 ID 或等待分数更新；恢复暴雪原版完成横幅，并避免插件图层遮盖原版横幅。排名数据读取失败时仍会播放图片和音效。
- **1.6.0** — 新增 EllesmereUI 整体风格适配与设置界面的「窗口外观」选择：默认**跟随 EllesmereUI**（EUI 的「Style」页选择 Blizzard Style / Classic WoW UI 时，HUD 面板与详细窗口自绘对应的暴雪原生外壳——Blizzard 风格用对话框金边、Classic 风格用香草岩石窗口 + 细金边，HUD 面板用暴雪提示框样式；金边保持原生美术，深色底与插件一致，背景透明度仍由滑块控制）；也可固定为**插件自身 / 暴雪原生 / 旧世经典**。外观切换在重载界面后生效（EUI 自身切换风格也要求重载）。
- **1.5.1** — 修复小队喊话被 12.x 聊天转义校验拒绝的问题（模板里的裸竖线触发 `Invalid escape code in chat message`）：默认文案不再使用 `|`，发送失败时自动改用全角符号重试，并自动清理旧版本固化的模板覆盖。进队欢迎新增组队查找器申请者分数缓存（开组时申请者的分数会用于进队欢迎）与共享慢刷新队列（所有待欢迎队友共用一个 2 秒轮询，读到分数立即发送，插钥匙/离队/关闭时自动停止）；结算喊话改为每位队友一行、0.5 秒间隔并附距下一目标的分数差。适配 WoW 音频编码与 EUI 皮肤。
- **1.5.0** — 隐藏原版完成横幅；结束喊话改为逐位播报队友成绩，按 GUID 和完整服务器名记录开钥匙前数据，最后发送广告。
- **1.4.1** — 整合 QFXMythicCeremony 结算界面与音效；结束时显示真实赛季分数、本次加分、已选区域预计排名和本次预计提升名次。
- **1.4.0** — 赛季条副本卡片改为按分数从高到低排列（同分按钥石层数，再按固定顺序）。新增 EllesmereUI 皮肤支持：安装 EllesmereUI 且启用第三方皮肤时，HUD 面板与详细窗口自动套用其主题（窗口外观、关闭按钮、下拉框，标题与进度条跟随强调色实时同步）；未安装或关闭皮肤时保持原外观，插件自身的外观滑块仅在该模式下生效。
- **1.3.30** — 传送完成喊话默认关闭（新安装；老用户已有设置不受影响）；接入 tag 触发的自动发布流程。
- **1.3.23–1.3.29** — 副本结束与队友进队播报、设置界面分区与文案自定义、双变体统一源码。
- **1.3.22** — 修复晦暗虚空核心数量显示错误：正式服可收集货币沿用 ID 3418（3511/3513 为客户端数据中的未使用重复条目）。
- **1.3.21** — Midnight 第二赛季货币（迷雾纹章 3442-3446、毒疫魔流 3465）。
