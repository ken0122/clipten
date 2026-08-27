# ClipTen

一个只在本机运行的轻量 macOS 菜单栏剪贴板历史工具。

## 功能

- 自动记录最近 10 条纯文本剪贴板内容
- 相同内容自动去重，再次复制时移到最前
- 点击菜单栏图标查看，点选任一记录即可复制
- 历史记录退出后仍保留在本机
- 支持清空历史；不显示 Dock 图标

## 构建

需要 macOS 13 或更高版本，以及 Xcode Command Line Tools。

```bash
./scripts/build-app.sh
open dist/ClipTen.app
```

## 使用

1. 启动 `ClipTen.app`。
2. 正常复制任意文本。
3. 点击菜单栏中的剪贴板图标。
4. 点击一条历史记录，将其重新复制到系统剪贴板。

记录通过 `UserDefaults` 保存在本机，不进行网络通信。
