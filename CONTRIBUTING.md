# 参与开发 / Contributing

拾用 · Useleaf 是原生 macOS 应用，源码采用 [MIT License](LICENSE)。请用小范围、可复现的改动说明问题和结果。

Useleaf is a native macOS app released under the [MIT License](LICENSE). Keep changes focused and explain the problem, resulting behavior and relevant validation.

## 环境 / Requirements

- macOS 14+；系统句子翻译需要 macOS 15+ 和已安装的英语、简体中文语言包。
- Swift 6.2+，建议使用 Xcode 26.6+ 的工具链与 SDK；源码包含较新的 Apple Translation API，`#available` 运行时保护不能替代编译时 SDK 声明。
- 构建和测试无需第三方 Swift 包。重新生成词典时需要 Python 3 与网络，固定版本和校验值见 [词典说明](ThirdParty/ECDICT/README.md)。

Use macOS 14+ and Swift 6.2+. Xcode 26.6+ is recommended for the newer Translation SDK declarations; runtime availability checks do not make missing SDK symbols compile. Sentence translation requires macOS 15+ and the English/Chinese language packs. There are no external Swift package dependencies. Rebuilding the pinned dictionary requires Python 3 and network access.

```sh
swift test
scripts/build_app.sh
scripts/package_release.sh
```

构建脚本生成 `dist/Useleaf.app`，打包脚本为已有应用生成带实际架构名称的 ZIP、DMG 和 SHA-256 校验文件。默认构建是本地 ad hoc 签名，不等于 Developer ID 签名或 Apple 公证；不要在发布说明中把单架构包标为 universal。打包操作不会安装应用或改写用户资料。

The build produces `dist/Useleaf.app`. Packaging creates a ZIP, DMG and SHA-256 checksums for the existing app, labeled with its actual architecture. Default builds are ad-hoc signed, not Developer ID signed or Apple notarized. Do not label a single-architecture package as universal. Packaging does not install the app or modify user data.

## 名称与兼容性 / Names and compatibility

对外品牌是「拾用 · Useleaf」。内部 Swift 包、模块、构建产物和部分资源仍保留 `WordShelf` 名称；正式版 Bundle ID 与数据目录继续使用 `com.yuki.wordshelf`。这些不是批量替换遗漏。不要仅因品牌更新而改动标识或移动数据；需要变更时，请提供迁移与旧版兼容验证。

The public brand is Useleaf. Internal package, module, build product and some resource names intentionally remain `WordShelf`; the packaged app executable is `Useleaf`. The shipping Bundle ID and data directory remain `com.yuki.wordshelf`. Preserve them unless a change includes an explicit migration and compatibility validation.

## 提交改动 / Changes and reports

- 测试使用独立临时目录。跨应用划词、语言包准备、真实发音与窗口行为需在 `.app` 中验证；用独立 QA 身份或示例资料，避免改写日常词库。不要让两份正式身份应用同时运行并竞争全局快捷键。
- 修改持久化或学习规则时，验证原文保真、旧文件兼容、手动用途优先、未知词频和失败时不覆盖原文件。与改动相关的测试通过即可，不必为纯文案修改增加镜像测试。
- Issue / PR 写明系统与应用版本、复现步骤、预期和实际结果。仅附必要的脱敏文本；不要上传真实 `words.json`、`learning.json`、场景画像、凭据或包含私人内容的截图。
- 保留 ECDICT 上游许可与来源元数据；新增第三方内容时说明来源、许可证和分发条件。

Tests should use isolated temporary directories. Validate selection capture, language preparation, audio and window behavior in the packaged app using a separate QA identity or sample data. Avoid simultaneous shipping-identity copies competing for the shortcut. Storage and learning changes should preserve original text, old-file compatibility, explicit user intent, unknown-frequency handling and failure protection. Reports should include versions, reproducible steps and expected/actual behavior, using anonymized examples rather than real collections, profiles, credentials or private screenshots. Keep upstream notices and document the license of any new third-party content.
