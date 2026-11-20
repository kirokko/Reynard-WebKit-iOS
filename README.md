# ieynec — WebKit 迁移工程与 iPhone 测试宿主

**正式浏览器的原 UI 迁移仍未完成。新增独立 `ieynec WK Test` 真机测试目标，可由 `device-probe.yml` 构建供 SideStore 重签的 IPA，不替换原 ieynec。** 安装包只以成功构建/发布的实际附件为准；没有实机通过承诺。

[测试宿主安装与限制](docs/IPHONE-WEBKIT-TEST.zh-CN.md)：真实 WKWebView 网页浏览、内置 uBO 研究包、合成网络测试、原版面板、临时自定义规则和错误报告。**测试宿主不是原 UI 迁移成品，扩展没有已启用的默认广告列表，也不是完整兼容。**

> 当前生产入口 [`browser/Reynard/main.swift`](browser/Reynard/main.swift) 仍调用 `GeckoRuntime.main`。单独的 WebKit 模块/探测并不等于主界面已换引擎。**不要把本仓库原有构建脚本生成的 Gecko 包当作 WebKit 包。**

本独立项目从 [kirokko/Reynard-Fennec-iOS](https://github.com/kirokko/Reynard-Fennec-iOS/tree/port/full-ubo-webkit) 的迁移分支提取，保留该分支可达的提交历史、原 UI、资源、应用展示名 **ieynec** 和旧实现，尚未完成生产接线。不会覆盖原仓库、正式版本或用户数据，也没有创建一个简陋 WKWebView 壳冒充迁移成品。

[源码检查点预发布](https://github.com/kirokko/Reynard-WebKit-iOS/releases) · [准确状态](SOURCE-STATUS.json) · [迁移审计](docs/webkit-migration/README.md)

## 已有代码与证据

- `browser/WebKitEngine/WebKitSession.swift`：真实 WKWebView 会话基础，含普通/私密 store、导航/KVO、错误及进程终止处理；**未接入生产 SessionManager/UI**。
- `browser/WebKitEngine/LegacySessionProjection.swift`：旧 Gecko 导航状态的只读 URL/title 投影，不改旧库，不声称恢复原生 WKBackForwardList。
- `tests/webkit-smoke/`：实际 WebKit 和扩展能力的独立原生诊断，不能当成完整浏览器测试。
- `docs/webkit-migration/`：审计、原始结果、未完成项和实机清单。已有成功结果来自母项目的精确提交/run，不是新仓库的完整 archive 或实机验收。

完整版 uBO 的移植实验已单独发布在 [uBlock-Origin-WebKit](https://github.com/kirokko/uBlock-Origin-WebKit)。它仍是 probe-only，不是 Lite，也不是完整兼容成品；独立原生 CI 出现 Worker 超时，失败已披露。本浏览器也没有因此获得完整 uBO 能力。

## 尚未完成，不能发布 IPA

| 项目 | 当前状态 |
|---|---|
| 生产入口 / 主界面 | **仍为 Gecko，未接 WebKit** |
| 原 UI、手势、下载、权限、阅读模式等的 WebKit 适配 | 未完成 |
| 扩展安装/权限/后台、完整 uBO | 未完成 |
| 视频旋转建议按钮、点击后保持方向 | 未实现到 WebKit 生产路径 |
| 用户数据迁移、回滚和私密数据审计 | 未完成 |
| 移除 Gecko SDK/Helper/targets | 未完成 |
| 清理旧 UI 私有 API | 未完成；不标记整个工程已满足仅公开 API |
| 完整 WebKit app archive / IPA / SideStore | **没有，未验收** |
| 性能及蜂窝网络＋sing-box | 待实际设备测试，不给出虚构提速数字 |

`v0.0.0-source.1` 仍是不可安装的源码检查点。新增 `tests/iphone-host/` 是独立诊断应用目标，可生成测试 IPA；不改变上表正式浏览器迁移未完成的状态，也不提供正式版/App Store/TestFlight。

## 构建隔离

旧 Gecko workflow、SDK引用和打包脚本保留，但三个旧 workflow 在仓库设置单独禁用，避免生成 Gecko IPA 并误认为 WebKit 成果。

只为新增手动 `device-probe.yml` 恢复 Actions；它直接编译独立 `tests/iphone-host/`，不调用旧 app 工程/Gecko打包链。gate验证WK网页、JS、内置本机页、非持久扩展上下文加载及IPA结构；**不要求uBO功能全通过，也绝不把绿色job当作完整兼容**。失败的过滤/后台状态保存在实际报告中，并在测试宿主可见。

不要启用旧 Build SideStore IPA：它仍是 Gecko。正式迁移需要另行完成生产接线与构建/验收门槛。

## 本地只读检查

Windows 可运行，不需要本地 Xcode：

```sh
node tools/ci/WebKitBaseline.mjs
node --test tests/*.test.mjs
```

基线仍保护原应用源码、UI资源、数据写入和旧打包文件；本次没有放宽 gate 或删功能求编译。这些检查不能证明 WebKit app 已完成。

## 原 Gecko 文档与许可证

原 README 完整保存在 [`docs/GECKO-BASELINE-README.md`](docs/GECKO-BASELINE-README.md)。它描述的是原 Gecko 浏览器/历史包；内部相对链接仍按原仓库根目录解释，**不是本项目 WebKit 发行说明**。

保留 Reynard/Minh Ton 及所有原作者的版权、[GPL v3](LICENSE)、[Gecko MPL-2.0](LICENSE.firefox) 和第三方声明。不要改掉现有应用名称、标识和资源冒充新成品。

English: **Incomplete production browser migration (still Gecko), plus a separate disposable iPhone WKWebView/WKWebExtension test host. Only the new manual test-host workflow is enabled. Its IPA is not the original UI migration and does not establish full uBO compatibility or physical-device acceptance.**
