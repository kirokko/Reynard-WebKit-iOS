// SPDX-License-Identifier: GPL-3.0-or-later
// Separate disposable test host. NOT the production ieynec UI migration.
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import "FixtureServer.h"

@interface DeviceHost : UIViewController <UITextFieldDelegate, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, UIAdaptivePresentationControllerDelegate, WKWebExtensionControllerDelegate, WKWebExtensionTab, WKWebExtensionWindow>
@property(nonatomic, strong) WKWebView *webView;
@property(nonatomic, strong) WKWebView *statusView;
@property(nonatomic, strong) WKWebsiteDataStore *store;
@property(nonatomic, strong) WKWebExtensionController *controller;
@property(nonatomic, strong) WKWebExtensionContext *context;
@property(nonatomic, strong) FixtureServer *server;
@property(nonatomic, strong) UITextField *address;
@property(nonatomic, strong) UILabel *stateLabel;
@property(nonatomic, strong) UIButton *extensionButton;
@property(nonatomic, strong) NSMutableDictionary *report;
@property(nonatomic, strong) NSDictionary *lastStatus;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, strong) NSDate *started;
@property(nonatomic) BOOL extensionLoaded;
@property(nonatomic) BOOL parsing;
@property(nonatomic) BOOL automation;
@property(nonatomic) BOOL baselineStarted;
@property(nonatomic) BOOL autoNetworkStarted;
@property(nonatomic) BOOL autoFinished;
@property(nonatomic) BOOL warmReloaded;
@property(nonatomic) NSUInteger generation;
@end
@implementation DeviceHost
- (UIButton *)button:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem]; [button setTitle:title forState:UIControlStateNormal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside]; return button;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.started = NSDate.date; self.automation = getenv("WK_DEVICE_AUTOMATION") != NULL;
    NSData *build = [NSData dataWithContentsOfURL:[NSBundle.mainBundle URLForResource:@"build" withExtension:@"json"]];
    self.report = [@{@"kind":@"disposable-WebKit-device-test-host", @"productionBrowserMigrationComplete":@NO,
        @"fullUBlockOriginVerified":@NO, @"physicalDeviceVerifiedByDeveloper":@NO,
        @"OS":NSProcessInfo.processInfo.operatingSystemVersionString,
        @"build":build ? [NSJSONSerialization JSONObjectWithData:build options:0 error:nil] ?: @{} : @{},
        @"automation":@(self.automation)} mutableCopy];
    self.store = WKWebsiteDataStore.nonPersistentDataStore;
    WKWebExtensionControllerConfiguration *host = WKWebExtensionControllerConfiguration.nonPersistentConfiguration;
    host.defaultWebsiteDataStore = self.store;
    self.controller = [[WKWebExtensionController alloc] initWithConfiguration:host]; self.controller.delegate = self;
    self.report[@"extensionStoragePersistent"] = @(host.persistent);
    WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
    configuration.websiteDataStore = self.store; configuration.webExtensionController = self.controller;
    configuration.allowsInlineMediaPlayback = YES;
    self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    self.webView.navigationDelegate = self; self.webView.UIDelegate = self;
    [self.controller didOpenWindow:self]; [self.controller didOpenTab:self];
    [self.controller didFocusWindow:self]; [self.controller didActivateTab:self previousActiveTab:nil];
    self.address = [UITextField new]; self.address.placeholder = @"输入网址（默认HTTPS）"; self.address.borderStyle = UITextBorderStyleRoundedRect;
    self.address.keyboardType = UIKeyboardTypeURL; self.address.autocorrectionType = UITextAutocorrectionTypeNo;
    self.address.autocapitalizationType = UITextAutocapitalizationTypeNone; self.address.returnKeyType = UIReturnKeyGo; self.address.delegate = self;
    self.stateLabel = [UILabel new]; self.stateLabel.numberOfLines = 2; self.stateLabel.font = [UIFont systemFontOfSize:12];
    self.stateLabel.text = @"WebKit真机测试宿主 · 临时数据 · 不是正式浏览器";
    UIStackView *navigation = [[UIStackView alloc] initWithArrangedSubviews:@[[self button:@"后退" action:@selector(back)], [self button:@"前进" action:@selector(forward)], [self button:@"刷新" action:@selector(reload)], [self button:@"测试页" action:@selector(fixture)]]];
    navigation.distribution = UIStackViewDistributionFillEqually;
    self.extensionButton = [self button:@"启用uBO" action:@selector(toggleExtension)];
    UIStackView *tools = [[UIStackView alloc] initWithArrangedSubviews:@[self.extensionButton, [self button:@"原版面板" action:@selector(popup)], [self button:@"状态/规则" action:@selector(status)], [self button:@"报告" action:@selector(exportReport)]]];
    tools.distribution = UIStackViewDistributionFillEqually;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.address, navigation, self.stateLabel, tools, self.webView]];
    stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 5; stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack]; UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[[stack.topAnchor constraintEqualToAnchor:safe.topAnchor constant:4], [stack.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor], [stack.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:6], [stack.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-6], [self.address.heightAnchor constraintEqualToConstant:40], [navigation.heightAnchor constraintEqualToConstant:36], [tools.heightAnchor constraintEqualToConstant:40], [self.stateLabel.heightAnchor constraintEqualToConstant:34]]];
    self.server = [FixtureServer new]; NSError *error = nil;
    self.report[@"loopbackFixtureStarted"] = @([self.server start:&error]);
    if (error) { self.report[@"fixtureError"] = error.description; self.stateLabel.text = @"本机测试页启动失败，可在地址栏测试普通HTTPS网页"; }
    else [self fixture];
    __weak DeviceHost *weak = self;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) { [weak tick]; }];
}
- (void)message:(NSString *)title text:(NSString *)text {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:text preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    UIViewController *target = self.presentedViewController ?: self; if (![target isKindOfClass:UIAlertController.class]) [target presentViewController:alert animated:YES completion:nil];
}
- (BOOL)textFieldShouldReturn:(UITextField *)field {
    NSString *text = [field.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (![text containsString:@"://"]) text = [@"https://" stringByAppendingString:text];
    NSURL *url = [NSURL URLWithString:text];
    if (!url.host.length || url.user.length || url.password.length || ![@[@"http",@"https"] containsObject:url.scheme.lowercaseString]) {
        [self message:@"网址无效" text:@"仅接受不包含用户名/密码的HTTP或HTTPS网址。"]; return NO;
    }
    [field resignFirstResponder]; [self.webView loadRequest:[NSURLRequest requestWithURL:url]]; return YES;
}
- (void)back { [self.webView goBack]; }
- (void)forward { [self.webView goForward]; }
- (void)reload { [self.webView reload]; }
- (void)fixture { [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"http://127.0.0.1:8765/port/index.html"]]]; }
- (void)toggleExtension {
    if (self.parsing) return;
    if (self.extensionLoaded) {
        NSError *error = nil;
        if (![self.controller unloadExtensionContext:self.context error:&error]) { [self message:@"卸载失败" text:error.description ?: @"未知错误"]; return; }
        self.generation++; self.extensionLoaded = NO; self.context = nil; self.lastStatus = nil;
        self.report[@"extensionLoaded"] = @NO; self.stateLabel.text = @"扩展已真正卸载；网页重载以移除旧内容脚本/CSS";
        [self.extensionButton setTitle:@"启用uBO" forState:UIControlStateNormal]; [self.webView reload]; return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"启用研究版uBO？" message:@"只加载固定来源的非官方完整版移植包，授予读取/修改所有网页及存储等清单权限。仅合成规则，没有默认广告列表；后台、scriptlet等可能失败。所有扩展/网页数据为本应用临时数据，启动可能重置规则。不要用于真实账号或日常隐私浏览。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"同意并测试" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self enableExtension]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)enableExtension {
    if (self.extensionLoaded || self.parsing) return;
    self.parsing = YES; self.extensionButton.enabled = NO; NSUInteger generation = ++self.generation;
    self.stateLabel.text = @"正在解析固定uBO测试包…";
    NSURL *directory = [NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"ubo"];
    [WKWebExtension extensionWithResourceBaseURL:directory completionHandler:^(WKWebExtension *extension, NSError *error) {
        if (generation != self.generation) return;
        self.parsing = NO; self.extensionButton.enabled = YES;
        self.report[@"extensionParseErrors"] = extension ? [extension.errors valueForKey:@"description"] : @[];
        if (!extension || error || extension.errors.count) { self.report[@"extensionError"] = error.description ?: @"Manifest parse errors"; self.stateLabel.text = @"扩展解析失败；浏览器仍可独立测试"; return; }
        self.context = [[WKWebExtensionContext alloc] initForExtension:extension]; self.context.uniqueIdentifier = NSUUID.UUID.UUIDString;
        self.context.hasAccessToPrivateData = YES; // Explicit consent above; ONLY this disposable nonpersistent test store.
        for (NSString *permission in extension.requestedPermissions) [self.context setPermissionStatus:WKWebExtensionContextPermissionStatusGrantedExplicitly forPermission:permission];
        for (WKWebExtensionMatchPattern *pattern in extension.requestedPermissionMatchPatterns) [self.context setPermissionStatus:WKWebExtensionContextPermissionStatusGrantedExplicitly forMatchPattern:pattern];
        NSError *loadError = nil; self.extensionLoaded = [self.controller loadExtensionContext:self.context error:&loadError];
        self.report[@"extensionLoaded"] = @(self.extensionLoaded);
        if (!self.extensionLoaded) { self.report[@"extensionError"] = loadError.description ?: @"Native context load failed"; self.stateLabel.text = @"扩展加载失败；请导出报告"; return; }
        [self.extensionButton setTitle:@"停用uBO" forState:UIControlStateNormal]; self.stateLabel.text = @"扩展上下文已加载，不代表后台/过滤已成功";
        [self fixture];
        [self.context loadBackgroundContentWithCompletionHandler:^(NSError *backgroundError) {
            if (generation != self.generation || !self.extensionLoaded) return;
            if (backgroundError) { self.report[@"backgroundLoadError"] = backgroundError.description; self.stateLabel.text = @"扩展后台加载失败；可继续测试WebKit或导出报告"; }
            else self.report[@"backgroundContentLoadCallbackSucceeded"] = @YES;
        }];
    }];
}
- (void)popup { [self presentPage:@"popup-fenix.html" title:@"原版面板（开关尚未桥接DNR）" status:NO]; }
- (void)status { [self presentPage:@"port/device-status.html" title:@"真实状态 / 临时自定义规则" status:YES]; }
- (BOOL)presentPage:(NSString *)page title:(NSString *)title status:(BOOL)isStatus {
    if (!self.extensionLoaded) { [self message:@"尚未加载扩展" text:@"先点击“启用uBO”。若加载失败，请导出报告。"]; return NO; }
    if (self.presentedViewController) return NO;
    WKWebViewConfiguration *configuration = self.context.webViewConfiguration;
    if (!configuration) { [self message:@"扩展UI错误" text:@"没有 extension-owned webViewConfiguration"]; return NO; }
    if (isStatus) [configuration.userContentController addScriptMessageHandler:self name:@"deviceStatus"];
    WKWebView *view = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration]; view.navigationDelegate = self; view.UIDelegate = self;
    if (isStatus) self.statusView = view;
    UIViewController *pageController = [UIViewController new]; pageController.view = view; pageController.title = title;
    pageController.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(closePanel)];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:pageController];
    [self presentViewController:navigation animated:YES completion:nil]; navigation.presentationController.delegate = self;
    [view loadRequest:[NSURLRequest requestWithURL:[self.context.baseURL URLByAppendingPathComponent:page]]]; return YES;
}
- (void)clearPanel {
    [self.statusView.configuration.userContentController removeScriptMessageHandlerForName:@"deviceStatus"]; self.statusView = nil;
}
- (void)closePanel { [self clearPanel]; [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController { [self clearPanel]; }
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
    NSURL *url = message.frameInfo.request.URL;
    if (message.webView != self.statusView || !message.frameInfo.mainFrame || ![url.scheme isEqual:self.context.baseURL.scheme] || ![url.host isEqual:self.context.baseURL.host] || ![message.body isKindOfClass:NSDictionary.class]) return;
    [self observeStatus:message.body];
}
- (NSDictionary *)json:(id)value {
    if (![value isKindOfClass:NSString.class]) return nil;
    id result = [NSJSONSerialization JSONObjectWithData:[value dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil]; return [result isKindOfClass:NSDictionary.class] ? result : nil;
}
- (void)observeStatus:(NSDictionary *)status {
    self.lastStatus = status; self.report[@"port"] = status;
    NSString *stage = status[@"network"][@"stage"];
    if ([stage isEqual:@"failed"]) self.stateLabel.text = @"uBO网络后端失败；打开“状态/规则”查看真实错误";
    else if ([stage isEqual:@"installed"]) self.stateLabel.text = [NSString stringWithFormat:@"DNR已安装%@条；不是完整uBO，后台/scriptlet另看状态", status[@"network"][@"installedRuleCount"] ?: @"?"];
    else self.stateLabel.text = [NSString stringWithFormat:@"uBO网络：%@；完整兼容未验证", stage ?: @"等待状态"];
}
- (void)tick {
    if (self.automation && !self.autoFinished && -self.started.timeIntervalSinceNow > 100) { self.report[@"automationTimeout"] = @YES; [self finishAutomation]; }
    if (self.webView.loading || ![self.webView.URL.absoluteString hasPrefix:@"http://127.0.0.1:8765/port/"]) return;
    [self.webView evaluateJavaScript:@"({status:document.documentElement.getAttribute('data-ubo-port-status'),network:document.documentElement.getAttribute('data-device-network'),bridgeError:document.documentElement.getAttribute('data-ubo-port-bridge-error')})" completionHandler:^(id value, NSError *error) {
        if (self.webView.loading || ![value isKindOfClass:NSDictionary.class]) return;
        NSDictionary *status = [self json:value[@"status"]]; if (status && self.extensionLoaded) [self observeStatus:status];
        NSDictionary *network = [self json:value[@"network"]]; if (network) self.report[@"controlledNetwork"] = network;
        if ([value[@"bridgeError"] isKindOfClass:NSString.class]) self.report[@"diagnosticBridgeError"] = value[@"bridgeError"];
        if (!self.automation || self.autoFinished || self.autoNetworkStarted) return;
        NSString *stage = status[@"network"][@"stage"];
        NSString *upstream = status[@"upstream"][@"stage"];
        BOOL settled = [@[@"ready",@"failed",@"initialization-timeout"] containsObject:upstream ?: @""];
        if ([stage isEqual:@"installed"] && settled && !self.warmReloaded) { self.warmReloaded = YES; [self.webView reload]; return; }
        if (([stage isEqual:@"installed"] && settled) || [stage isEqual:@"failed"] || (self.extensionLoaded && -self.started.timeIntervalSinceNow > 75)) {
            self.autoNetworkStarted = YES;
            [self.webView callAsyncJavaScript:@"return await runNetworkTest();" arguments:@{} inFrame:nil inContentWorld:WKContentWorld.pageWorld completionHandler:^(id result, NSError *testError) {
                if ([result isKindOfClass:NSDictionary.class]) self.report[@"controlledNetwork"] = result;
                if (testError) self.report[@"networkTestScriptError"] = testError.description;
                [self finishAutomation];
            }];
        }
    }];
}
- (NSURL *)writeReport:(NSString *)name {
    self.report[@"nativeExtensionErrors"] = self.context ? [self.context.errors valueForKey:@"description"] : @[];
    self.report[@"fullUBlockOriginVerified"] = @NO;
    NSData *data = [NSJSONSerialization dataWithJSONObject:self.report options:NSJSONWritingPrettyPrinted error:nil];
    NSURL *directory = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *url = [directory URLByAppendingPathComponent:name]; [data writeToURL:url atomically:YES]; return url;
}
- (void)finishAutomation {
    if (self.autoFinished) return; self.autoFinished = YES;
    NSDictionary *n = self.report[@"controlledNetwork"] ?: @{};
    BOOL passed = [self.lastStatus[@"network"][@"stage"] isEqual:@"installed"];
    for (NSString *name in @[@"blocked",@"important",@"xhr-only",@"image:image-only.txt"]) {
        NSDictionary *r = n[name]; passed &= [r[@"loaded"] isEqual:@NO] && ![r[@"timeout"] boolValue];
    }
    for (NSString *name in @[@"control",@"allowed",@"image-only",@"new-rule",@"image:control.png"]) passed &= [n[name][@"loaded"] isEqual:@YES];
    passed &= [n[@"serverHits"][@"/port/control.txt"] unsignedIntegerValue] > 0 && [n[@"serverHits"][@"/port/blocked.txt"] unsignedIntegerValue] == 0;
    self.report[@"controlledDNRPassed"] = @(passed);
    self.report[@"originalCosmeticObserved"] = @([n[@"cosmeticDisplay"] isEqual:@"none"]);
    self.report[@"originalScriptletObserved"] = @([n[@"scriptletObserved"] isEqual:@YES]);
    [self writeReport:@"simulator-report.json"];
}
- (void)exportReport {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导出本地诊断报告" message:@"不会自动上传。报告可能含错误信息、自定义规则片段等，请分享前检查。不会导出cookie或旧浏览器配置。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"选择保存/分享位置" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[[self writeReport:@"WKTest-report.json"]] applicationActivities:nil];
        share.popoverPresentationController.sourceView = self.view; share.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, 50, 1, 1);
        [self presentViewController:share animated:YES completion:nil];
    }]]; [self presentViewController:alert animated:YES completion:nil];
}
- (void)webView:(WKWebView *)view didFinishNavigation:(WKNavigation *)navigation {
    if (view != self.webView) return;
    if (!self.address.editing) self.address.text = view.URL.absoluteString;
    [self.controller didChangeTabProperties:WKWebExtensionTabChangedPropertiesURL | WKWebExtensionTabChangedPropertiesTitle | WKWebExtensionTabChangedPropertiesLoading forTab:self];
    if (self.automation && !self.baselineStarted && !self.extensionLoaded && [view.URL.path isEqual:@"/port/index.html"]) {
        self.baselineStarted = YES;
        [view callAsyncJavaScript:@"const response=await fetch('/port/blocked.txt?token=baseline'); return {answer:6*7,status:response.status,title:document.title};" arguments:@{} inFrame:nil inContentWorld:WKContentWorld.pageWorld completionHandler:^(id value, NSError *error) {
            if ([value isKindOfClass:NSDictionary.class]) self.report[@"webKitBaseline"] = value;
            if (error) self.report[@"baselineError"] = error.description;
            [self enableExtension];
        }];
    }
}
- (void)webView:(WKWebView *)view didCommitNavigation:(WKNavigation *)navigation {
    if (view == self.webView) [self.controller didChangeTabProperties:WKWebExtensionTabChangedPropertiesURL | WKWebExtensionTabChangedPropertiesLoading forTab:self];
}
- (void)webView:(WKWebView *)view didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    if (view == self.webView) { self.report[@"lastNavigationError"] = @{@"domain":error.domain,@"code":@(error.code)}; self.stateLabel.text = [NSString stringWithFormat:@"网页加载错误 %@/%ld",error.domain,(long)error.code]; }
}
- (void)webView:(WKWebView *)view didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error { [self webView:view didFailProvisionalNavigation:navigation withError:error]; }
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)view { self.report[@"webProcessTerminated"] = @YES; self.stateLabel.text = @"网页进程已终止；可手动刷新并导出报告"; }
- (void)webView:(WKWebView *)view decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void (^)(WKNavigationActionPolicy))decision {
    NSURL *url = action.request.URL; BOOL allowed;
    if (view != self.webView) allowed = ([url.scheme isEqual:self.context.baseURL.scheme] && [url.host isEqual:self.context.baseURL.host]) || [url.absoluteString isEqual:@"about:blank"];
    else allowed = [@[@"http",@"https",@"about",@"blob",@"data"] containsObject:url.scheme.lowercaseString] && !url.user.length && !url.password.length;
    decision(allowed ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel);
}
- (WKWebView *)webView:(WKWebView *)view createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)action windowFeatures:(WKWindowFeatures *)features {
    if (view == self.webView && !action.targetFrame && [@[@"http",@"https"] containsObject:action.request.URL.scheme.lowercaseString]) [view loadRequest:action.request];
    return nil; // Explicit single-tab test host, not production popup/tab equivalence.
}
- (void)webView:(WKWebView *)view runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completion {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"网页提示" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { completion(); }]];
    UIViewController *target = self.presentedViewController ?: self;
    if ([target isKindOfClass:UIAlertController.class]) completion(); else [target presentViewController:alert animated:YES completion:nil];
}
- (void)webView:(WKWebView *)view runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(BOOL))completion {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"网页确认" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) { completion(NO); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { completion(YES); }]];
    UIViewController *target = self.presentedViewController ?: self;
    if ([target isKindOfClass:UIAlertController.class]) completion(NO); else [target presentViewController:alert animated:YES completion:nil];
}
- (void)webView:(WKWebView *)view requestMediaCapturePermissionForOrigin:(WKSecurityOrigin *)origin initiatedByFrame:(WKFrameInfo *)frame type:(WKMediaCaptureType)type decisionHandler:(void (^)(WKPermissionDecision))decision { decision(WKPermissionDecisionDeny); }
- (NSArray *)webExtensionController:(WKWebExtensionController *)controller openWindowsForExtensionContext:(WKWebExtensionContext *)context { return @[self]; }
- (id<WKWebExtensionWindow>)webExtensionController:(WKWebExtensionController *)controller focusedWindowForExtensionContext:(WKWebExtensionContext *)context { return self; }
- (NSArray *)tabsForWebExtensionContext:(WKWebExtensionContext *)context { return @[self]; }
- (id<WKWebExtensionTab>)activeTabForWebExtensionContext:(WKWebExtensionContext *)context { return self; }
- (id<WKWebExtensionWindow>)windowForWebExtensionContext:(WKWebExtensionContext *)context { return self; }
- (WKWebView *)webViewForWebExtensionContext:(WKWebExtensionContext *)context { return self.webView; }
- (NSURL *)urlForWebExtensionContext:(WKWebExtensionContext *)context { return self.webView.URL; }
- (NSString *)titleForWebExtensionContext:(WKWebExtensionContext *)context { return self.webView.title; }
- (BOOL)isActiveForWebExtensionContext:(WKWebExtensionContext *)context { return YES; }
- (BOOL)isPrivateForWebExtensionContext:(WKWebExtensionContext *)context { return YES; }
- (NSUInteger)indexInWindowForWebExtensionContext:(WKWebExtensionContext *)context { return 0; }
- (void)webExtensionController:(WKWebExtensionController *)controller openOptionsPageForExtensionContext:(WKWebExtensionContext *)context completionHandler:(void (^)(NSError *))completion {
    BOOL shown = [self presentPage:@"dashboard.html" title:@"原版设置（未全部桥接）" status:NO];
    completion(shown ? nil : [NSError errorWithDomain:@"WKTestHost" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Could not present options page"}]);
}
@end

@interface DeviceApp : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation DeviceApp
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds]; self.window.rootViewController = [DeviceHost new]; [self.window makeKeyAndVisible]; return YES;
}
@end
int main(int argc, char **argv) { @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(DeviceApp.class)); } }
