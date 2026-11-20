# ieynec — 基于原项目的完整 WebKit 迁移（进行中）

**当前尚未完工。生产主界面仍使用 Gecko，没有满足原 UI/功能要求的完整 WebKit IPA。不会再用独立测试壳或源码检查点冒充交付。**

## 当前方向

- 以原 [Reynard-Fennec-iOS](https://github.com/kirokko/Reynard-Fennec-iOS) 的 **ieynec** 为唯一浏览器基础，保留已有 UI、图标资源、布局、工具栏、菜单、设置及交互/动画策略。
- 只替换引擎和必要的平台适配，不引入 Floorp UI、Safari 风格测试栏或另一个浏览器架构。
- **停止自研完整版 uBO 移植。广告过滤改用官方 uBO Lite Safari 包，不开发新的过滤引擎/规则转换器。**
- 原仓库、原版本、已安装应用和用户数据不删除、不覆盖。WebKit 生产入口、迁移事务和实机验收完成之前不标“完工”。

[正式迁移范围与完成门槛](docs/WEBKIT-PRODUCTION-PLAN.zh-CN.md) · [机器可读状态](SOURCE-STATUS.json)

## 旧实验已退役

`v0.0.1-device-probe.1` 的 `ieynec WK Test` 是历史诊断宿主，**不是原项目 UI**，已停止开发，发布页已标退役。旧的三个 Gecko workflow 和独立测试 IPA workflow 均禁用，不再为它们触发构建。

自研 uBO 仓库已归档停用；永久删除尝试被 GitHub 的 `delete_repo` 权限限制阻止，**不能把“归档”写成“删除完成”**。旧测试包对应的补丁/源码归档和上游源码仍附在旧浏览器诊断发布中，仅用于许可证合规、重建和历史追踪，不作为独立插件继续开发。

历史目录 `ports/ublock-webkit/`、`tools/ublock/`、`tests/iphone-host/` 等暂留用于对应源码和可追溯性，不是当前产品实现。旧证据中的成功/失败都保留，不将它们解释为 Lite 或正式浏览器已完成。

## 官方 Lite 接入起点

固定官方 `uBOLite_2026.1116.1650.safari.zip`，下载地址及 GitHub SHA-256 在 [`tools/webextensions/official-lite.json`](tools/webextensions/official-lite.json)。Safari 版本使用 MV3、非持久 module background scripts；**不是先前合成 MV3 service-worker fixture**。包声明最低 Safari18.6，正式工程需落实相应最低系统策略。

安全暂存工具只校验/解包固定包，逐文件保持原样，不改 manifest、不替换后台、不添加合成规则或篡改默认列表：

```sh
python3 tools/webextensions/stage-official-lite.py path/to/official.safari.zip path/to/NEW-directory
python3 tools/webextensions/test-stage-official-lite.py path/to/official.safari.zip
```

Windows 使用 `py -3`。**包完整性校验不等于 WKWebExtension 运行兼容，原生 Lite 接入尚未验收。** Safari App Store 安装的扩展也不会自动出现在自有 WKWebView 中，需要宿主实际接入。

## 工程状态

真实 `WebKitSession`、普通/私密 profile、只读旧会话投影已经存在。新增 profile 扩展控制器绑定保证在创建标签页之前完成，并拒绝跨 website store 和绕过控制器的 popup 配置；它不等于 Lite 初始化或规则安装成功。

原 `SessionManager`、`Tab`、`WebContentView`、`BrowserViewController` 和扩展协调器的生产接线仍需完成。Gecko SDK/Helper、旧 UI 私有 API、下载/权限/阅读模式/视频与数据迁移等未完成，不删难迁移功能求编译，不做空成功回调。

唯一恢复使用的 `webkit-core.yml` 是**内部工程验证**：arm64核心编译、实际WK核心测试、官方Lite逐字节暂存检查。它不构建浏览器 IPA，不验收正式 UI，也不代表 Lite 原生运行通过。

```sh
node tools/ci/WebKitBaseline.mjs
node --test tests/*.test.mjs
```

原应用源码/UI资源保护基线保留；进入生产接线时按明确修改清单更新审核门槛，而不是绕过检查。

## 原项目与许可证

原 Gecko README 见 [`docs/GECKO-BASELINE-README.md`](docs/GECKO-BASELINE-README.md)，其构建/安装说明只对应历史 Gecko 工程，不是 WebKit 交付指南。原应用展示名仍是 **ieynec**。

保留 Reynard/Minh Ton、Raymond Hill及所有原作者的版权、[GPL v3](LICENSE)、[Gecko MPL-2.0](LICENSE.firefox) 与第三方声明。原始浏览器仓库和回滚版本不受本项目退役实验影响。
