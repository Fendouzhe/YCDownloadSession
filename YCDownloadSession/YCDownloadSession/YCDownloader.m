//
//  YCDownloader.m
//  YCDownloadSession
//
//  Created by wz on 2018/8/27.
//  Copyright © 2018 onezen.cc. All rights reserved.
//

#import "YCDownloader.h"
#import "YCDownloadUtils.h"
#import "YCDownloadTask.h"

typedef void(^BGRecreateSessionBlock)(void);
static NSString * const kIsAllowCellar = @"kIsAllowCellar";

@interface YCDownloadTask(Downloader)

@end

@interface YCDownloader()<NSURLSessionDelegate>
{
    BGRecreateSessionBlock _bgRCSBlock;
    dispatch_source_t _timerSource;
}
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, assign) BOOL isNeedCreateSession;
@property (nonatomic, strong) NSMutableDictionary *memCache;
/**后台下载回调的handlers，所有的下载任务全部结束后调用*/
@property (nonatomic, copy) BGCompletedHandler completedHandler;
@end

@implementation YCDownloader

#pragma mark - init

+ (instancetype)downloader {
    static dispatch_once_t onceToken;
    static YCDownloader *_downloader;
    dispatch_once(&onceToken, ^{
        _downloader = [[self alloc] initWithPrivate];
    });
    return _downloader;
}

- (instancetype)initWithPrivate {
    if (self = [super init]) {
        NSLog(@"[YCDownloader init]");
        _session = [self backgroundUrlSession];
        _memCache = [NSMutableDictionary dictionary];
        [self recoveryExceptionTasks];
        [self addNotification];
    }
    return self;
}


- (instancetype)init {
    NSAssert(false, @"use +[YCDownloader downloader] instead!");
    return nil;
}

+ (NSString *)downloadVersion {
    return @"2.0.0";
}

- (NSString *)backgroundSessionIdentifier {
    NSString *bundleId = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleIdentifier"];
    NSString *identifier = [NSString stringWithFormat:@"%@.BackgroundSession", bundleId];
    return identifier;
}

- (NSURLSession *)backgroundUrlSession {
    NSURLSession *session = nil;
    NSString *identifier = [self backgroundSessionIdentifier];
    NSURLSessionConfiguration* sessionConfig = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:identifier];
    sessionConfig.allowsCellularAccess = [[NSUserDefaults standardUserDefaults] boolForKey:kIsAllowCellar];
    session = [NSURLSession sessionWithConfiguration:sessionConfig delegate:self delegateQueue:[NSOperationQueue mainQueue]];
    return session;
}

- (NSInteger)sessionTaskIdWithDownloadTask:(NSURLSessionDownloadTask *)downloadTask {
    NSMutableDictionary *dictM = [self.session valueForKey:@"tasks"];
    __block NSInteger stid;
    [dictM enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull task, BOOL * _Nonnull stop) {
        if (task == downloadTask) {
            stid = [key integerValue];
            *stop = true;
        }
    }];
    NSAssert(stid, @"sessionTaskIdWithDownloadTask stid not nil!");
    return stid;
}

- (void)recoveryExceptionTasks {
    NSMutableDictionary *dictM = [self.session valueForKey:@"tasks"];
    [dictM enumerateKeysAndObjectsUsingBlock:^(NSNumber *_Nonnull key, NSURLSessionDownloadTask *obj, BOOL * _Nonnull stop) {
        YCDownloadTask *task = [YCDownloadDB taskWithStid:key.integerValue];
        NSAssert(task, @"recoveryExceptionTasks no nil!");
        [self memCacheDownloadTask:obj task:task];
        if (!task) [obj cancel];
    }];
}
- (void)addNotification {
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillResignActive) name:UIApplicationWillResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillTerminate) name:UIApplicationWillTerminateNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillBecomeActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    
}

#pragma mark - event

- (void)appWillBecomeActive {
    
}

- (void)appWillResignActive {
    
}

- (void)appWillTerminate {
    
}

#pragma mark - download handler
- (NSURLRequest *)requestWithUrlStr:(NSString *)urlStr {
    NSURL *url = [NSURL URLWithString:urlStr];
    return [NSMutableURLRequest requestWithURL:url];;
}

- (YCDownloadTask *)downloadWithUrl:(NSString *)url progress:(YCProgressHanlder)progress completion:(YCCompletionHanlder)completion {
    NSURLRequest *request = [self requestWithUrlStr:url];
    return [self downloadWithRequest:request progress:progress completion:completion];
}

- (YCDownloadTask *)downloadWithRequest:(NSURLRequest *)request progress:(YCProgressHanlder)progress completion:(YCCompletionHanlder)completion{
    return [self downloadWithRequest:request progress:progress completion:completion priority:0];
}

- (YCDownloadTask *)downloadWithRequest:(NSURLRequest *)request progress:(YCProgressHanlder)progress completion:(YCCompletionHanlder)completion priority:(float)priority{
    YCDownloadTask *task = [YCDownloadTask taskWithRequest:request progress:progress completion:completion];
    NSURLSessionDownloadTask *downloadTask = [self.session downloadTaskWithRequest:request];
    NSAssert(downloadTask, @"downloadtask can not nil!");
    [self memCacheDownloadTask:downloadTask task:task];
    [task.downloadTask resume];
    [self saveDownloadTask:task];
    return task;
}

- (YCDownloadTask *)resumeDownloadTaskWithTid:(NSString *)tid progress:(YCProgressHanlder)progress completion:(YCCompletionHanlder)completion {
    YCDownloadTask *task = [YCDownloadDB taskWithTid:tid];
    task.completionHanlder = completion;
    task.progressHandler = progress;
    [self resumeDownloadTask:task];
    return task;
}

- (BOOL)canResumeTaskWithTid:(NSString *)tid {
    YCDownloadTask *task = [YCDownloadDB taskWithTid:tid];
    return task && (task.downloadTask.state == NSURLSessionTaskStateRunning || task.resumeData != nil);
}

- (BOOL)resumeDownloadTask:(YCDownloadTask *)task {
    if (!task.resumeData) return false;
    if (task.downloadTask && self.memCache[task.downloadTask]) {
        return true;
    }else if (task.downloadTask){
        NSAssert(false, @"exception condition!");
    }
    NSURLSessionDownloadTask *downloadTask = nil;
    @try {
        downloadTask = [YCResumeData downloadTaskWithCorrectResumeData:task.resumeData urlSession:self.session];
    } @catch (NSException *exception) {
        NSError *error = [NSError errorWithDomain:exception.description code:10002 userInfo:exception.userInfo];
        task.completionHanlder(nil, error);
        return false;
    }
    NSAssert(downloadTask, @"resumeDownloadTask can not nil!");
    [self memCacheDownloadTask:downloadTask task:task];
    [downloadTask resume];
    task.resumeData = nil;
}

- (void)pauseDownloadTask:(YCDownloadTask *)task{
    [task.downloadTask cancelByProducingResumeData:^(NSData * _Nullable resumeData) { }];
}

- (void)cancelDownloadTask:(YCDownloadTask *)task{
    [task.downloadTask cancel];
}

#pragma mark - recreate session

- (void)prepareRecreateSession {
    [[YCDownloadDB fetchAllDownloadTasks] enumerateObjectsUsingBlock:^(YCDownloadTask * _Nonnull task, NSUInteger idx, BOOL * _Nonnull stop) {
        if (task.downloadTask.state == NSURLSessionTaskStateRunning) {
            task.needToRestart = true;
            task.noNeedToStartNext = true;
            [self pauseDownloadTask:task];
        }
    }];
    [_session invalidateAndCancel];
    self.isNeedCreateSession = true;
}
- (void)recreateSession {
    
    _session = [self backgroundUrlSession];
    //恢复正在下载的task状态
    [[YCDownloadDB fetchAllDownloadTasks] enumerateObjectsUsingBlock:^(YCDownloadTask * _Nonnull task, NSUInteger idx, BOOL * _Nonnull stop) {
        task.downloadTask = nil;
        if (task.needToRestart) {
            task.needToRestart = false;
            [self resumeDownloadTask:task];
        }
    }];
    NSLog(@"recreate Session success");
}

#pragma mark - setter & getter

- (void)setAllowsCellularAccess:(BOOL)allowsCellularAccess {
    if ([self allowsCellularAccess] != allowsCellularAccess) {
        [[NSUserDefaults standardUserDefaults] setBool:allowsCellularAccess forKey:kIsAllowCellar];
        [self prepareRecreateSession];
    }
}

- (BOOL)allowsCellularAccess {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kIsAllowCellar];
}


#pragma mark - cache

- (void)memCacheDownloadTask:(NSURLSessionDownloadTask *)downloadTask  task:(YCDownloadTask *)task{
    task.downloadTask = downloadTask;
    task.stid = [self sessionTaskIdWithDownloadTask:downloadTask];
    [self.memCache setObject:task forKey:downloadTask];
    [self saveDownloadTask:task];
}

- (void)removeMembCacheTask:(NSURLSessionDownloadTask *)downloadTask task:(YCDownloadTask *)task {
    task.stid = -1;
    task.downloadTask = nil;
    [self.memCache removeObjectForKey:downloadTask];
    [self saveDownloadTask: task];
}


- (void)removeDownloadTask:(YCDownloadTask *)task {
    [YCDownloadDB removeTask:task];
    
}

- (void)saveDownloadTask:(YCDownloadTask *)task {
    [YCDownloadDB saveTask:task];
}

#pragma mark - hanlder

- (void)startTimer {
    [self endTimer];
    dispatch_source_t timerSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    _timerSource = timerSource;
    double interval = 1 * NSEC_PER_SEC;
    dispatch_source_set_timer(timerSource, dispatch_time(DISPATCH_TIME_NOW, interval), interval, 0);
    __weak typeof(self) weakself = self;
    dispatch_source_set_event_handler(timerSource, ^{
        [weakself callTimer];
    });
    dispatch_resume(_timerSource);
}

- (void)endTimer {
    if(_timerSource) dispatch_source_cancel(_timerSource);
    _timerSource = nil;
}

- (void)callTimer {
    NSLog(@"background time remain: %f", [UIApplication sharedApplication].backgroundTimeRemaining);
    //TODO: optimeze the logic for background session
    if ([UIApplication sharedApplication].backgroundTimeRemaining < 15 && !_bgRCSBlock) {
        NSLog(@"background time will up, need to call completed hander!");
        __weak typeof(self) weakSelf = self;
        _bgRCSBlock = ^{
            [weakSelf endTimer];
            [weakSelf callBgCompletedHandler];
        };
        [self prepareRecreateSession];
    }
}

- (void)callBgCompletedHandler {
    if (self.completedHandler) {
        self.completedHandler();
        self.completedHandler = nil;
    }
}


- (void)startNextDownloadTask {
    
}

-(void)addCompletionHandler:(BGCompletedHandler)handler identifier:(NSString *)identifier{
    if ([[self backgroundSessionIdentifier] isEqualToString:identifier]) {
        self.completedHandler = handler;
        //fix a crash in backgroud. for:  reason: backgroundDownload owner pid:252 preventSuspend  preventThrottleDownUI  preventIdleSleep  preventSuspendOnSleep
        [self startTimer];
    }
}

#pragma mark - NSURLSession delegate


- (void)URLSession:(NSURLSession *)session didBecomeInvalidWithError:(nullable NSError *)error {
    
    if (self.isNeedCreateSession) {
        self.isNeedCreateSession = false;
        [self recreateSession];
        if (_bgRCSBlock) {
            _bgRCSBlock();
            _bgRCSBlock = nil;
        }
    }
}

- (YCDownloadTask *)taskWithSessionTask:(NSURLSessionDownloadTask *)downloadTask {
    NSAssert(downloadTask, @"taskWithSessionTask downloadTask can not nil!");
    YCDownloadTask *task = [self.memCache objectForKey:downloadTask];
    return task;
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location {
    
    NSString *localPath = [location path];
    YCDownloadTask *task = [self taskWithSessionTask:downloadTask];
    NSAssert(task, @"YCDownloadTask can not nil!");
    NSUInteger fileSize = [YCDownloadUtils fileSizeWithPath:localPath];
    if (fileSize>0 && fileSize != task.fileSize) {
        NSString *errStr = [NSString stringWithFormat:@"[YCDownloader didFinishDownloadingToURL] fileSize Error, task fileSize: %zd tmp fileSize: %zd", task.fileSize, fileSize];
        NSLog(@"%@",errStr);
        NSError *error = [NSError errorWithDomain:errStr code:10001 userInfo:nil];
        if(task.completionHanlder) task.completionHanlder(nil, error);
    }else{
        if(task.completionHanlder) task.completionHanlder(localPath, nil);
    }
    [self removeDownloadTask:task];
    
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    YCDownloadTask *task = [self taskWithSessionTask:downloadTask];
    if (!task) {
        [downloadTask cancel];
        NSAssert(false,@"didWriteData task nil!");
    }
    task.downloadedSize = (NSInteger)totalBytesWritten;
    if(task.fileSize==0) [task updateTask];
    task.progress.totalUnitCount = totalBytesExpectedToWrite;
    task.progress.completedUnitCount = totalBytesWritten;
    if(task.progressHandler) task.progressHandler(task.progress, task);
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionDownloadTask *)downloadTask didCompleteWithError:(NSError *)error {
    YCDownloadTask *task = [self taskWithSessionTask:downloadTask];
    if (error) {
        // check whether resume data are available
        NSData *resumeData = [error.userInfo objectForKey:NSURLSessionDownloadTaskResumeData];
        if (resumeData) {
            //can resume
            if (YC_DEVICE_VERSION >= 11.0f && YC_DEVICE_VERSION < 11.2f) {
                //修正iOS11 多次暂停继续 文件大小不对的问题
                resumeData = [YCResumeData cleanResumeData:resumeData];
            }
            //通过之前保存的resumeData，获取断点的NSURLSessionTask，调用resume恢复下载
            task.resumeData = resumeData;
            id resumeDataObj = [NSPropertyListSerialization propertyListWithData:resumeData options:0 format:0 error:nil];
            if ([resumeDataObj isKindOfClass:[NSDictionary class]]) {
                NSDictionary *resumeDict = resumeDataObj;
                task.tmpName = [resumeDict valueForKey:@"NSURLSessionResumeInfoTempFileName"];
            }
            task.resumeData = resumeData;
            task.downloadTask = nil;
            [self saveDownloadTask:task];
        }else{
            //cannot resume
            NSLog(@"[didCompleteWithError] : %@",error);
            task.completionHanlder(nil, error);
            [self removeDownloadTask:task];
            [self removeMembCacheTask:task.downloadTask task:task];
        }
        [self removeMembCacheTask:downloadTask task:task];
    }
    //需要下载下一个任务则下载下一个，否则还原noNeedToStartNext标识
    !task.noNeedToStartNext ? [self startNextDownloadTask] :  (task.noNeedToStartNext = false);
    
}

@end
