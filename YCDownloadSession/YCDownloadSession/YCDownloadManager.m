//
//  YCDownloadManager.m
//  YCDownloadSession
//
//  Created by wz on 17/3/24.
//  Copyright © 2017年 onezen.cc. All rights reserved.
//  Contact me: http://www.onezen.cc
//  Github:     https://github.com/onezens/YCDownloadSession
//

#import "YCDownloadManager.h"

#define kCommonUtilsGigabyte (1024 * 1024 * 1024)
#define kCommonUtilsMegabyte (1024 * 1024)
#define kCommonUtilsKilobyte 1024

@interface YCDownloadManager ()

@property (nonatomic, strong) NSMutableDictionary *itemsDictM;
/**本地通知开关，默认关,一般用于测试。可以根据通知名称，自定义*/
@property (nonatomic, assign) BOOL localPushOn;

@end

@implementation YCDownloadManager

static id _instance;

#pragma mark - init

+ (instancetype)manager {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _instance = [[self alloc] init];
    });
    return _instance;
}

- (instancetype)init {
    if (self = [super init]) {
        [self initDownloadData];
        [self addNotification];
    }
    return self;
}

- (void)initDownloadData {
    [self getDownloadItems];
    if(!self.itemsDictM) self.itemsDictM = [NSMutableDictionary dictionary];
}

- (void)saveDownloadItems {
    [NSKeyedArchiver archiveRootObject:self.itemsDictM toFile:[self downloadItemSavePath]];
}

- (void)getDownloadItems {
    NSMutableDictionary *items = [NSKeyedUnarchiver unarchiveObjectWithFile:[self downloadItemSavePath]];;
    self.itemsDictM = items;
}

- (NSString *)downloadItemSavePath {
    NSString *saveDir = [[YCDownloadSession downloadSession] saveRootPath];
    return [saveDir stringByAppendingFormat:@"/video/items.data"];
}

- (void)addNotification {
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(saveDownloadItems) name:kDownloadStatusChangedNoti object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(downloadAllTaskFinished) name:kDownloadAllTaskFinishedNoti object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(downloadTaskFinishedNoti:) name:kDownloadTaskFinishedNoti object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(saveDownloadItems) name:kDownloadNeedSaveDataNoti object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(downloadUserChanged) name:kDownloadUserIdentifyChanged object:nil];
}


#pragma mark - public

+ (void)setMaxTaskCount:(NSInteger)count {
    [YCDownloadMgr setMaxTaskCount: count];
}

+ (void)startDownloadWithItem:(YCDownloadItem *)item {
    [YCDownloadMgr startDownloadWithItem:item priority:NSURLSessionTaskPriorityDefault];
}

+ (void)startDownloadWithItem:(YCDownloadItem *)item priority:(float)priority {
    [YCDownloadMgr startDownloadWithItem:item priority:priority];
}

+ (void)startDownloadWithUrl:(NSString *)downloadURLString fileName:(NSString *)fileName imageUrl:(NSString *)imagUrl{
    [YCDownloadMgr startDownloadWithUrl:downloadURLString fileName:fileName imageUrl:imagUrl];
}

+ (void)startDownloadWithUrl:(NSString *)downloadURLString fileName:(NSString *)fileName imageUrl:(NSString *)imagUrl fileId:(NSString *)fileId{
    [YCDownloadMgr startDownloadWithUrl:downloadURLString fileName:fileName imageUrl:imagUrl fileId:fileId];
}

+ (void)pauseDownloadWithItem:(YCDownloadItem *)item {
    [YCDownloadMgr pauseDownloadWithItem:item];
}

+ (void)resumeDownloadWithItem:(YCDownloadItem *)item {
    [YCDownloadMgr resumeDownloadWithItem:item];
}

+ (void)stopDownloadWithItem:(YCDownloadItem *)item {
    [YCDownloadMgr stopDownloadWithItem:item];
}

/**
 暂停所有的下载
 */
+ (void)pauseAllDownloadTask {
    [YCDownloadMgr pauseAllDownloadTask];
}

+ (void)resumeAllDownloadTask {
    [YCDownloadMgr resumeAllDownloadTask];
}

+ (void)removeAllCache {
    [YCDownloadMgr removeAllCache];
}

+ (NSArray *)downloadList {
    return [YCDownloadMgr downloadList];
}
+ (NSArray *)finishList {
    return [YCDownloadMgr finishList];
}

+ (BOOL)isDownloadWithId:(NSString *)downloadId {
    return [YCDownloadMgr isDownloadWithId:downloadId];
}

+ (YCDownloadStatus)downloasStatusWithId:(NSString *)downloadId {
    return [YCDownloadMgr downloasStatusWithId:downloadId];
}

+ (YCDownloadItem *)downloadItemWithId:(NSString *)downloadId {
    return [YCDownloadMgr itemWithIdentifier:downloadId];
}

+(void)allowsCellularAccess:(BOOL)isAllow {
    [YCDownloadMgr allowsCellularAccess:isAllow];
}

+(void)localPushOn:(BOOL)isOn {
    [YCDownloadMgr localPushOn:isOn];
}


#pragma mark - assgin

- (void)setGetUserIdentify:(GetUserIdentifyBlk)getUserIdentify {
    _getUserIdentify = getUserIdentify;
    [[YCDownloadSession downloadSession] setGetUserIdentify:getUserIdentify];
    [self initDownloadData];
}

- (void)setMaxTaskCount:(NSInteger)count{
    [YCDownloadSession downloadSession].maxTaskCount = count;
}

#pragma mark tools
+(BOOL)isAllowsCellularAccess{
    return [YCDownloadMgr isAllowsCellularAccess];
}


+ (NSUInteger)videoCacheSize {
    NSUInteger size = 0;
    NSArray *downloadList = [self downloadList];
    NSArray *finishList = [self finishList];
    for (YCDownloadTask *task in downloadList) {
        size += task.downloadedSize;
    }
    for (YCDownloadTask *task in finishList) {
        size += task.fileSize;
    }
    return size;
    
}
+ (NSUInteger)fileSystemFreeSize {
    NSUInteger totalFreeSpace = 0;
    NSError *error = nil;
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSDictionary *dictionary = [[NSFileManager defaultManager] attributesOfFileSystemForPath:[paths lastObject] error: &error];
    
    if (dictionary) {
        NSNumber *freeFileSystemSizeInBytes = [dictionary objectForKey:NSFileSystemFreeSize];
        totalFreeSpace = [freeFileSystemSizeInBytes unsignedIntegerValue];
    }
    return totalFreeSpace;
}

+ (void)saveDownloadStatus {
    [[YCDownloadManager manager] saveDownloadItems];
}
+ (NSString *)fileSizeStringFromBytes:(uint64_t)byteSize {
    if (kCommonUtilsGigabyte <= byteSize) {
        return [NSString stringWithFormat:@"%@GB", [self numberStringFromDouble:(double)byteSize / kCommonUtilsGigabyte]];
    }
    if (kCommonUtilsMegabyte <= byteSize) {
        return [NSString stringWithFormat:@"%@MB", [self numberStringFromDouble:(double)byteSize / kCommonUtilsMegabyte]];
    }
    if (kCommonUtilsKilobyte <= byteSize) {
        return [NSString stringWithFormat:@"%@KB", [self numberStringFromDouble:(double)byteSize / kCommonUtilsKilobyte]];
    }
    return [NSString stringWithFormat:@"%zdB", byteSize];
}


+ (NSString *)numberStringFromDouble:(const double)num {
    NSInteger section = round((num - (NSInteger)num) * 100);
    if (section % 10) {
        return [NSString stringWithFormat:@"%.2f", num];
    }
    if (section > 0) {
        return [NSString stringWithFormat:@"%.1f", num];
    }
    return [NSString stringWithFormat:@"%.0f", num];
}

#pragma mark - private

- (void)downloadUserChanged{
    [self initDownloadData];
}


- (void)startDownloadWithItem:(YCDownloadItem *)item priority:(float)priority{
    if(!item) return;
    YCDownloadItem *oldItem = [self itemWithIdentifier:item.taskId];
    if (oldItem.downloadStatus == YCDownloadStatusFinished) return;
    [self.itemsDictM setValue:item forKey:item.taskId];
    YCDownloadTask *task =  [YCDownloadSession.downloadSession startDownloadWithUrl:item.downloadUrl fileId:item.fileId delegate:item priority:priority];
    task.enableSpeed = item.enableSpeed;
}

- (void)startDownloadWithUrl:(NSString *)downloadURLString fileName:(NSString *)fileName imageUrl:(NSString *)imagUrl {
    [self startDownloadWithUrl:downloadURLString fileName:fileName imageUrl:imagUrl fileId:downloadURLString];
}

//下载文件时候的保存名称，如果没有fileid那么必须 savename = nil
- (NSString *)saveNameForItem:(YCDownloadItem *)item {
    
    NSString *saveName = [item.downloadUrl isEqualToString:item.fileId] ? nil : item.fileId;
    return saveName;
}

- (void)startDownloadWithUrl:(NSString *)downloadURLString fileName:(NSString *)fileName imageUrl:(NSString *)imagUrl fileId:(NSString *)fileId{
    
    if (downloadURLString.length == 0 && fileId.length == 0) return;
    NSString *taskId = [YCDownloadTask taskIdForUrl:downloadURLString fileId:fileId];
    YCDownloadItem *item = [self.itemsDictM valueForKey:taskId];
    if (item == nil) {
        item = [[YCDownloadItem alloc] initWithUrl:downloadURLString fileId:fileId];
    }
    item.fileName = fileName;
    item.thumbImageUrl = imagUrl;
    [self startDownloadWithItem:item priority:NSURLSessionTaskPriorityDefault];
}

- (void)resumeDownloadWithItem:(YCDownloadItem *)item{
    YCDownloadTask *task = [YCDownloadSession.downloadSession taskForTaskId:item.taskId];
    task.delegate = item;
    [YCDownloadSession.downloadSession resumeDownloadWithTaskId:item.taskId];
    [self saveDownloadItems];
}


- (void)pauseDownloadWithItem:(YCDownloadItem *)item {
    [YCDownloadSession.downloadSession pauseDownloadWithTaskId:item.taskId];
    [self saveDownloadItems];
}

- (void)stopDownloadWithItem:(YCDownloadItem *)item {
    if (item == nil )  return;
    [YCDownloadSession.downloadSession stopDownloadWithTaskId: item.taskId];
    [self.itemsDictM removeObjectForKey:item.taskId];
    [self saveDownloadItems];
}

- (void)pauseAllDownloadTask {
    [[YCDownloadSession downloadSession] pauseAllDownloadTask];
}

- (void)removeAllCache {
    [self.itemsDictM.copy enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, YCDownloadItem *  _Nonnull obj, BOOL * _Nonnull stop) {
        [self stopDownloadWithItem:obj];
    }];
}

- (void)resumeAllDownloadTask{
    [self.itemsDictM enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        YCDownloadItem *item = obj;
        if (item.downloadStatus == YCDownloadStatusPaused || item.downloadStatus == YCDownloadStatusFailed) {
            [self resumeDownloadWithItem:item];
        }
    }];
}

-(NSArray *)downloadList {
    NSMutableArray *arrM = [NSMutableArray array];
    
    [self.itemsDictM enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        YCDownloadItem *item = obj;
        if(item.downloadStatus != YCDownloadStatusFinished){
            [arrM addObject:item];
        }
    }];
    
    return arrM;
}
- (NSArray *)finishList {
    NSMutableArray *arrM = [NSMutableArray array];
    [self.itemsDictM enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        YCDownloadItem *item = obj;
        if(item.downloadStatus == YCDownloadStatusFinished){
            [arrM addObject:item];
        }
    }];
    return arrM;
}

/**id 可以是downloadUrl，也可以是fileId，首先从fileId开始找，然后downloadUrl*/

- (YCDownloadItem *)itemWithIdentifier:(NSString *)identifier {
    __block YCDownloadItem *item = [self.itemsDictM valueForKey:identifier];
    if (item) return item;
    [self.itemsDictM enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        YCDownloadItem *dItem = obj;
        if([dItem.fileId isEqualToString:identifier]){
            item = dItem;
            *stop = true;
        }
    }];
    
    if(item) return item;
    
    [self.itemsDictM enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        YCDownloadItem *dItem = obj;
        if([dItem.downloadUrl isEqualToString:identifier]){
            item = dItem;
            *stop = true;
        }
    }];
    
    return item;
}

-(void)allowsCellularAccess:(BOOL)isAllow {
    [[YCDownloadSession downloadSession] allowsCellularAccess:isAllow];
}

- (BOOL)isAllowsCellularAccess {
    return [[YCDownloadSession downloadSession] isAllowsCellularAccess];
}

- (BOOL)isDownloadWithId:(NSString *)downloadId {
    
    YCDownloadItem *item = [self itemWithIdentifier:downloadId];
    return item != nil;
}

- (YCDownloadStatus)downloasStatusWithId:(NSString *)downloadId {
    YCDownloadItem *item = [self itemWithIdentifier:downloadId];
    if (!item) {
        return -1;
    }
    return item.downloadStatus;
}

- (void)localPushOn:(BOOL)isOn {
    self.localPushOn = isOn;
}

#pragma mark notificaton

- (void)downloadAllTaskFinished{
    [self localPushWithTitle:@"YCDownloadSession" detail:@"所有的下载任务已完成！"];
}

- (void)downloadTaskFinishedNoti:(NSNotification *)noti{
    
    YCDownloadItem *item = noti.object;
    if (item) {
        NSString *detail = [NSString stringWithFormat:@"%@ 视频，已经下载完成！", item.fileName];
        [self localPushWithTitle:@"YCDownloadSession" detail:detail];
    }
    [self saveDownloadItems];
}


#pragma mark local push

- (void)localPushWithTitle:(NSString *)title detail:(NSString *)body  {
    
    if (!self.localPushOn || title.length == 0) return;
    
    // 1.创建本地通知
    UILocalNotification *localNote = [[UILocalNotification alloc] init];
    
    // 2.设置本地通知的内容
    // 2.1.设置通知发出的时间
    localNote.fireDate = [NSDate dateWithTimeIntervalSinceNow:3.0];
    // 2.2.设置通知的内容
    localNote.alertBody = body;
    // 2.3.设置滑块的文字（锁屏状态下：滑动来“解锁”）
    localNote.alertAction = @"滑动来“解锁”";
    // 2.4.决定alertAction是否生效
    localNote.hasAction = NO;
    // 2.5.设置点击通知的启动图片
    //    localNote.alertLaunchImage = @"123Abc";
    // 2.6.设置alertTitle
//    localNote.alertTitle = title;
    // 2.7.设置有通知时的音效
    localNote.soundName = @"default";
    // 2.8.设置应用程序图标右上角的数字
    localNote.applicationIconBadgeNumber = 0;
    
    // 2.9.设置额外信息
    localNote.userInfo = @{@"type" : @1};
    
    // 3.调用通知
    [[UIApplication sharedApplication] scheduleLocalNotification:localNote];
    
}

-(void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
