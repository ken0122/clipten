# ClipTen

一个只在本机运行的轻量 macOS 菜单栏剪贴板历史工具。

## 功能

- 自动记录最近 10 条纯文本剪贴板内容
- 相同内容自动去重，再次复制时移到最前
- 点击菜单栏图标查看，点选任一记录即可复制
- 菜单关闭时也可使用全局快捷键 `⌃⇧1`～`⌃⇧0`（Control + Shift + 数字，共三键）
- 历史记录退出后仍保留在本机
- 支持清空历史；不显示 Dock 图标
- Finder 与 Launchpad 使用和菜单栏一致的原创剪贴板图标

## 安装

### 直接安装（推荐）

1. 打开项目的 [Releases 页面](https://github.com/ken0122/clipten/releases/latest)。
2. 在 **Assets** 中下载 `ClipTen-macOS.zip`。
3. 解压后，将 `ClipTen.app` 拖入 macOS 的“应用程序”文件夹。
4. 启动 `ClipTen.app`，菜单栏出现剪贴板图标即安装完成。

当前应用没有经过 Apple 公证。若首次启动时 macOS 提示无法验证开发者，请在 Finder 中右键 `ClipTen.app`，选择“打开”，然后再次确认“打开”。

如果 Releases 页面暂时没有可下载文件，可以按下面的方式从源码构建。

### 从源码构建

需要 macOS 13 或更高版本，以及 Xcode Command Line Tools。

```bash
git clone https://github.com/ken0122/clipten.git
cd clipten
./scripts/build-app.sh
mv dist/ClipTen.app /Applications/
open /Applications/ClipTen.app
```

## 使用

1. 启动 `ClipTen.app`。
2. 正常复制任意文本。
3. 点击菜单栏中的剪贴板图标。
4. 点击一条历史记录，将其重新复制到系统剪贴板。

也可以在任意应用中直接按 `Control + Shift + 数字`：`⌃⇧1`～`⌃⇧9` 对应第 1～9 条，`⌃⇧0` 对应第 10 条，无需先打开状态栏菜单。该组合避开了常见的 `⌘1`、`⌘⇧3` 等系统与应用快捷键；如果系统报告占用或注册失败，ClipTen 会跳过该键，并在菜单中显示不可用数字。个别应用的自定义快捷键仍可能使用相同组合，无法保证与所有软件完全无冲突。

记录通过 `UserDefaults` 保存在本机，不进行网络通信。

## 许可证

本项目采用 [MIT License](LICENSE)。
