---
name: ClipTen
description: 以 macOS 原生菜单栏语言呈现最近十条剪贴板文本的轻量工作台
---

# Design System: ClipTen

## Overview

**Creative North Star: "The Native Memory Slip"**

ClipTen 像一张随手可取的系统记忆便签：它栖身于菜单栏，只在用户主动点开时展开，不占 Dock、不制造独立窗口，也不把短暂的剪贴板动作包装成复杂工作流。视觉表达完全服从 macOS 原生菜单，让应用看起来像系统本来就有的一项能力。

界面密度紧凑但不拥挤。层级来自系统菜单的排版、分隔线、禁用态和键盘快捷键列；内容本身是主角，品牌装饰保持隐形。深色、浅色、高对比度、键盘导航和 VoiceOver 表现均交由 AppKit 的动态语义与系统行为处理。

**Key Characteristics:**

- 单一菜单栏入口，无独立主窗口。
- 原生菜单材质、系统字体与动态语义颜色。
- 最近记录先于管理命令，十条上限始终清晰可扫读。
- 反馈短促且克制，不中断当前应用。

## Colors

ClipTen 不定义品牌色板；菜单背景、文字、禁用态、选中态、分隔线和模板图标着色全部继承当前 macOS 外观与无障碍设置。

### Neutral

- **System Menu Surface:** 由 `NSMenu` 提供的动态菜单材质，用于唯一的展开面板。
- **System Label:** 系统动态标签色，用于标题、记录和命令文字。
- **System Secondary Label:** 系统禁用态对比度，用于不可操作的标题、空状态和不可用的清空命令。
- **System Separator:** 系统动态分隔线，用于切分标题、历史记录和工具命令。
- **Template Icon Tint:** 菜单栏模板图标继承系统当前着色，自动适应菜单栏明暗状态。

**The Appearance Inheritance Rule.** 不固定任何浅色或深色值；新增视觉状态必须使用 AppKit 动态系统语义。

## Typography

**Display Font:** macOS system menu font
**Body Font:** macOS system menu font
**Label/Mono Font:** 不使用独立字体

**Character:** 字体应像系统命令而不是品牌海报。字号、字重、行高和快捷键对齐均由原生 `NSMenuItem` 决定，随系统设置保持一致。

### Hierarchy

- **Title:** 禁用的原生菜单项，用于“最近复制”分组标题。
- **Body:** 默认原生菜单项，用于单行历史预览。
- **Label:** 默认原生菜单项，用于“清空记录”和“退出 ClipTen”等工具命令。

**The System Type Rule.** 不为菜单内容设置自定义字体、字号、字重或字距。

## Layout

应用以一个系统方形状态栏项目为入口。菜单严格按纵向顺序组织：禁用标题“最近复制”、系统分隔线、零至十条历史记录（或一个禁用空状态）、系统分隔线、清空命令和退出命令。该顺序是信息架构，不应因记录数量或系统外观变化而重排。

每条记录以单行预览出现：连续空白与换行折叠为空格，默认最多显示 72 个字符，超出后以省略号收束；完整文本保留在系统工具提示和可访问名称中。系统菜单负责宽度、边距、行高和屏幕边缘避让，不设置自定义断点或固定面板尺寸。

**The Ten-at-a-Glance Rule.** 历史区最多十行，并保持最近内容在最上方；不要引入分页、滚动容器、搜索栏或嵌套子菜单。

## Elevation & Depth

ClipTen 不添加自定义阴影或描边。菜单与其所在应用之间的层级完全由 macOS 菜单窗口的系统材质、边缘和合成阴影表达；状态栏图标在静止状态下保持平面模板符号。

**The Native Layer Rule.** 不在原生菜单之上叠加卡片、弹窗或自制浮层。

## Shapes

菜单轮廓、行高、分隔线端点、选中背景和窗口圆角全部采用当前 macOS 的系统形态。唯一的应用符号是 SF Symbols 模板图标：静止时为 `doc.on.clipboard`，复制成功时短暂切换为 `checkmark`。

**The System Geometry Rule.** 不覆盖原生菜单圆角、内边距、选中轮廓或图标绘制方式。

## Components

### Status Item

- **Shape:** 系统方形状态栏槽位，由 `NSStatusItem.squareLength` 决定。
- **Default:** 使用可随菜单栏着色的 `doc.on.clipboard` 模板符号，并提供说明最近十条剪贴板的系统工具提示。
- **Success:** 点选历史记录后切换为 `checkmark`，约 0.8 秒后恢复；反馈不弹通知、不播放声音、不夺取焦点。

### History Menu

- **Header:** “最近复制”使用禁用菜单项，承担分组标签而非操作。
- **Empty State:** 无记录时显示禁用的“还没有剪贴板记录”。
- **History Item:** 一行可读预览，完整内容置于工具提示；第一至第十条对应 `Command-1` 至 `Command-0`。
- **Selection:** 采用系统菜单高亮；点选后把完整内容写回剪贴板，并将其移到历史首位。
- **Utilities:** “清空记录”在无历史时禁用；“退出 ClipTen”使用 `Command-Q`。

**The One-Click Return Rule.** 从打开菜单到恢复任一历史文本只需要一次菜单项选择，不添加确认、详情页或二级动作。

## Do's and Don'ts

### Do:

- **Do** 使用原生 `NSMenu`、`NSMenuItem`、系统分隔线和 SF Symbols 模板图标扩展现有界面。
- **Do** 保持“标题 → 历史 → 工具命令”的固定阅读顺序。
- **Do** 让完整文本继续通过工具提示和可访问名称可用，即使可见预览被截断。
- **Do** 将反馈限制为菜单栏图标的短暂状态变化。

### Don't:

- **Don't** 添加独立窗口、Dock 界面、卡片面板或自绘菜单。
- **Don't** 固定浅色或深色颜色，也不要覆盖系统字体、圆角、阴影和选中态。
- **Don't** 用多行正文撑高菜单项，或让历史记录超过十条。
- **Don't** 为复制成功增加通知、声音、模态确认或焦点切换。
