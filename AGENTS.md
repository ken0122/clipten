# ClipTen 开发与交付约定

本文件适用于整个仓库。项目目录与应用名均为 **ClipTen**，仓库为 `ken0122/clipten`。先阅读 `README.md`、`PRODUCT.md`、`DESIGN.md` 和 `TESTING.md`；不要从旧目录、旧构建缓存或已安装应用推断当前源码状态。

## 产品边界

- 原生 Swift / AppKit 菜单栏工具，macOS 13+；维持 `NSMenu`，无独立主窗口、Dock 界面或云服务。
- 文字与静态 PNG / TIFF 合计最多 10 条；图片保留原始字节，单张不超过 20,000,000 字节、40,000,000 像素。
- 点选与 `Control + Shift + 1…9 / 0` 复制当前第 1…10 条，成功后置顶，不自动粘贴。
- 打开菜单和生成缩略图不改变历史或剪贴板；再次打开应用的菜单入口必须在状态栏图标被挤掉时仍可用。
- Finder 文件复制、多图、动图、多页图片、OCR、账户与同步不在当前范围内；扩展前先确认需求。
- 保留原生键盘导航、系统外观、可访问名称、禁用态和菜单内错误提示。Launcher 与状态栏共享 `ClipTenIcon` 字形。

## 代码导航

| 文件 | 职责 |
| --- | --- |
| `Sources/ClipTen/AppDelegate.swift` | 原生菜单、轮询入口、复制反馈、重新打开应用 |
| `ClipboardCaptureReader.swift` | 读取剪贴板表示，排除文件复制，优先 PNG |
| `ClipboardEntry.swift` | 稳定 ID、文本/图片条目、图片元数据与错误类型 |
| `ClipboardImageProcessor.swift` | 字节/像素限制、格式验证、摘要与缩略图 |
| `HistoryController.swift` | 主线程 UI、后台串行队列、异步复制与清空失效 |
| `ClipboardHistoryStore.swift` / `HistoryDisk.swift` | 持久化、迁移、原子提交、受限文件操作 |
| `GlobalShortcutManager.swift` | Carbon 全局快捷键注册与冲突反馈 |
| `Sources/ClipTenDesign/ClipTenIcon.swift` | 唯一图标绘制源 |
| `Resources/Info.plist` | 应用标识、版本和系统要求 |

表中省略目录的 Swift 文件均位于 `Sources/ClipTen/`。

构建入口为 `Package.swift`（Swift tools 6.0）和 `scripts/build-app.sh`。macOS 13 是应用部署目标，不代表任意 macOS 13 上的 Command Line Tools 都能编译当前源码；先检查 `swift --version`。

## 数据安全：不可回退的约束

1. **不改 Bundle Identifier / 偏好设置域**：固定为 `local.luokun.ClipTen`。应用自身使用 `UserDefaults.standard`；不要使用与当前 Bundle Identifier 同名的 suite 初始化应用存储。
2. 数据目录固定为用户 `Application Support/local.luokun.ClipTen/`，与项目路径和版本无关。`history-v2.json` 为版本化索引，`images/` 存原始图片。
3. 旧键 `clipboardHistory` 是字符串数组；`clipboardHistoryFormatVersion = 2` 为迁移标记。迁移保持内容和顺序，新索引写入并回读验证成功后才标记完成，旧键保留为备份。
4. 已迁移的索引缺失、损坏或与内存不一致时停止覆盖写入；不能当空历史重建，也不能自动导入过时旧键。图片缺失只影响该条，不清空其他历史。
5. 图片先完整写入文件，再原子提交索引；成功提交后才删除未引用图片。失败保留已提交历史，不提前淘汰文件。
6. 启动仅恢复历史并记录剪贴板基线。清空必须使旧异步任务失效，同时处理新索引、图片和旧备份；重启不得复活已清空内容。
7. 文件名必须来自经过验证的格式与摘要；拒绝符号链接与路径穿越，清理只处理数据目录内生成的普通文件，不能递归删除未知内容。
8. 不打印、提交或上传真实剪贴板内容、用户历史、偏好设置导出及备份。不用删除用户数据的方式解决启动或升级错误。

## 并发与复制

- 主线程操作 AppKit 与系统剪贴板；图片处理、文件 IO 与存储引擎由后台串行队列承载。
- 捕获按顺序提交并限制排队数据量，菜单只持有小缩略图，不批量缓存全尺寸图片。
- 菜单项绑定 ID，快捷键在触发时确定目标 ID；异步完成后不能重新按数组位置取条目。
- 加载完成前校验文件；写回原始表示，不写缩略图或路径。加载期间剪贴板已变化时取消旧复制。
- 处理清空、重复请求、加载期间条目被淘汰的竞态；仅在复制与置顶提交成功后给出成功反馈。

## 测试与本地安装

```sh
swift test
swift test -c release
./scripts/build-app.sh
codesign --verify --deep --strict dist/ClipTen.app
```

- 移动目录后旧 Swift 缓存可能包含失效绝对路径；使用新的 `--scratch-path work/<新缓存目录>`，构建脚本可通过 `CLIPTEN_BUILD_DIR` 指向同一路径。不要为修复缓存删除历史或偏好设置。
- 所有自动测试使用临时目录、独立偏好设置域与命名剪贴板。不得把测试改为 `.general`。
- volatile UserDefaults 域只遮盖读取，**不会隔离写入**。真实 `.app` 初始化探针必须预置临时索引和进程内迁移标记，避免向正式域重复写标记。
- 保留升级、清空重启、图片原字节、容量去重、稳定 ID、IO 失败、索引损坏、缺失图片、菜单重开和真实 `.app` 初始化回归。
- 启动相关改动还须覆盖慢速历史/缩略图恢复期间的新复制，以及恢复前已打开菜单在完成后的状态；只在 `waitUntilIdle()` 后开始复制或打开菜单，不能验证这两个边界。当前缺口见 `DESIGN.md`。
- 审查时区分产品约束与实现事实；如功能缺口未修复，文档须明确标记，不因现有测试通过便写成已实现。复现使用临时夹具，不能依赖真实用户历史。
- 跨应用实测与真实按键/视觉验收按 `TESTING.md` 隔离流程执行。构建通过、处理函数测试或进程存活不等于真实粘贴验收。
- 仅在获得安装授权后替换 `/Applications/ClipTen.app`：先退出旧实例，备份旧应用和数据，启动后核对迁移内容及顺序。不要为发布而无授权地再次替换用户的验证实例。

## Git 与 Release

- 先检查 `git status`、分支、远端及现有 tag/release，保留不属于本次任务的工作区内容；按明确路径暂存，核对暂存 diff，禁止 `git add .` 混入无关文件。
- “提交”不等于推送；安装、推送、发布各按用户明确授权执行。“验证后发布”必须等待用户授权，不擅自提前发布。
- 版本在 `Resources/Info.plist` 更新：`CFBundleShortVersionString` 使用语义版本，`CFBundleVersion` 递增；Bundle Identifier 不变。
- 发布前更新 README / 产品 / 设计 / 测试说明中的相关事实。自动测试、用户验证、未完成的人工检查必须区分，不虚构验收结果。
- 运行 Debug、Release 测试和 `git diff --check`。发布构建使用不受 iCloud / File Provider 同步的临时输出目录，避免 Finder 元数据破坏严格签名检查。
- ZIP 应只包含 `ClipTen.app`，不含用户数据、源码缓存或备份。使用 `ditto -c -k --norsrc --noextattr --keepParent` 打包；重新解压后核对版本、架构、Bundle Identifier 和 `codesign --verify --deep --strict`。
- 产物为 `ClipTen-macOS.zip` 与 `SHA256SUMS`，放在被忽略的 `dist/`，通过 GitHub Release 上传，不提交二进制文件。
- 将已验证提交推送到 `origin/main`，创建对应 `vX.Y.Z` tag 并推送；创建草稿 Release、上传资产、检查后发布。禁止覆盖既有 tag 或未经授权替换已发布资产。
- 发布后核对远端 SHA、tag 与 Release，下载资产比对 SHA-256 并验证解压签名。交付提交 SHA、Release 链接及任何保留的未提交文件。
- workflow 文件需要相应 GitHub 权限；不能为了推送扩大凭证权限或更换身份。权限不足时保留原文件并说明，不阻塞独立的本地测试与手工发布。

当前预编译包仅保证 Apple Silicon；Intel 源码构建不等于 Intel 运行验收。ad-hoc 签名不等于 Developer ID 签名或 Apple 公证。
