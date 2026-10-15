# 译喵

住在 macOS 桌面上的橘猫翻译官。醒着的时候眼睛跟着鼠标转，你在任何 App 里选中一段文字，他就蹦到旁边，调用 DeepSeek 或 Kimi 翻译，把译文用气泡递到你眼前。他还会记下你查过的词过几天来考你，在你坐太久、该下班、该睡觉的时候提醒一声。

## 构建和运行

需要 macOS 14 以上和 Xcode（或 Command Line Tools）。

```bash
Scripts/build.sh --run
```

产物是 `build/译喵.app`，可以拖进「应用程序」。只有改了代码才需要重新构建，平时直接打开这个 App 就行。他没有 Dock 图标，入口是桌面上的猫和菜单栏里的猫头图标。

## 第一次使用

1. **选择 AI 服务并填 API Key**：右键点猫 → 设置 → 翻译，在「AI 服务」选择 DeepSeek 或 Kimi，填入对应平台的 Key，点「测试连接」。[创建 DeepSeek Key](https://platform.deepseek.com/api_keys) · [创建 Kimi Key](https://platform.kimi.com/console/api-keys)。各服务的 Key 分开保存在系统钥匙串里。
2. **给辅助功能权限**：设置 → 取词 → 去授权，在系统设置里打开「译喵」的开关。没有这个权限他看不到你选中的文字；缺权限时你一选中文字，他会冒气泡提醒，点气泡就能跳过去。

之后在任意 App 里拖选、双击或用 ⇧ 加方向键选中文字即可。

## 切换 DeepSeek / Kimi

在「设置 → 翻译 → AI 服务配置」切换服务即可，配置自动保存。两套 API Key、Base URL、模型与深度思考开关彼此独立，来回切换不用重填；升级前的 DeepSeek 配置会继续保留。切换后，后续翻译、连接测试和 AI 陪伴台词使用所选服务，已经发出的请求仍使用发出时的配置。

| 服务 | 默认 Base URL | 默认模型 | 模型预设 |
| --- | --- | --- | --- |
| DeepSeek | `https://api.deepseek.com` | `deepseek-flash` | `deepseek-flash`、`deepseek-v4-pro` |
| Kimi | `https://api.moonshot.cn/v1` | `kimi-k2.6` | `kimi-k2.6`、`kimi-k3` |

Kimi 默认关闭思考，适合快速翻译。K2.6 可开关思考；K3 始终思考，开关对应低/高推理强度。自填其他 Kimi 模型时使用该模型的服务默认参数。Base URL 和模型都可手动编辑；使用 Moonshot 国际站密钥时，可将地址改为 `https://api.moonshot.ai/v1`。只填接口根地址，不要加 `/chat/completions`。

Kimi 模型与参数依据[官方模型列表](https://platform.kimi.com/docs/models)和[模型参数参考](https://platform.kimi.com/docs/api/models-overview)配置。密钥应在对应 API 开放平台创建。从终端启动且尚未保存 Key 时，DeepSeek 读取 `DEEPSEEK_API_KEY`，Kimi 读取 `MOONSHOT_API_KEY`。

## 怎么玩

| 操作 | 效果 |
| --- | --- |
| 选中文字 | 他跳到选区旁边翻译，气泡避开原文，说完回原位 |
| 点气泡 | 复制译文；有按钮时点按钮（看答案、重试、去设置…） |
| 鼠标停在气泡上 | 气泡不消失 |
| 单击猫 | 戳一下，同时收起气泡；睡着时是叫醒 |
| 双击猫 | 哄睡。睡着后不取词、不翻译、不发任何请求 |
| 拖动猫 | 拎到别处，位置会记住 |
| 在他身上来回摸 | 冒爱心 |
| 播放视频时 | 他自动滑到最近的屏幕边缘，只露半张脸，停播几秒后回来；点他或拖他可以叫出来 |
| 右键猫 / 菜单栏图标 | 睡觉、翻译剪贴板、设置、退出 |

默认外语译成简体中文，中文译成英文，两个方向都能在设置里改。五分钟没有键鼠操作他会自己睡着，你回来时自己醒。

气泡会按完整选区边界选择上下方或侧边空位，并为译文逐字增长预留空间；空间较小时使用紧凑气泡，长译文可以滚动。若当前屏幕没有空位，会尝试其他显示器；所有屏幕都放不下时，菜单栏出现「译文」，点击菜单里的「查看译文」查看或复制，不自动覆盖原文。读取不到选区边界时，鼠标拖选按经过的整段行区域避让；键盘或 Shift 扩选按焦点文本控件范围保守避让，因此气泡可能离原文更远。

## 他什么时候会主动开口

每句话都有由头，不靠定时器随机冒出来：

| 由头 | 默认 |
| --- | --- |
| 每天第一次见面 | 打招呼 |
| 离开半小时以上回来 | 欢迎回来 |
| 连续用了 50 分钟没歇过 | 劝你起来走走；不理他的话隔 30 分钟、1 小时、2 小时再提 |
| 听劝休息完回来 | 打个气 |
| 到了下班时间（18:30）你还在 | 劝收工，每天一次 |
| 过了睡觉时间（23:30）你还在 | 催睡，每 45 分钟一次 |
| 当天翻译到第 20、50、100 段 | 邀个功 |
| 生词到期 | 考你一个 |

停手 5 分钟算一次休息。两次开口至少隔 10 分钟。他睡着时、正在翻译时、躲在屏幕边缘看你看视频时、你在全屏演示时不出声，所以双击哄睡就是免打扰。

台词默认由模型按当时的情况现写一句（一次很小的请求），没有 Key、请求失败或在设置里关掉时用内置台词。时间、间隔和每一类的开关都在「设置 → 陪伴」里。

## 生词本

选中单词或短语（三个词以内）翻译后会自动收录，在右键菜单的「生词本」里查看和删除。之后隔 1、3、7、16、35 天各考一次：他报出词，你想一想，点「看答案」，再告诉他记得还是忘了。忘了就从 1 天重新来，再查一次同一个词也是。数据存在 `~/Library/Application Support/Yimiao/vocabulary.json`。

## 取词是怎么做的

优先用辅助功能接口直接读选区。Chrome、VS Code、微信这类读不到选区的 App 走「兼容模式」：替你按一下 ⌘C，读完立刻把剪贴板还原。兼容模式只在鼠标拖选或双击后触发，可以在设置里关掉。

醒着时，选中的文字会发送给你配置的接口（默认 DeepSeek）。不想被翻译的时候让他睡觉。

## 其他

- **模型**：默认服务仍为 DeepSeek，可按上面的说明切换 Kimi。设置里可选择预设或手动输入模型名。Base URL 可以指向兼容 OpenAI Chat Completions 接口的服务；本机和局域网地址允许用 http。
- **服务出问题时**：DeepSeek 繁忙时不会拒绝请求，而是挂着连接发心跳，最长十分钟。所以他自己计时：20 秒没收到任何回答就报「一直没回话」，回答到一半停住 20 秒报「没动静了」，服务端中途掐断（`insufficient_system_resource` 等）也会说明。气泡标题会写明是「DeepSeek 服务异常」「网络问题」还是「设置需要检查」，并给出「重试」或「去设置」按钮；连续失败时再加「看服务状态」，打开 status.deepseek.com。设置里的「测试连接」同样最多等 20 秒，等待时显示秒数，可以随时取消。
- **他怎么知道在放视频**：播放器、浏览器和视频会议在画面播放时都会向系统申请「别让显示器休眠」，暂停就撤回，他看的是这个信号。后台放音乐不算；caffeinate、Amphetamine 这类防休眠工具被排除在外。躲着的时候选中文字，他照样会跳过来翻译，说完回到边缘。不想要可以在「设置 → 桌宠」里关。
- **从别的工具喂文字**：`open "yimiao://translate?text=Hello"`，可以接快捷指令、Raycast、脚本。加上 `&x=800&y=560`（从屏幕左下角算起的坐标）他会跳到那个位置去说。
- **权限和重新构建**：macOS 按签名认 App。构建脚本给临时签名指定了「按应用标识符识别」的要求，所以重新构建不会丢掉辅助功能授权和钥匙串访问。代价是授权跟着标识符 `io.github.hannah-bbbb.yimiao` 走，而不是绑定某一个二进制；想绑定到证书，就在钥匙串里放一个代码签名证书，或用 `CODESIGN_IDENTITY` 指定，脚本会改用它签名。
- **开关明明开着却不取词**：多半是系统里留着一条旧版本的授权。点猫的提醒气泡（或设置里的「去授权…」），他会先清掉自己那条旧记录，再请你重新打开开关。
- **他没反应时看日志**（只记录来源 App 和字数，不记录文字内容）：

  ```bash
  /usr/bin/log stream --predicate 'subsystem == "io.github.hannah-bbbb.yimiao"'
  ```

## 代码结构

```
Sources/Yimiao/
  App/        PetController 把所有部件串起来；OverlayPanel 是透明悬浮窗
  Pet/        PetBrain 决定姿势（状态、弹簧、随机动作）
              PetRenderer 画各个部件，PetStage 把部件做成图层交给 GPU 合成
  Bubble/     气泡的状态和 SwiftUI 视图
  Translate/  SelectionWatcher 取词，LanguageRouter 判断方向，Translator 流式请求
  Companion/  Companion 决定什么时候开口，Lines 是台词，Vocabulary 是生词本
  Settings/   偏好、钥匙串、设置窗口
  Support/    日志；Snapshot 离屏渲染
```

改了造型或气泡后不用启动 App 就能看效果：

```bash
swift run Yimiao --snapshot poses.png
swift run Yimiao --bubbles bubbles.png
swift run Yimiao --selection-layouts .build/selection-layouts.png
```

## 本地版本管理与变更规范

项目使用本地 Git 仓库，主分支为 `main`，未配置远程仓库。历史见 `git log --oneline`，功能变更与验证记录见 [CHANGELOG.md](CHANGELOG.md)，后续开发入口见 [开发记忆/目录.md](开发记忆/目录.md)。

- 每次提交只处理一个明确主题，标题使用 `fix(模块): 描述`、`feat(模块): 描述`、`docs: 描述` 或 `chore: 描述`。
- 用户可感知的改动须更新 `CHANGELOG.md`，注明日期、行为变化、验证方式及未验证范围。
- 提交前运行 `swift test` 和 `git diff --check`；交付可运行应用时再运行 `bash Scripts/build.sh`。
- `.build/`、`build/`、本机环境文件和日志由 `.gitignore` 排除；API Key 继续只保存在系统钥匙串，不提交密钥或个人设置。
- 用 `git status --short` 检查待提交内容，用 `git show <提交号>` 查看修改；回退已提交修复时优先使用 `git revert <提交号>`，保留历史记录。
