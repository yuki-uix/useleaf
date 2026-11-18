# 隐私说明 / Privacy

本文对应 **Useleaf 0.8.0**。

This document describes **Useleaf 0.8.0**.

拾用 · Useleaf 在本机完成查词、翻译、发音和学习推荐。应用没有账户、遥测、广告 SDK 或云端同步，不向第三方翻译网站或云端大模型发送选文、收藏与场景资料。

Useleaf performs lookup, translation, pronunciation and learning recommendations on your Mac. The app has no account system, telemetry, advertising SDK or cloud sync, and does not send selections, collections or learning profiles to third-party translation sites or cloud language models.

## 本地文件 / Local files

为兼容原拾词 / WordShelf，正式版继续使用：

```text
~/Library/Application Support/com.yuki.wordshelf/
├── words.json
└── learning.json
```

- `words.json` 只保存主动收藏的单词、短语和句子原文，不附加释义、译文、来源、上下文或查询时间。
- `learning.json` 保存场景选择、已有自定义场景、学习用途反馈、已收藏原文的主动查词日期与复习状态。日期按不同 UTC 日期去重，不是网页曝光记录或完整查询历史。
- 未收藏的查询、临时释义和翻译不持久化。复习时输入的答句只保留在当前练习界面；应用不录音，也不自动批改或上传答句。
- 0.8.0 保留 `words.json` 原文字符串数组格式，不增加收藏字段。菜单栏检索词与展开的释义仅留在当前面板内存中，关闭后丢弃；找回收藏、发音与复制不会新增遇见日期或复习记录。
- 删除收藏会将其移出学习队列，但保留关联学习记录，以支持撤销后继续。若需清除全部本地资料，退出应用后移除上述两份文件。

The shipping app retains the original WordShelf data directory for compatibility. `words.json` contains only explicitly saved originals. `learning.json` contains your scenario choices, retained custom scenarios, purpose feedback, distinct UTC dates on which you actively looked up saved entries, and review progress. Unsaved lookups, temporary meanings and translations are not persisted. Practice drafts stay in the current session; the app neither records audio nor uploads or automatically grades answers. Deleting a saved entry removes it from practice while retaining its learning record for undo. To clear all local app data, quit and remove both files.

Version 0.8.0 keeps the existing original-string array in `words.json` without adding collection fields. Menu-bar searches and expanded meanings stay in the current panel's memory and are discarded when it closes. Finding, pronouncing or copying a saved entry adds no encounter dates or review records.

这些文件是本机 JSON，没有额外的应用层加密。应用写入时尝试将收藏文件设为仅当前账户可读写，并以该权限创建学习文件；系统账户权限、备份和你主动导出的 TXT / CSV 文件仍由 macOS 与你管理。

These are local JSON files without additional app-level encryption. The app attempts to restrict collection writes to the current account and creates learning files with account-only permissions. macOS account access, backups and exports you create remain outside the app's control.

## 划词与剪贴板 / Selection and clipboard

只有在你触发划词快捷键时，应用才通过已授予的辅助功能权限读取当前前台应用的选中文字；不会收集整页正文、网址或持续监视阅读内容。它会拒绝安全输入和可识别的密码框。

若阅读应用没有暴露选文，拾用会在快捷键松开且原应用仍在前台时，临时发送一次 `⌘C`。操作前在内存中保存剪贴板快照，读取新的复制结果后，**仅在剪贴板未被再次修改时**恢复快照；不会用旧剪贴板文字冒充选文，也不会覆盖更新的复制内容。无法完整保留剪贴板、选文读取失败或前台应用改变时，会中止读取并提示手动输入。扫描 PDF 和图片没有 OCR 支持。

Selection capture runs only when you trigger the shortcut. It uses the granted Accessibility access to read the foreground app's selected text, without collecting full pages or URLs or continuously monitoring reading. Secure input and recognized password fields are rejected. When Accessibility does not expose the selection, the app temporarily sends `⌘C` after shortcut modifiers are released and while the source app remains in front. It keeps a clipboard snapshot in memory and restores it only if no newer clipboard change has occurred. Existing clipboard text is never treated as a fresh selection, and newer clipboard contents are preserved. Capture failures fall back to manual input. Scanned PDFs and images are not processed with OCR.

在菜单栏收藏面板中点击 **“复制原文”** 是一次主动复制：成功后，系统剪贴板会被替换为该条收藏的完整原文，不附带释义或来源。面板关闭并回到之前的写作应用，由你自行按 `⌘V` 粘贴；应用不会自动输入或发送文本。复制失败时会尝试保留原剪贴板。此行为与划词读取使用的临时复制不同，主动复制成功后不会恢复旧剪贴板。

Clicking **Copy original** in the menu-bar finder is an explicit copy action. On success, it replaces the system clipboard with the complete saved original, without meanings or sources. The panel closes and returns to the previous writing app; you choose where to paste with `⌘V`. The app does not automatically type or send text. It attempts to preserve the previous clipboard if copying fails. Unlike the temporary selection-capture fallback, a successful explicit copy does not restore the old clipboard.

## 浮窗关闭监听 / Outside-click dismissal

0.8.0 只在查译浮窗或菜单栏收藏面板可见期间，临时监听其他应用中的鼠标按下事件，用于点击外部时关闭浮窗。这个监听不读取按键、页面正文或点击目标内容，不保留事件历史；两个浮窗均关闭后立即移除。它不会持续监视阅读或写作过程。

Version 0.8.0 temporarily listens for mouse-down events in other apps only while the lookup popup or menu-bar finder is visible, so an outside click can dismiss it. This listener does not read keys, page text or the contents of the clicked target, and it retains no event history. It is removed as soon as both transient surfaces are closed. It does not continuously monitor reading or writing.

## 系统服务与网络 / System services and network

内置 ECDICT 词典和词频在本地查询。推荐使用本机规则与可用的 Natural Language 模型，缺少语义模型时退回词法规则。英文朗读使用已安装的 macOS 系统语音，不需要麦克风或语音识别权限。

句子翻译使用 Apple 的本地 Translation 框架，需要 macOS 15+ 和英语、简体中文语言包。首次准备语言包时，你需确认系统下载，此步骤需要网络；普通查译不会自动请求语言包下载。重新生成开源词典的开发脚本也会下载固定版本的上游数据，这不属于应用日常运行。

The bundled ECDICT dictionary and frequency data are queried locally. Recommendations use local rules and available Natural Language models, falling back to lexical rules when semantic models are absent. Pronunciation uses installed system voices and requires no microphone or speech-recognition access. Sentence translation uses Apple's local Translation framework on macOS 15+ with English and Simplified Chinese language packs. Explicit initial language preparation requires a system download and network access; normal lookup does not automatically request that download. The developer script for rebuilding the dictionary separately downloads a pinned upstream dataset.

应用的系统诊断日志仅记录快捷键和窗口等流程事件，不记录选文或答句。向 [GitHub Issues](https://github.com/yuki-uix/useleaf/issues) 主动提交的描述和附件会由 GitHub 处理；请使用脱敏示例，不要附真实词库或场景画像。

System diagnostic logs record flow events such as shortcut and window handling, not selected text or practice drafts. Reports and attachments you choose to submit to [GitHub Issues](https://github.com/yuki-uix/useleaf/issues) are handled by GitHub. Use anonymized examples rather than your real collection or learning profile.

小啄的收藏确认与姿态只保留在内存和当前界面，不新增收藏字段、画像信息、统计上传或学习判断。

Woodpecker feedback and poses are temporary UI state. They add no stored collection fields, profile information, telemetry or learning judgments.
