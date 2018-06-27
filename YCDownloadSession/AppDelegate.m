//
//  AppDelegate.m
//  YCDownloadSession
//
//  Created by wz on 17/3/14.
//  Copyright © 2017年 onezen.cc. All rights reserved.
//

#import "AppDelegate.h"
#import "MainTableViewController.h"
#import "YCDownloadManager.h"
#import <Bugly/Bugly.h>

@interface AppDelegate ()

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    //root vc
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    MainTableViewController *vc = [[MainTableViewController alloc] init];
    UIViewController *rootVc = [[UINavigationController alloc] initWithRootViewController:vc];
    self.window.rootViewController = rootVc;
    [self.window makeKeyAndVisible];
    
    //注册通知
    if ([[UIDevice currentDevice].systemVersion doubleValue] >= 8.0) {
        UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeAlert | UIUserNotificationTypeBadge | UIUserNotificationTypeSound categories:nil];
        [application registerUserNotificationSettings:settings];
    }
    
    //setup bugly
    [self setUpBugly];
    
    //setup downloadsession
    [self setUpDownload];
    
    return YES;
}

- (void)setUpDownload {
    //Thanks feedback: @一品戴砖侍卫
    //https://developer.apple.com/library/content/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemOverview/FileSystemOverview.html#//apple_ref/doc/uid/TP40010672-CH2-SW2
    //必须在设置用户之前设置目录， 也可以忽略用户标志，根据不同的用户指定根路径
//    [YCDownloadSession setSaveRootPath:^NSString *{
//        NSString *path = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, true).firstObject;
//        path = [path stringByAppendingPathComponent:@"download/data"];
//        return path;
//    }];
    
    //不同用户，不同的下载数据.注意：切换用户之后重新调用下setGetUserIdentify:方法，来刷新数据
    [YCDownloadMgr setGetUserIdentify:^NSString *{
        //切换用户，这里最好使用get方法
        return @"10002";
    }];
}

- (void)setUpBugly {
    BuglyConfig *config = [BuglyConfig new];
    config.blockMonitorEnable = true;
    config.channel = @"git";
    config.unexpectedTerminatingDetectionEnable = true;
    config.symbolicateInProcessEnable =  true;
    [Bugly startWithAppId:@"900036376" config:config];
}

-(void)application:(UIApplication *)application handleEventsForBackgroundURLSession:(NSString *)identifier completionHandler:(void (^)(void))completionHandler{
    NSLog(@"%s", __func__);
    [[YCDownloadSession downloadSession] addCompletionHandler:completionHandler identifier:identifier];
}


- (void)applicationWillResignActive:(UIApplication *)application {
    //test code
//    [YCDownloadMgr setGetUserIdentify:^NSString *{
//        return @"10001";
//    }];
}


#pragma mark - download push

- (void)localPushWithTitle:(NSString *)title detail:(NSString *)body  {
    
    UILocalNotification *localNote = [[UILocalNotification alloc] init];
    localNote.fireDate = [NSDate dateWithTimeIntervalSinceNow:3.0];
    localNote.alertBody = body;
    localNote.alertAction = @"滑动来解锁";
    localNote.hasAction = NO;
    localNote.soundName = @"default";
    localNote.userInfo = @{@"type" : @1};
    [[UIApplication sharedApplication] scheduleLocalNotification:localNote];
}

- (void)downloadAllTaskFinished{
    [self localPushWithTitle:@"YCDownloadSession" detail:@"所有的下载任务已完成！"];
}

- (void)downloadTaskFinishedNoti:(NSNotification *)noti{
    
    YCDownloadItem *item = noti.object;
    if (item) {
        NSString *detail = [NSString stringWithFormat:@"%@ 视频，已经下载完成！", item.fileName];
        [self localPushWithTitle:@"YCDownloadSession" detail:detail];
    }
}


@end
