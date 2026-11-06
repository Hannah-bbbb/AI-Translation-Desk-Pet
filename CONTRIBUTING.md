# 参与贡献

欢迎提 Issue 和 Pull Request。报 bug 时请写上 macOS 版本、出问题的 App，以及下面「调试」里那条日志命令的输出（日志只有来源 App 和字数，不含你选中的文字）。

## 开发环境

- macOS 14 及以上，Xcode 15 及以上或 Command Line Tools（Swift 5.9+）
- 没有第三方依赖

```bash
swift build             # 编译
swift test              # 单元测试
Scripts/build.sh --run  # 打包成 build/译喵.app 并启动
```

代码结构见 [README](README.md#代码结构)，各模块入口和重要决策记在 [开发记忆/目录.md](开发记忆/目录.md)。

## 不启动 App 看效果

猫和气泡都是代码画的，可以离屏渲染成图片检查：

```bash
swift run Yimiao --snapshot poses.png               # 各种姿势
swift run Yimiao --looks looks.png                  # 毛色 × 装扮
swift run Yimiao --hero hero.png                    # README 顶部那排猫
swift run Yimiao --hero snake.png --snake           # 那排小蛇；--snapshot、--looks 也可以加 --snake
swift run Yimiao --snapshot crab.png --crab         # 像素小蟹的姿势和他自己的小动作；--hero、--looks 也可以加 --crab
swift run Yimiao --snapshot dragon.png --dragon     # 小龙同上
swift run Yimiao --bubbles bubbles.png              # 气泡的各种状态
swift run Yimiao --selection-layouts layouts.png    # 选区避让布局
```

## 调试

- 看日志：`/usr/bin/log stream --predicate 'subsystem == "io.github.hannah-bbbb.yimiao"'`（zsh 里的 `log` 是内建命令，要写全路径）。
- 不用真实 Key 测试翻译：在设置里把 Base URL 指向本机的模拟服务，本机和局域网地址允许用 http。从终端启动且没有保存 Key 时，会读取 `DEEPSEEK_API_KEY` 或 `MOONSHOT_API_KEY`。
- 手动触发：`open "yimiao://translate?text=Hello&x=800&y=560"` 翻译并跳到指定位置，`open -g "yimiao://sit"` 让他去窗口上坐坐。
- 取词依赖「辅助功能」权限；构建脚本让重新构建后的 App 保留这个授权，详见 README 的「其他」一节。

## 提交规范

- 一个提交只处理一个明确主题。标题用 `feat(模块): …`、`fix(模块): …`、`docs: …` 或 `chore: …`，模块如 `pet`、`bubble`、`selection`、`companion`、`settings`、`translate`、`snapshot`。
- 用户能感知到的改动要更新 [CHANGELOG.md](CHANGELOG.md)：日期、行为变化、怎么验证的，以及哪些没验证。
- 提交前运行 `swift test` 和 `git diff --check`；改了打包、签名或权限相关的代码，再跑一次 `Scripts/build.sh`。
- 不要提交 API Key、个人设置或构建产物，`.gitignore` 已排除 `.build/`、`build/` 和环境文件。
- 回退已推送的提交用 `git revert`，保留历史。

## Fork 后改名

应用标识符同时决定钥匙串条目和日志子系统的名字，代码从 App 包里读取。改名只需修改两处：

- `Resources/Info.plist` 的 `CFBundleIdentifier` 和 `CFBundleURLName`
- `Scripts/build.sh` 的 `BUNDLE_ID`

改名后 macOS 会把它当成新 App，需要重新授权辅助功能。旧标识符下的设置和 API Key 可以一次性导入，不会覆盖已有内容：

```bash
build/译喵.app/Contents/MacOS/Yimiao --import-from <旧标识符>
```
