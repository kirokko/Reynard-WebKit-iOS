# iPhone WebKit + 扩展测试宿主

这是用户要求立即在iPhone测试而新增的**独立诊断应用**，不是原浏览器UI迁移完成版。原app源码、UI、标识和数据不改。

## 安装

1. 到本仓库 Releases 下载实际成功构建的 `ieynec-WK-Test.ipa`，不是Source code ZIP。也可在成功的 `device-probe.yml` run取 `ieynec-WK-Test-IPA` artifact。
2. 对照同一run的 provenance / SHA256SUMS。IPA为arm64、iOS18.4+，只有一个测试app，无Gecko/Helper。
3. 用你已有的 SideStore 正常重签安装。显示名 **ieynec WK Test**、独立bundle ID `net.kirokko.ieynec.webkitprobe`，不应替换原 ieynec。若安装器显示要替换原浏览器，先停止并反馈。
4. SideStore自身的安装/签名条件不作改变。测试宿主运行不新增浏览器JIT激活、LocalDevVPN或代理步骤。WK执行由系统WebKit进程管理，不宣称已实测JIT策略或性能提升。

## 测试方法

- 初始显示本机测试页。地址栏可输入普通HTTPS网址，提供后退/前进/刷新；继续使用原有蜂窝＋sing-box环境，不修改路由。
- 点击 **启用uBO**，阅读并确认权限。这只加载固定哈希、独立实验ID的内置包，不是任意XPI安装器。
- 等待状态，点击测试页的 **检测实际网络阻断**。检查control到达服务器、blocked不达、例外/important/资源类型等。不要将所有失败请求都看成广告已拦截；超时不计为阻断成功。
- **原版面板** 仅用于观察原uBO界面；其电源/白名单/动态防火墙尚未同步DNR，不能以外观判断生效。
- **状态/规则** 使用真实消息API显示错误。可以写入临时user-filters测试编译（例如`||doubleclick.net^`）；存储写入不等于DNR更新，必须检查 `network.stage` / `conversion`。后台重启可能重置规则。
- **停用uBO** 是原生宿主实际卸载上下文，并重载页面清掉旧内容脚本/CSS。
- 遇到Worker超时、后台失败或网页异常，点击 **报告**，自己选择保存或分享JSON。不会自动上传；分享前检查自定义规则片段/错误内容。

## 数据和网络边界

- 网页使用新的 nonPersistent WKWebsiteDataStore，扩展使用nonPersistent控制器及每次新随机identity。启用时明确授权扩展访问这个临时测试store；不接入原app profile。
- 当前uBO bootstrap会写入合成规则、列表选择并关闭自动更新。**没有已启用的真实默认广告列表，不适合日用或登录真实账号。** 自定义规则不会保证持久化。
- 本机 `127.0.0.1:8765/port/` 服务仅提供内置合成页面/PNG/计数，不代理、转发网络，不监听LAN，不读取文件或cookie。无需电脑部署服务。
- 浏览普通网址走正常WKWebView系统网络；本app没有VPN、SOCKS或代理转发能力。sing-box是否对环回地址采用特殊策略，仍需实际手机验证。

## 测试范围与限制

单标签测试工具，非完整浏览器：未移植原UI、多标签、下载管理、阅读模式、视频旋转建议交互或数据迁移。相机/麦克风采集在宿主中拒绝；正常网页视频播放由WebKit处理，没有强制替换播放器。不是DRM/MSE/PiP验收。

CI实际链接iphoneos arm64，并运行同源码Simulator app。绿色gate只表示WK导航/JS、本机页、非持久扩展上下文加载以及IPA结构检查通过。`controlledDNRPassed`、原版CSS/scriptlet等另外记录，可能失败；完整uBO、SideStore和实机标记不冒充通过。

嵌入扩展来自非官方 `uBlock-Origin-WebKit v0.1.0-alpha.1`，仅额外加入两份extension-owned诊断页面，其余扩展文件逐字节核对。许可证、来源、对应上游源码链接及新增文件哈希在包内保留。此前独立原生CI有Compiler Worker超时，不能保证手机上正常过滤；应把真实结果反馈后再修。
