//
//  HMNGJSContext.m
//  Hummer
//
//  Created by 唐佳诚 on 2020/7/15.
//

#import <objc/runtime.h>
#if __has_include(<Hummer/HMJSExecutor.h>)
#import <Hummer/HMJSExecutor.h>
#endif
#import "HMJSCExecutor.h"
#import "HMJSContext.h"
#import "HMExportClass.h"
#import "NSObject+Hummer.h"
#import "HMUtility.h"
#import "HMInterceptor.h"
#import "HMBaseValue.h"
#import "HMExceptionModel.h"
#import "HMJSGlobal.h"
#import <Hummer/HMConfigEntryManager.h>
#import <Hummer/HMPluginManager.h>
#import <Hummer/HMDebug.h>
#import <Hummer/HMConfigEntryManager.h>
#import <Hummer/HMWebSocket.h>
NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, HMCLILogLevel) {
    HMCLILogLevelLog = 0,
    HMCLILogLevelDebug,
    HMCLILogLevelInfo,
    HMCLILogLevelWarn,
    HMCLILogLevelError
};

static inline HMCLILogLevel convertNativeLogLevel(HMLogLevel logLevel) {
    // T I W E F
    switch (logLevel) {
        case HMLogLevelTrace:
            return HMCLILogLevelDebug;
        case HMLogLevelInfo:
            return HMCLILogLevelLog;
        case HMLogLevelWarning:
            return HMCLILogLevelWarn;
        case HMLogLevelError:
            return HMCLILogLevelError;
        default:
            // 正常不会传递
            return HMCLILogLevelError;
    }
}

#ifdef HMDEBUG
API_AVAILABLE(ios(13.0))
#endif
@interface HMJSContext () // <NSURLSessionWebSocketDelegate>

@property (nonatomic, weak, nullable) UIView *rootView;

@property (nonatomic, strong, readwrite) id <HMBaseExecutorProtocol>context;

#ifdef HMDEBUG
@property (nonatomic, nullable, strong) NSURLSessionWebSocketTask *webSocketTask;

- (void)handleWebSocket;

#endif

@end

NS_ASSUME_NONNULL_END

@implementation UIView (HMJSContext)
- (HMJSContext *)hm_context {
    return objc_getAssociatedObject(self, _cmd);
}

- (void)setHm_context:(HMJSContext *)hmContext {
    objc_setAssociatedObject(self, @selector(hm_context), hmContext, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end

@implementation HMJSContext

- (void)dealloc {
    NSObject *componentViewObject = self.componentView.toNativeObject;
    if ([componentViewObject isKindOfClass:UIView.class]) {
        [((UIView *) componentViewObject) removeFromSuperview];
    }
    HMLogDebug(@"HMJSContext 销毁");
#ifdef HMDEBUG
    [self.webSocketTask cancel];
#endif
    [self.webSocketSet enumerateObjectsUsingBlock:^(HMWebSocket * _Nonnull obj, BOOL * _Nonnull stop) {
        [obj close];
    }];
}

+ (instancetype)contextInRootView:(UIView *)rootView {
    rootView.hm_context = [[HMJSContext alloc] init];
    rootView.hm_context.rootView = rootView;
    return rootView.hm_context;
}

- (instancetype)init {
    struct timespec createTimespec;
    HMClockGetTime(&createTimespec);
    self = [super init];
    _createTimespec = createTimespec;
    NSBundle *frameworkBundle = [NSBundle bundleForClass:self.class];
    NSString *resourceBundlePath = [frameworkBundle pathForResource:@"Hummer" ofType:@"bundle"];
    NSAssert(resourceBundlePath.length > 0, @"Hummer.bundle 不存在");
    NSBundle *resourceBundle = [NSBundle bundleWithPath:resourceBundlePath];
    NSAssert(resourceBundle, @"Hummer.bundle 不存在");
    // TODO(唐佳诚): 修改文件名
    NSDataAsset *dataAsset = [[NSDataAsset alloc] initWithName:@"builtin" bundle:resourceBundle];
    NSAssert(dataAsset, @"builtin dataset 无法在 xcassets 中搜索到");
    NSString *jsString = [[NSString alloc] initWithData:dataAsset.data encoding:NSUTF8StringEncoding];
#if __has_include(<Hummer/HMJSExecutor.h>)
    _context = HMGetEngineType() == HMEngineTypeNAPI ? [[HMJSExecutor alloc] init] : [[HMJSCExecutor alloc] init];
#else
    _context = [[HMJSCExecutor alloc] init];
#endif
    [self setupExecutorCallBack];
    [[HMJSGlobal globalObject] weakReference:self];
    [_context evaluateScript:jsString withSourceURL:[NSURL URLWithString:@"https://www.didi.com/hummer/builtin.js"]];
    
    NSMutableDictionary *classes = [NSMutableDictionary new];
    // 可以使用模型替代字典，转 JSON，做缓存
    [HMExportManager.sharedInstance.jsClasses enumerateKeysAndObjectsUsingBlock:^(NSString *_Nonnull key, HMExportClass *_Nonnull obj, BOOL *_Nonnull stop) {
        NSMutableArray *methodPropertyArray = [NSMutableArray arrayWithCapacity:obj.classMethodPropertyList.count + obj.instanceMethodPropertyList.count];
        [obj.classMethodPropertyList enumerateKeysAndObjectsUsingBlock:^(NSString *_Nonnull key, HMExportBaseClass *_Nonnull obj, BOOL *_Nonnull stop) {
            [methodPropertyArray addObject:@{
                @"nameString": obj.jsFieldName,
                @"isClass": @YES,
                @"isMethod": @([obj isKindOfClass:HMExportMethod.class])
            }];
        }];
        [obj.instanceMethodPropertyList enumerateKeysAndObjectsUsingBlock:^(NSString *_Nonnull key, HMExportBaseClass *_Nonnull obj, BOOL *_Nonnull stop) {
            [methodPropertyArray addObject:@{
                @"nameString": obj.jsFieldName,
                @"isClass": @NO,
                @"isMethod": @([obj isKindOfClass:HMExportMethod.class])
            }];
        }];
        NSDictionary *class = @{
            @"methodPropertyList": methodPropertyArray,
            @"superClassName": obj.superClassReference.jsClass ?: @""
        };
        [classes setObject:class forKey:obj.jsClass];
    }];
    NSData *data = [NSJSONSerialization dataWithJSONObject:classes options:0 error:nil];
    NSString *classesStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    [_context evaluateScript:[NSString stringWithFormat:@"(function(){hummerLoadClass(%@)})()", classesStr] withSourceURL:[NSURL URLWithString:@"https://www.didi.com/hummer/classModelMap.js"]];
    
    return self;
}


- (void)setupExecutorCallBack {
    __weak typeof(self) weakSelf = self;
    [_context addExceptionHandler:^(HMExceptionModel * _Nonnull exception) {
        
        NSDictionary<NSString *, NSObject *> *exceptionInfo = @{
            @"column": exception.column ?: @0,
            @"line": exception.line ?: @0,
            @"message": exception.message ?: @"",
            @"name": exception.name ?: @"",
            @"stack": exception.stack ?: @""
        };
        HMLogError(@"%@", exceptionInfo);
        if (weakSelf.nameSpace) {
            // errorName -> message
            // errorcode -> type
            // errorMsg -> stack / type + message + stack
            [HMConfigEntryManager.manager.configMap[weakSelf.nameSpace].trackEventPlugin trackJavaScriptExceptionWithExceptionModel:exception pageUrl:weakSelf.hummerUrl ?: @""];
        }
        typeof(weakSelf) strongSelf = weakSelf;
        [HMReporterInterceptor handleJSException:exceptionInfo namespace:strongSelf.nameSpace];
        [HMReporterInterceptor handleJSException:exceptionInfo context:strongSelf namespace:strongSelf.nameSpace];
        if (strongSelf.exceptionHandler) {
            strongSelf.exceptionHandler(exception);
        }
    } key:self];
    
    
    [_context addConsoleHandler:^(NSString * _Nullable logString, HMLogLevel logLevel) {
        
        typeof(weakSelf) strongSelf = weakSelf;
        [HMLoggerInterceptor handleJSLog:logString level:logLevel namespace:strongSelf.nameSpace];
        if (strongSelf.consoleHandler) {
            strongSelf.consoleHandler(logString, logLevel);
        }
#ifdef HMDEBUG
        [strongSelf handleConsoleToWS:logString level:logLevel];
#endif

    } key:self];
    
    
}
#ifdef HMDEBUG
- (void)handleConsoleToWS:(NSString *)logString level:(HMLogLevel)logLevel {
    // 避免 "(null)" 情况
    NSString *jsonStr = @"";
    @try {
        jsonStr = _HMJSONStringWithObject(@{@"type":@"log",
                                            @"data":@{@"level":@(convertNativeLogLevel(logLevel)),
                                                      @"message":logString.length > 0 ? logString : @""}});
    } @catch (NSException *exception) {
        HMLogError(@"native webSocket json 失败");
    } @finally {
        if (@available(iOS 13.0, *)) {
            if (self.webSocketTask) {
                NSURLSessionWebSocketMessage *webSocketMessage = [[NSURLSessionWebSocketMessage alloc] initWithString:jsonStr];
                // 忽略错误
                __weak typeof(self) weakSelf = self;
                [self.webSocketTask sendMessage:webSocketMessage completionHandler:^(NSError * _Nullable error) {
                    typeof(weakSelf) strongSelf = weakSelf;
                    if (error) {
                        [strongSelf handleWebSocket];
                    }
                }];
            }
        }
    }
}
#endif

#ifdef HMDEBUG
- (void)handleWebSocket {
    if (@available(iOS 13, *)) {
        if (self.webSocketTask.state == NSURLSessionTaskStateCanceling || self.webSocketTask.state == NSURLSessionTaskStateCompleted) {
            self.webSocketTask = nil;
        }
    }
}
#endif

- (HMBaseValue *)evaluateScript:(NSString *)javaScriptString fileName:(NSString *)fileName {
    return [self evaluateScript:javaScriptString fileName:fileName hummerUrl:fileName];
}

- (nullable HMBaseValue *)evaluateScript:(nullable NSString *)javaScriptString fileName:(nullable NSString *)fileName hummerUrl:(nullable NSString *)hummerUrl {
    struct timespec beforeTimespec;
    HMClockGetTime(&beforeTimespec);
    
    if (!self.hummerUrl && hummerUrl.length > 0) {
        self.hummerUrl = hummerUrl;
    }
    
    // context 和 WebSocket 对应
    if (!self.url && fileName.length > 0) {
        self.url = [NSURL URLWithString:fileName];
#if __has_include(<Hummer/HMJSExecutor.h>)
        if ([self.context isKindOfClass:HMJSExecutor.class]) {
            [((HMJSExecutor *)self.context) enableDebuggerWithTitle:fileName];
        }
#endif
    }
#ifdef HMDEBUG
    if (@available(iOS 13, *)) {
        if (!self.webSocketTask && fileName.length > 0) {
            NSURLComponents *urlComponents = [NSURLComponents componentsWithString:fileName];
            if ([urlComponents.scheme isEqualToString:@"http"]) {
                urlComponents.scheme = @"ws";
                urlComponents.user = nil;
                urlComponents.password = nil;
                urlComponents.path = @"/proxy/native";
                urlComponents.query = nil;
                urlComponents.fragment = nil;
                if (urlComponents.URL) {
                    self.webSocketTask = [NSURLSession.sharedSession webSocketTaskWithURL:urlComponents.URL];
                    // 启动
                    [self.webSocketTask resume];
                    __weak typeof(self) weakSelf = self;
                    // 判断是否连通
                    [self.webSocketTask sendPingWithPongReceiveHandler:^(NSError * _Nullable error) {
                        typeof(weakSelf) strongSelf = weakSelf;
                        if (error) {
                            [strongSelf handleWebSocket];
                        }
                    }];
                }
            }
        }
    }
#endif
    
    NSURL *url = nil;
    if (fileName.length > 0) {
        url = [NSURL URLWithString:fileName];
    }
    
    NSData *data = [javaScriptString dataUsingEncoding:NSUTF8StringEncoding];
    if (data && self.nameSpace) {
        // 不包括 \0
        // 单位 KB
        [HMConfigEntryManager.manager.configMap[self.nameSpace].trackEventPlugin trackJavaScriptBundleWithSize:@(data.length / 1024) pageUrl:self.hummerUrl ?: @""];
    }
    
    HMBaseValue *returnValue = [self.context evaluateScript:javaScriptString withSourceURL:url];
    
    struct timespec afterTimespec;
    HMClockGetTime(&afterTimespec);
    struct timespec resultTimespec;
    HMDiffTime(&beforeTimespec, &afterTimespec, &resultTimespec);
    if (self.nameSpace) {
        [HMConfigEntryManager.manager.configMap[self.nameSpace].trackEventPlugin trackEvaluationWithDuration:@(resultTimespec.tv_sec * 1000 + resultTimespec.tv_nsec / 1000000)  pageUrl:self.hummerUrl ?: @""];
    }
    
    return returnValue;
}

@end
