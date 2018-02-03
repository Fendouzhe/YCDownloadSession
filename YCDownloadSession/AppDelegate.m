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
    // Override point for customization after application launch.
    NSLog(@"%@", NSHomeDirectory());
    
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
    
    return YES;
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

@end
