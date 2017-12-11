//
//  YCDownloadSession.m
//  YCDownloadSession
//
//  Created by wz on 17/3/14.
//  Copyright © 2017年 onezen.cc. All rights reserved.
//  Github: https://github.com/onezens/YCDownloadSession
//

#import "YCDownloadSession.h"
#import "NSURLSession+CorrectedResumeData.h"

#define IS_IOS10ORLATER ([[[UIDevice currentDevice] systemVersion] floatValue] >= 10)

#ifdef DEBUG
#define YCLog(...) NSLog(__VA_ARGS__)
#else
#define YCLog(...)
#endif

static NSString * const kIsAllowCellar = @"kIsAllowCellar";
@interface YCDownloadSession ()<NSURLSessionDownloadDelegate>

/**正在下载的task*/
@property (nonatomic, strong) NSMutableDictionary *downloadTasks;
/**下载完成的task*/
@property (nonatomic, strong) NSMutableDictionary *downloadedTasks;
/**后台下载回调的handlers，所有的下载任务全部结束后调用*/
@property (nonatomic, copy) BGCompletedHandler completedHandler;
@property (nonatomic, strong, readonly) NSURLSession *session;
/**重新创建sessio标记位*/
@property (nonatomic, assign) BOOL isNeedCreateSession;
/**启动下一个下载任务的标记位*/
@property (nonatomic, assign) BOOL isStartNextTask;

@end

@implementation YCDownloadSession


static YCDownloadSession *_instance;

+ (instancetype)downloadSession {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _instance = [[self alloc] init];
    });
    return _instance;
}


- (instancetype)init {
    if (self = [super init]) {
        //初始化
        _session = [self getDownloadURLSession];
        _maxTaskCount = 1;
        self.downloadTasks = [NSKeyedUnarchiver unarchiveObjectWithFile:[self getArchiverPathIsDownloaded:false]];
        self.downloadedTasks = [NSKeyedUnarchiver unarchiveObjectWithFile:[self getArchiverPathIsDownloaded:true]];
        
        //获取保存在本地的数据是否为空，为空则初始化
        if(!self.downloadedTasks) self.downloadedTasks = [NSMutableDictionary dictionary];
        if(!self.downloadTasks) self.downloadTasks = [NSMutableDictionary dictionary];
        
        //获取背景session正在运行的(app重启，或者闪退会有任务)
        NSMutableDictionary *dictM = [self.session valueForKey:@"tasks"];
        [dictM enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
            YCDownloadTask *task = [self getDownloadTaskWithUrl:[YCDownloadTask getURLFromTask:obj] isDownloadingList:true];
            if(!task){
                [obj cancel];
            }else{
                task.downloadTask = obj;
            }
        }];
        
        //app重启，或者闪退的任务全部暂停
        [self pauseAllDownloadTask];
        
    }
    return self;
}

- (NSURLSession *)getDownloadURLSession {
    
    NSURLSession *session = nil;
    NSString *identifier = [self backgroundSessionIdentifier];
    NSURLSessionConfiguration* sessionConfig = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:identifier];
    sessionConfig.allowsCellularAccess = [[NSUserDefaults standardUserDefaults] boolForKey:kIsAllowCellar];
    session = [NSURLSession sessionWithConfiguration:sessionConfig
                                            delegate:self
                                       delegateQueue:[NSOperationQueue mainQueue]];
    return session;
}

- (NSString *)backgroundSessionIdentifier {
    NSString *bundleId = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleIdentifier"];
    NSString *identifier = [NSString stringWithFormat:@"%@.BackgroundSession", bundleId];
    return identifier;
}


- (void)recreateSession {
    
    _session = [self getDownloadURLSession];
    YCLog(@"recreate Session success");
    //恢复正在下载的task状态
    [self.downloadTasks enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        YCDownloadTask *task = obj;
        task.downloadTask = nil;
        if (task.needToRestart) {
            task.needToRestart = false;
            [self resumeDownloadTask:task];
        }
    }];
}


-(void)setMaxTaskCount:(NSInteger)maxTaskCount {
    if (maxTaskCount>3) {
        _maxTaskCount = 3;
    }else if(maxTaskCount <= 0){
        _maxTaskCount = 1;
    }else{
        _maxTaskCount = maxTaskCount;
    }
}

- (NSInteger)currentTaskCount {
    NSMutableDictionary *dictM = [self.session valueForKey:@"tasks"];
    __block NSInteger count = 0;
    [dictM enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        NSURLSessionTask *task = obj;
        if (task.state == NSURLSessionTaskStateRunning) {
            count++;
        }
    }];
    return count;
}

#pragma mark - public

- (YCDownloadTask *)startDownloadWithUrl:(NSString *)downloadURLString fileId:(NSString *)fileId delegate:(id<YCDownloadTaskDelegate>)delegate{
    if (downloadURLString.length == 0)  return nil;
    
    //判断是否是下载完成的任务
    YCDownloadTask *task = [self getDownloadTaskWithUrl:downloadURLString isDownloadingList:false];
    if (task) {
        task.delegate = delegate;
        [self downloadStatusChanged:YCDownloadStatusFinished task:task];
        return task;
    }
    //读取正在下载的任务
    task = [self getDownloadTaskWithUrl:downloadURLString isDownloadingList:true];
    
    if (!task) {
        //判断任务的个数，如果达到最大值则返回，回调等待
        if([self currentTaskCount] >= self.maxTaskCount){
            //创建任务，让其处于等待状态
            task = [self createDownloadTaskItemWithUrl:downloadURLString fileId:fileId delegate:delegate];
            [self downloadStatusChanged:YCDownloadStatusWaiting task:task];
            return task;
        }else {
            //开始下载
            return [self startNewTaskWithUrl:downloadURLString fileId:fileId delegate:delegate];
        }
        return nil;
    }else{
        task.delegate = delegate;
        if ([self detectDownloadTaskIsFinished:task]) {
            [self downloadStatusChanged:YCDownloadStatusFinished task:task];
            return task;
        }
        
        if (task.downloadTask && task.downloadTask.state == NSURLSessionTaskStateRunning && task.resumeData.length == 0) {
            [task.downloadTask resume];
            [self downloadStatusChanged:YCDownloadStatusDownloading task:task];
            return task;
        }
        [self resumeDownloadTask:task];
        return task;
    }
}


- (void)pauseDownloadWithTask:(YCDownloadTask *)task {
    [self pauseDownloadTask:task];
}

- (void)resumeDownloadWithTask:(YCDownloadTask *)task{
    [self resumeDownloadTask:task];
}

- (void)stopDownloadWithTask:(YCDownloadTask *)task{
    [self stopDownloadWithTaskId:task.taskId];
}

- (void)pauseDownloadWithTaskId:(NSString *)taskId {
    self.isStartNextTask = true;
    YCDownloadTask *task = [self.downloadTasks valueForKey:taskId];
    [self pauseDownloadTask:task];
}

- (void)resumeDownloadWithTaskId:(NSString *)taskId{
    YCDownloadTask *task = [self.downloadTasks valueForKey:taskId];
    [self resumeDownloadTask:task];
}

- (void)stopDownloadWithTaskId:(NSString *)taskId {
    
    YCDownloadTask *task = [self.downloadedTasks valueForKey:taskId];
    if (task && [[NSFileManager defaultManager] fileExistsAtPath:task.savePath]) {
        [[NSFileManager defaultManager] removeItemAtPath:task.savePath error:nil];
    }
    task = [self.downloadTasks valueForKey:taskId];
    [task.downloadTask cancel];
    [self.downloadedTasks removeObjectForKey:taskId];
    [self.downloadTasks removeObjectForKey:taskId];
    [self saveDownloadStatus];
    [self startNextDownloadTask];
}


- (void)pauseAllDownloadTask{
    [self.downloadTasks enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, YCDownloadTask * _Nonnull obj, BOOL * _Nonnull stop) {
        if(obj.downloadStatus == YCDownloadStatusDownloading){
            [self pauseDownloadTask:obj];
        }else if (obj.downloadStatus == YCDownloadStatusWaiting){
            [self downloadStatusChanged:YCDownloadStatusPaused task:obj];
        }
    }];
}

- (void)resumeAllDownloadTask {
    
}
//- (void)resumeDownloadWithUrl:(NSString *)downloadURLString delegate:(id<YCDownloadTaskDelegate>)delegate saveName:(NSString *)saveName{
//    //判断是否是下载完成的任务
//    YCDownloadTask *task = [self getDownloadTaskWithUrl:downloadURLString isDownloadingList:false];
//    if (task) {
//        task.delegate = delegate;
//        [self downloadStatusChanged:YCDownloadStatusFinished task:task];
//        return;
//    }
//    task = [self getDownloadTaskWithUrl:downloadURLString isDownloadingList:true];
//
//    //如果下载列表和下载完成列表都不存在，则重新创建
//    if (!task) {
//        [self startDownloadWithUrl:downloadURLString fileId:nil delegate:delegate];
//        return;
//    }
//
//    if(delegate) task.delegate = delegate;
//    [self resumeDownloadTask: task];
//}


- (void)allowsCellularAccess:(BOOL)isAllow {
    
    [[NSUserDefaults standardUserDefaults] setBool:isAllow forKey:kIsAllowCellar];
    [self.downloadTasks enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        YCDownloadTask *task = obj;
        if (task.downloadTask.state == NSURLSessionTaskStateRunning) {
            task.needToRestart = true;
            [self pauseDownloadTask:task];
        }
    }];

    [_session invalidateAndCancel];
    self.isNeedCreateSession = true;
}

- (BOOL)isAllowsCellularAccess {
    
    return [[NSUserDefaults standardUserDefaults] boolForKey:kIsAllowCellar];
}

-(void)addCompletionHandler:(BGCompletedHandler)handler identifier:(NSString *)identifier{
    if ([[self backgroundSessionIdentifier] isEqualToString:identifier]) {
        self.completedHandler = handler;
    }
}

#pragma mark - private

- (YCDownloadTask *)startNewTaskWithUrl:(NSString *)downloadURLString fileId:(NSString *)fileId delegate:(id<YCDownloadTaskDelegate>)delegate{
    
    NSURL *downloadURL = [NSURL URLWithString:downloadURLString];
    NSURLRequest *request = [NSURLRequest requestWithURL:downloadURL];
    NSURLSessionDownloadTask *downloadTask = [self.session downloadTaskWithRequest:request];
    YCDownloadTask *task = [self createDownloadTaskItemWithUrl:downloadURLString fileId:fileId delegate:delegate];
    task.downloadTask = downloadTask;
    [downloadTask resume];
    [self downloadStatusChanged:YCDownloadStatusDownloading task:task];
    return task;
}

- (YCDownloadTask *)createDownloadTaskItemWithUrl:(NSString *)downloadURLString fileId:(NSString *)fileId delegate:(id<YCDownloadTaskDelegate>)delegate{
    
    YCDownloadTask *task = [YCDownloadTask taskWithUrl:downloadURLString fileId:fileId delegate:delegate];
    task.delegate = delegate;
    [self.downloadTasks setObject:task forKey:task.taskId];
    [self downloadStatusChanged:YCDownloadStatusWaiting task:task];
    return task;
}

- (void)pauseDownloadTask:(YCDownloadTask *)task{
    [task.downloadTask cancelByProducingResumeData:^(NSData * resumeData) {
        YCLog(@"pause ----->   %zd  ----->   %@", resumeData.length, task.downloadURL);
        if(resumeData.length>0) task.resumeData = resumeData;
        task.downloadTask = nil;
        [self saveDownloadStatus];
        [self downloadStatusChanged:YCDownloadStatusPaused task:task];
        if (self.isStartNextTask) {
            [self startNextDownloadTask];
        }
    }];
}


- (void)resumeDownloadTask:(YCDownloadTask *)task {
    
    if(!task) return;
    if (([self currentTaskCount] >= self.maxTaskCount) && task.downloadStatus != YCDownloadStatusDownloading) {
        [self downloadStatusChanged:YCDownloadStatusWaiting task:task];
        return;
    }
    if ([self detectDownloadTaskIsFinished:task]) {
        [self downloadStatusChanged:YCDownloadStatusFinished task:task];
        return;
    }
    
    NSData *data = task.resumeData;
    if (data.length > 0) {
        if(task.downloadTask && task.downloadTask.state == NSURLSessionTaskStateRunning){
            [self downloadStatusChanged:YCDownloadStatusDownloading task:task];
            return;
        }
        NSURLSessionDownloadTask *downloadTask = nil;
        if (IS_IOS10ORLATER) {
            @try { //非ios10 升级到ios10会引起崩溃
                downloadTask = [self.session downloadTaskWithCorrectResumeData:data];
            } @catch (NSException *exception) {
                downloadTask = [self.session downloadTaskWithResumeData:data];
            }
        } else {
            downloadTask = [self.session downloadTaskWithResumeData:data];
        }
        task.downloadTask = downloadTask;
        [downloadTask resume];
        task.resumeData = nil;
        [self downloadStatusChanged:YCDownloadStatusDownloading task:task];
        
    }else{
        //没有下载任务，那么重新创建下载任务；  部分下载暂停异常 NSURLSessionTaskStateCompleted ，但并没有完成，所以重新下载
        if (!task.downloadTask || task.downloadTask.state == NSURLSessionTaskStateCompleted) {
            [self.downloadTasks removeObjectForKey:task.taskId];
            [self startNewTaskWithUrl:task.downloadURL fileId:task.fileId delegate:task.delegate];
        }else{
            [task.downloadTask resume];
            [self downloadStatusChanged:YCDownloadStatusDownloading task:task];
        }
    }
}


- (void)startNextDownloadTask {
    self.isStartNextTask = false;
    if ([self currentTaskCount] < self.maxTaskCount) {
        [self.downloadTasks enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
            YCDownloadTask *task = obj;
            if ((!task.downloadTask || task.downloadTask.state != NSURLSessionTaskStateRunning) && task.downloadStatus == YCDownloadStatusWaiting) {
                [self resumeDownloadTask:task];
            }
        }];
    }
}


- (void)downloadStatusChanged:(YCDownloadStatus)status task:(YCDownloadTask *)task{
    
    task.downloadStatus = status;
    [self saveDownloadStatus];
    switch (status) {
        case YCDownloadStatusWaiting:
            break;
        case YCDownloadStatusDownloading:
            break;
        case YCDownloadStatusPaused:
            break;
        case YCDownloadStatusFailed:
            break;
        case YCDownloadStatusFinished:
            [self startNextDownloadTask];
            break;
        default:
            break;
    }
    
    if ([task.delegate respondsToSelector:@selector(downloadStatusChanged:downloadTask:)]) {
        [task.delegate downloadStatusChanged:status downloadTask:task];
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kDownloadStatusChangedNoti object:nil];
    
    //等task delegate方法执行完成后去判断该逻辑
    //URLSessionDidFinishEventsForBackgroundURLSession 方法在后台执行一次，所以在此判断执行completedHandler
    if (status == YCDownloadStatusFinished) {
        
        if ([self allTaskFinised]) {
            [[NSNotificationCenter defaultCenter] postNotificationName:kDownloadAllTaskFinishedNoti object:nil];
            //所有的任务执行结束之后调用completedHanlder
            if (self.completedHandler) {
                YCLog(@"completedHandler");
                self.completedHandler();
                self.completedHandler = nil;
            }
        }

    }
}

- (BOOL)allTaskFinised {
    
    if (self.downloadTasks.count == 0) return true;
    
    __block BOOL isFinished = true;
    [self.downloadTasks enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        YCDownloadTask *task = obj;
        if (task.downloadStatus == YCDownloadStatusWaiting || task.downloadStatus == YCDownloadStatusDownloading) {
            isFinished = false;
            *stop = true;
        }
    }];
    return isFinished;
}


#pragma mark - event

- (void)saveDownloadStatus {
    
    [NSKeyedArchiver archiveRootObject:self.downloadTasks toFile:[self getArchiverPathIsDownloaded:false]];
    [NSKeyedArchiver archiveRootObject:self.downloadedTasks toFile:[self getArchiverPathIsDownloaded:true]];
}

- (NSString *)getArchiverPathIsDownloaded:(BOOL)isDownloaded {
    NSString *saveDir = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, true).firstObject;
    saveDir = [saveDir stringByAppendingPathComponent:@"YCDownload"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:saveDir]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:saveDir withIntermediateDirectories:true attributes:nil error:nil];
    }
    saveDir = isDownloaded ? [saveDir stringByAppendingPathComponent:@"YCDownloaded.data"] : [saveDir stringByAppendingPathComponent:@"YCDownloading.data"];
    
    return saveDir;
}

- (BOOL)detectDownloadTaskIsFinished:(YCDownloadTask *)task {
    
    NSMutableArray *tmpPaths = [NSMutableArray array];
    
    if (task.tempPath.length > 0) [tmpPaths addObject:task.tempPath];
    
    if (task.tmpName.length > 0) {
        [tmpPaths addObject:[NSTemporaryDirectory() stringByAppendingPathComponent:task.tmpName]];
        NSString *downloadPath = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, true).firstObject;
        NSString *bundleId = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleIdentifier"];
        downloadPath = [downloadPath stringByAppendingPathComponent: [NSString stringWithFormat:@"/com.apple.nsurlsessiond/Downloads/%@/", bundleId]];
        downloadPath = [downloadPath stringByAppendingPathComponent:task.tmpName];
        [tmpPaths addObject:downloadPath];
    }
    
    __block BOOL isFinished = false;
    [tmpPaths enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *path = obj;
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            NSDictionary *dic = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
            NSInteger fileSize = dic ? (NSInteger)[dic fileSize] : 0;
            if (fileSize>0 && fileSize == task.fileSize) {
                [[NSFileManager defaultManager] moveItemAtPath:path toPath:task.savePath error:nil];
                isFinished = true;
                task.downloadStatus = YCDownloadStatusFinished;
                *stop = true;
            }
        }
    }];
    
    return isFinished;
}


- (YCDownloadTask *)getDownloadTaskWithUrl:(NSString *)downloadUrl isDownloadingList:(BOOL)isDownloadList{
    
    NSMutableDictionary *tasks = isDownloadList ? self.downloadTasks : self.downloadedTasks;
    __block YCDownloadTask *task = nil;
    [tasks enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        YCDownloadTask *dTask = obj;
        if ([dTask.downloadURL isEqualToString:downloadUrl]) {
            task = dTask;
            *stop = true;
        }
    }];
    return task;
}


#pragma mark -  NSURLSessionDelegate

//将一个后台session作废完成后的回调，用来切换是否允许使用蜂窝煤网络，重新创建session
- (void)URLSession:(NSURLSession *)session didBecomeInvalidWithError:(nullable NSError *)error {
    
    if (self.isNeedCreateSession) {
        self.isNeedCreateSession = false;
        [self recreateSession];
    }
}

//如果appDelegate实现下面的方法，后台下载完成时，会自动唤醒启动app。如果不实现，那么后台下载完成不唤醒，用户手动启动会调用相关回调方法
//-[AppDelegate application:handleEventsForBackgroundURLSession:completionHandler:]
//后台唤醒调用顺序： appdelegate ——> didFinishDownloadingToURL  ——> URLSessionDidFinishEventsForBackgroundURLSession
//手动启动调用顺序: didFinishDownloadingToURL  ——> URLSessionDidFinishEventsForBackgroundURLSession
- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location {
    
    YCLog(@"%s", __func__);

    NSString *locationString = [location path];
    NSError *error;
    
    NSString *downloadUrl = [YCDownloadTask getURLFromTask:downloadTask];
    YCDownloadTask *task = [self getDownloadTaskWithUrl:downloadUrl isDownloadingList:true];
    if(!task){
        YCLog(@"download finished , item nil error!!!! url: %@", downloadUrl);
        return;
    }
    task.tempPath = locationString;
    NSDictionary *dic = [[NSFileManager defaultManager] attributesOfItemAtPath:locationString error:nil];
    NSInteger fileSize = dic ? (NSInteger)[dic fileSize] : 0;
    //校验文件大小
    BOOL isCompltedFile = (fileSize>0) && (fileSize == task.fileSize);
    //文件大小不对，回调失败 ios11 多次暂停继续会出现文件大小不对的情况
    if (!isCompltedFile) {
        [self downloadStatusChanged:YCDownloadStatusFailed task:task];
        return;
    }
    task.downloadedSize = task.fileSize;
    [[NSFileManager defaultManager] moveItemAtPath:locationString toPath:task.savePath error:&error];

    if (task.downloadURL.length != 0) {
        [self.downloadedTasks setObject:task forKey:task.downloadURL];
        [self.downloadTasks removeObjectForKey:task.downloadURL];
    }
    [self downloadStatusChanged:YCDownloadStatusFinished task:task];
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
 didResumeAtOffset:(int64_t)fileOffset
expectedTotalBytes:(int64_t)expectedTotalBytes {
    
    //NSLog(@"fileOffset:%lld expectedTotalBytes:%lld",fileOffset,expectedTotalBytes);
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    
    YCDownloadTask *task = [self getDownloadTaskWithUrl:[YCDownloadTask getURLFromTask:downloadTask] isDownloadingList:true];
    task.downloadedSize = (NSInteger)totalBytesWritten;
    if (task.fileSize == 0)  {
        [task updateTask];
        if ([task.delegate respondsToSelector:@selector(downloadCreated:)]) {
            [task.delegate downloadCreated:task];
        }
        [self saveDownloadStatus];
    }
    
    if([task.delegate respondsToSelector:@selector(downloadProgress:downloadedSize:fileSize:)]){
        [task.delegate downloadProgress:task downloadedSize:task.downloadedSize fileSize:task.fileSize];
    }
    
    NSString *url = downloadTask.response.URL.absoluteString;
    YCLog(@"downloadURL: %@  downloadedSize: %zd totalSize: %zd  progress: %f", url, task.downloadedSize, task.fileSize, (float)task.downloadedSize / task.fileSize);
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {
    
    //YCLog(@"willPerformHTTPRedirection ------> %@",response);
}

//后台下载完成后调用。在执行 URLSession:downloadTask:didFinishDownloadingToURL: 之后调用
- (void)URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session {
    //YCLog(@"%s", __func__);

}


/*
 * 该方法下载成功和失败都会回调，只是失败的是error是有值的，
 * 在下载失败时，error的userinfo属性可以通过NSURLSessionDownloadTaskResumeData
 * 这个key来取到resumeData(和上面的resumeData是一样的)，再通过resumeData恢复下载
 */
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error {
    
    if (error) {
        
        // check if resume data are available
        NSData *resumeData = [error.userInfo objectForKey:NSURLSessionDownloadTaskResumeData];
        YCDownloadTask *yctask = [self getDownloadTaskWithUrl:[YCDownloadTask getURLFromTask:task] isDownloadingList:true];
        YCLog(@"error ----->   %@  ----->   %@   --->%zd",error, yctask.downloadURL, resumeData.length);
        if (resumeData) {
            //通过之前保存的resumeData，获取断点的NSURLSessionTask，调用resume恢复下载
            yctask.resumeData = resumeData;
            id obj = [NSPropertyListSerialization propertyListWithData:resumeData options:0 format:0 error:nil];
            if ([obj isKindOfClass:[NSDictionary class]]) {
                NSDictionary *resumeDict = obj;
                YCLog(@"%@", resumeDict);
                yctask.tmpName = [resumeDict valueForKey:@"NSURLSessionResumeInfoTempFileName"];
            }
           
        }else{
            [self downloadStatusChanged:YCDownloadStatusFailed task:yctask];
            [self startNextDownloadTask];
        }
    }
}



@end
