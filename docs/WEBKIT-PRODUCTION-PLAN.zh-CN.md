# 正式迁移范围：原 ieynec UI + WebKit + 官方 Lite

## 用户最新决策

停止自研完整版uBO移植，改用官方uBO Lite。用户要的是原项目的完工WebKit浏览器，不是独立测试宿主。不会再发布不同UI的工具当作阶段交付，也不会用换色/换标题代替原UI接线。

自研仓库永久删除受GitHub授权限制，现已归档停用；状态如实记录。旧发布的源码/许可证归档属于合规保留，不等于继续插件开发。用户截图和访问记录不上传公开仓库。

## 生产路径（尚未接通）

必须迁移实际的以下链路，而非另写首页：

1. `browser/Reynard/main.swift`：真正启动UIKit app，不再依赖Gecko入口。
2. `Client/SessionManagement/SessionManager.swift`：会话创建/代理、激活、生命周期、设置、历史和外部响应保持。
3. `Client/TabManagement/Tab.swift`、`TabManagerImpl.swift`：原标签页和普通/私密模型、状态恢复、popup与窗口归属。
4. `Client/Interface/ContentView/WebContentView.swift`：保留原容器层级、工具栏滚动与刷新指示，把实际引擎view换为WKWebView，不添加测试工具栏。
5. `Client/Interface/BrowserViewController.swift` 及原菜单/设置/书签/历史/下载控制器：逐个连接真实后端，禁止用空实现让编译通过。
6. `Client/Interface/Addons/AddonCoordinator.swift`：保留原扩展入口，实际托管官方Lite上下文、权限、tab/window事件、popup和设置页。不能借用Safari app内的扩展开关。

上面路径均相对 `browser/Reynard/`。生产UI当前仍使用Gecko类型，迁移尚未完成。

## 官方 Lite，而不是另一份自研过滤器

- 固定官方Safari包及哈希，按包原样接入。新的暂存器不会修改manifest、后台、列表和规则。
- 当前固定包 `2026.1116.1650` 的Safari背景页是非持久module scripts，不是Chromium service worker；先前合成MV3 worker超时不能据此判其不可用。
- 清单声明Safari18.6，最低系统与SDK兼容策略需落实到正式目标并验证，不静默宣称原iOS13部署仍全部可用。
- 验证默认真实列表、权限/模式、声明式网络规则、外观过滤/scriptlet、开关/站点例外、后台恢复；只检测网络请求或只解析包不算完成。
- 不宣称Lite自动解决所有站点问题，不做“比Lite更强”的自研目标，也不把Lite兼容等同任意Firefox扩展兼容。

## UI、功能与数据约束

- 原名称ieynec、图标、颜色、布局、顶部/底部栏、标签页、菜单、设置、手势与现有动画策略保留。
- 导航/前进后退/重载/停止、桌面模式、缩放、查找、分享、打印、下载/外部打开、权限、popup、阅读模式、历史/书签/恢复需真实实现。
- 新全屏方向需求：先竖屏；旋转传感器只给左下建议；用户点击后固定对应横屏，不再跟重力切换；app按钮回竖；退出全屏回竖。系统原生全屏的公开API限制必须单列，不声称能定制内部系统按钮。
- 数据迁移先可回滚备份、只读投影和事务验证，原Gecko profile/旧库不删除；不能把opaque state硬塞进WK。私密cookie、URL/title持久化边界分别审计。
- 运行继续使用原蜂窝＋sing-box，不添加浏览器代理/VPN、配对激活JIT、私有API或越狱要求。
- 公开API无法等价的功能必须明确列为未解决/待决策，不偷偷删掉、灰掉或用假返回值算完成。

## 完工门槛（未满足，不能宣称正式交付）

- [ ] 原UI真实运行在WK生产路径，主要操作与界面验收通过，不是合成组件截图。
- [ ] 生命周期、普通/私密隔离、冷启动首请求、恢复和迁移/回滚通过。
- [ ] 官方Lite在自有宿主内真实工作，默认列表和用户交互经过测试，不是固定几条测试规则。
- [ ] 下载、权限、popup、阅读模式、视频/iframe/MSE/DRM/PiP等逐项验收，未通过项如实列出。
- [ ] 原UI私有API和Gecko SDK/runtime/Helper/链接/缓存依赖清理；OpenIn保留并工作。
- [ ] 新构建/IPA verifier按真实WebKit app和OpenIn检查，不继续要求/伪造Gecko Helper。
- [ ] 完整archive与iPhone arm64 IPA结构/来源/签名元数据通过。
- [ ] 用户iPhone＋SideStore＋蜂窝/sing-box实际测试；开发者没有设备的项目不标实机通过。

当前内部`webkit-core.yml`只验证核心和官方包字节完整性，不会产生用户安装包，也不勾选以上完工项。
