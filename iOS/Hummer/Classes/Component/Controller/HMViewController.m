//
//  HMViewController.h
//  Hummer
//
//  Copyright © 2019年 didi. All rights reserved.
//

#import "HMViewController.h"
#import "Hummer.h"
#import "HMJSGlobal.h"
#import <Hummer/HMBaseExecutorProtocol.h>
#import "HMBaseValue.h"

#if __has_include(<SocketRocket/SRWebSocket.h>)
#import <SocketRocket/SRWebSocket.h>
#endif

@interface HMViewController ()

@property (nonatomic, strong) UIView *naviView;
@property (nonatomic, strong) UIView *hmRootView;

@property (nonatomic, weak) HMJSContext  * context;
@property (nonatomic, weak) UIView * pageView;

@end

@implementation HMViewController

+ (instancetype)hmxPageControllerWithURL:(NSString *)URL
                                  params:(NSDictionary *)params {
    if (!URL) {
        return nil;
    }
    return [[self alloc] initWithURL:URL params:params];
}

- (instancetype)initWithURL:(NSString *)URL
                     params:(NSDictionary *)params {
    if (self = [super init]) {
        self.URL = URL ;
        self.params = params;
    }
    return self;
}

- (void)addCustomNavigationView:(UIView *)customNaviView {
    if (nil == customNaviView) {
        return;
    }
    
    [self.naviView removeFromSuperview];
    [self.view addSubview:customNaviView];
    self.naviView = customNaviView;
    
    CGFloat naviHeight = self.naviView ? CGRectGetHeight(self.naviView.frame) : 0;
    CGFloat hmHeight = CGRectGetHeight(self.view.bounds) - naviHeight;
    CGFloat hmWidth = CGRectGetWidth(self.view.bounds);
    
    CGRect containerFrame = CGRectMake(0, naviHeight, hmWidth, hmHeight);
    self.hmRootView.frame = containerFrame;
}

- (void)initHMRootView {
    /** hummer渲染view */
    self.hmRootView = [[UIView alloc] initWithFrame:self.view.bounds];
    self.hmRootView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.hmRootView];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    self.automaticallyAdjustsScrollViewInsets = NO;
    
    [self initHMRootView];
    
    if (!self.hm_pageID.length) {
        self.hm_pageID = @([self hash]).stringValue;
    }
    
    if ([[NSURL URLWithString:self.URL].pathExtension containsString:@"js"] && ([self.URL hasPrefix:@"http"] ||[self.URL hasPrefix:@"https"]))
    {// hummer js 模式加载
        __weak typeof(self)weakSelf = self;
        [HMJavaScriptLoader loadBundleWithURL:[NSURL URLWithString:self.URL] onProgress:^(HMLoaderProgress *progressData) {
        } onComplete:^(NSError *error, HMDataSource *source) {
            __strong typeof(self) self = weakSelf;
            if (!error) {
                HMExecOnMainQueue(^{
                    NSString *script = [[NSString alloc] initWithData:source.data encoding:NSUTF8StringEncoding];
                    [self renderWithScript:script];
                });
            }
        }];
    }else {
        //hummer 离线包模式加载
        NSString * script = nil;
        if (self.loadBundleJSBlock) {
            script = HM_SafeRunBlock(self.loadBundleJSBlock,self.URL);
        }else if ([[NSURL URLWithString:self.URL].pathExtension containsString:@"js"] && [self.URL hasPrefix:@"file"]){
            script = [NSString stringWithContentsOfURL:[NSURL URLWithString:self.URL] encoding:NSUTF8StringEncoding error:nil];
        }
        [self renderWithScript:script];
    }
}

#pragma mark -渲染脚本

- (void)renderWithScript:(NSString *)script {
    if (script.length == 0) {
        return;
    }
    
    //设置页面参数
    NSMutableDictionary * pData = [NSMutableDictionary dictionary];
    if (self.URL) {
        pData[@"url"]=self.URL;
    }
    pData[@"params"] = self.params ?: @{};
    HMJSGlobal.globalObject.pageInfo = pData;
    
    //渲染脚本之前 注册bridge
    HMJSContext *context = [HMJSContext contextInRootView:self.hmRootView];
    HM_SafeRunBlock(self.registerJSBridgeBlock,context);
    
    //执行脚本
    [context evaluateScript:script fileName:self.URL];
    self.pageView = self.hmRootView.subviews.firstObject;
    self.context = [[HMJSGlobal globalObject] currentContext:self.pageView.hmContext];
    
    //发送加载完成消息
    [self callJSWithFunc:@"onCreate" arguments:@[]];
}

#pragma mark - View 生命周期管理
- (BOOL)hm_didClickGoBack {
    if ([[self callJSWithFunc:@"onBack" arguments:@[]] toBool]) {return YES;}
    if ([self respondsToSelector:@selector(hm_triggerNativeGoBack)]) {
        [self hm_triggerNativeGoBack];
    }else{
        if (self.navigationController) {
            [self.navigationController popViewControllerAnimated:YES];
        }
    }
    return NO;
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self callJSWithFunc:@"onAppear" arguments:@[]];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self callJSWithFunc:@"onDisappear" arguments:@[]];
}

- (void)didMoveToParentViewController:(UIViewController *)parent {
    if (!parent) {
        id pageResult = nil;
        HMBaseValue * jsPageResult = self.pageView.hmContext[@"Hummer"][@"pageResult"];
        if (!jsPageResult.isNull || !jsPageResult.isUndefined) {
            if (jsPageResult.isObject) {
                pageResult = jsPageResult.toObject;
            }else if (jsPageResult.isNumber){
                pageResult = jsPageResult.toNumber;
            }else if (jsPageResult.isBoolean){
                pageResult = @(jsPageResult.toBool);
            }
        }
        HM_SafeRunBlock(self.hm_dismissBlock,pageResult);
    }
}

- (void)dealloc {
    [self callJSWithFunc:@"onDestroy" arguments:@[]];
}

#pragma mark - Call Hummer

- (HMBaseValue *)callJSWithFunc:(NSString *)func arguments:(NSArray *)arguments {
    HMBaseValue * page = self.pageView.hmValue;
    if ([page hasProperty:func]) {
        return [page invokeMethod:func withArguments:arguments];
    }
    return nil;
}

#ifdef DEBUG
#if __has_include(<SocketRocket/SRWebSocket.h>)

- (void)openWebSocketWithUrl:(NSString *)wsURLStr
{
    if (wsURLStr.length == 0) {
        return;
    }
    
//    NSString *wsURLStr = @"ws://172.23.163.148:9000/";
    NSURL *wsURL = [NSURL URLWithString:wsURLStr];
    if (wsURL) {
        SRWebSocket *webSocket = [[SRWebSocket alloc] initWithURL:wsURL];
        webSocket.delegate = self;
        [webSocket open];
    }
}

#pragma mark - SRWebSocketDelegate

- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessage:(id)message {
    id object = _HMObjectFromJSONString(message);
    if ([object isKindOfClass:[NSDictionary class]]) {
        NSDictionary *urlParam = [object valueForKey:@"params"];
        NSString *URLString = [urlParam valueForKey:@"url"];
        NSURL * URL  = [NSURL URLWithString:URLString];
        if (!URL) {
            return;
        }
        
        [self callJSWithFunc:@"onDestroy" arguments:@[]];
        [self.hmRootView.subviews enumerateObjectsUsingBlock:^(__kindof UIView * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            [obj removeFromSuperview];
        }];
        
        __weak typeof(self)weakSelf = self;
        [HMJavaScriptLoader loadBundleWithURL:URL onProgress:^(HMLoaderProgress *progressData) {
        } onComplete:^(NSError *error, HMDataSource *source) {
            __strong typeof(self) self = weakSelf;
            if (!error) {
                HMExecOnMainQueue(^{
                    NSString *script = [[NSString alloc] initWithData:source.data encoding:NSUTF8StringEncoding];
                    [self renderWithScript:script];
                });
            }
        }];
    }
    NSLog(@"----->>> %@", message);
}

- (void)webSocketDidOpen:(SRWebSocket *)webSocket {
    NSLog(@"----->>> %@", @"webSocketDidOpen");
}

- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error {
    NSLog(@"----->>> %@", error.localizedFailureReason);
}

#endif
#endif

@end
