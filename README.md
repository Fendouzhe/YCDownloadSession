# YCDownloadSession
[![GitHub issues](https://img.shields.io/github/issues/onezens/YCDownloadSession.svg)](https://github.com/onezens/YCDownloadSession/issues)
[![GitHub forks](https://img.shields.io/github/forks/onezens/YCDownloadSession.svg)](https://github.com/onezens/YCDownloadSession/network)
[![GitHub stars](https://img.shields.io/github/stars/onezens/YCDownloadSession.svg)](https://github.com/onezens/YCDownloadSession/stargazers)
[![Platform](https://img.shields.io/badge/platform-iOS-yellowgreen.svg)](https://github.com/onezens/YCDownloadSession)
[![GitHub license](https://img.shields.io/github/license/onezens/YCDownloadSession.svg)](https://github.com/onezens/YCDownloadSession/blob/master/LICENSE)


### 通过Cocoapods安装

[安装Cocoapods](http://www.onezen.cc/2016/02/05/iosdev/CocoaPods.html)

```
$ sudo gem install -n /usr/local/bin cocoapods --pre
```

**Podfile**

```
source 'https://github.com/CocoaPods/Specs.git'
platform :ios, '8.0'

target 'TargetName' do
pod 'YCDownloadSession', '~> 1.2.2'
end
```

然后安装依赖库：

```
$ pod install
```




### 介绍
下载库主要有四个核心类：YCDownloadSession，YCDownloadTask，YCDownloadItem，YCDownloadManager  

1. YCDownloadSession：对NSURLSession的进一步分装，是一个单例，所有的下载任务都是由其生成和管理。是最主要的核心类。实现了下载的代理方法，通过一个可下载的url，生成一个YCDownloadTask，并且将该task的所有数据进行实时存储。
2. YCDownloadTask 将YCDownloadSession里的代理方法进一步封装和扩展，保存session生成和所需要的一些下载信息和数据。
3. YCDownloadItem 存放需要下载的视频的信息
4. YCDownloadManager 管理下载视频操作，生成一个YCDownloadItem，并且实时保存相关信息(下载状态，文件大小，已下载文件大小，以及其它的需要和UI交互的数据)，然后调用YCDownloadSession去下载该视频。



### 用法

1. AppDelegate设置后台下载成功回调方法

	```
	-(void)application:(UIApplication *)application handleEventsForBackgroundURLSession:(NSString *)identifier completionHandler:(void (^)(void))completionHandler{
	    [[YCDownloadSession downloadSession] addCompletionHandler:completionHandler];
	}
	
	```


2. 直接使用YCDownloadSession下载文件

	```
	self.downloadURL = @"http://dldir1.qq.com/qqfile/QQforMac/QQ_V6.0.1.dmg";
	


    - (void)start {
        self.downloadTask = [YCDownloadSession.downloadSession startDownloadWithUrl:self.downloadURL fileId:nil delegate:self];
    }
    - (void)resume {
        [self.downloadTask resume];
    }
    
    - (void)pause {
        [self.downloadTask pause];
    }
    
    - (void)stop {
        [self.downloadTask remove];
    }
    	
    //代理
    - (void)downloadProgress:(YCDownloadTask *)task downloadedSize:(NSUInteger)downloadedSize fileSize:(NSUInteger)fileSize {
        self.progressLbl.text = [NSString stringWithFormat:@"%f",(float)downloadedSize / fileSize * 100];
    }
    
    
    - (void)downloadStatusChanged:(YCDownloadStatus)status downloadTask:(YCDownloadTask *)task {
        if (status == YCDownloadStatusFinished) {
            self.progressLbl.text = @"download success!";
            NSLog(@"save file path: %@", task.savePath);
        }else if (status == YCDownloadStatusFailed){
            self.progressLbl.text = @"download failed!";
        }
    }

	```
	
3. YCDownloadManager 为视频类型文件专用下载管理类

	```
    /**
     开始/创建一个后台下载任务。downloadURLString作为整个下载任务的唯一标识。
     下载成功后用downloadURLString的MD5的值来保存
     文件后缀名取downloadURLString的后缀名，[downloadURLString pathExtension]
    
     @param downloadURLString 下载的资源的url
     @param fileName 资源名称,可以为空
     @param imagUrl 资源的图片,可以为空
     */
    + (void)startDownloadWithUrl:(NSString *)downloadURLString fileName:(NSString *)fileName imageUrl:(NSString *)imagUrl;
    
    /**
     开始/创建一个后台下载任务。downloadURLString作为整个下载任务的唯一标识。
     下载成功后用fileId来保存, 要确保fileId唯一
     文件后缀名取downloadURLString的后缀名，[downloadURLString pathExtension]
     
     @param downloadURLString 下载的资源的url， 不可以为空， 下载任务标识
     @param fileName 资源名称,可以为空
     @param imagUrl 资源的图片,可以为空
     @param fileId 非资源的标识,可以为空，用作下载文件保存的名称
     */
    + (void)startDownloadWithUrl:(NSString *)downloadURLString fileName:(NSString *)fileName imageUrl:(NSString *)imagUrl fileId:(NSString *)fileId;

    
        /**
     暂停一个后台下载任务
     
     @param item 创建的下载任务item
     */
    + (void)pauseDownloadWithItem:(YCDownloadItem *)item;
    
    /**
     继续开始一个后台下载任务
     
     @param item 创建的下载任务item
     */
    + (void)resumeDownloadWithItem:(YCDownloadItem *)item;
    
    /**
     删除一个后台下载任务，同时会删除当前任务下载的缓存数据
     
     @param item 创建的下载任务item
     */
    + (void)stopDownloadWithItem:(YCDownloadItem *)item;
    
    /**
     暂停所有的下载
     */
    + (void)pauseAllDownloadTask;

	
	```

4. 蜂窝煤是否允许下载的方法(YCDownloadSession, YCDownloadManager)

	```
	YCDownloadSession: 
	/**
	 是否允许蜂窝煤网络下载，以及网络状态变为蜂窝煤是否允许下载，必须把所有的downloadTask全部暂停，然后重新创建。否则，原先创建的
	 下载task依旧在网络切换为蜂窝煤网络时会继续下载
	 
	 @param isAllow 是否允许蜂窝煤网络下载
	 */
	- (void)allowsCellularAccess:(BOOL)isAllow;
	
	YCDownloadManager:
	/**
	 获取当前是否允许蜂窝煤访问状态
	 */
	- (BOOL)isAllowsCellularAccess;
	```

5. 设置最大同时进行下载的任务数

	```
	YCDownloadSession: 
	/**
	 设置下载任务的个数，最多支持3个下载任务同时进行。
	 NSURLSession最多支持5个任务同时进行
	 但是5个任务，在某些情况下，部分任务会出现等待的状态，所有设置最多支持3个
	 */
	@property (nonatomic, assign) NSInteger maxTaskCount;
	
	
	
	YCDownloadManager:
	/**
	 设置下载任务的个数，最多支持3个下载任务同时进行。
	 */
	+ (void)setMaxTaskCount:(NSInteger)count;
	```
	
6. 下载完成的通知
	* 本地通知(YCDownloadManager实现)：
	
		```
		/**
		 本地通知的开关，默认是false,可以根据通知名称自定义通知类型
		 */
		+ (void)localPushOn:(BOOL)isOn;
		```
	* 当前session中所有的任务下载完成的通知。 不包括失败、暂停的任务: `kDownloadAllTaskFinishedNoti`
	* 某一的任务下载完成的通知object为YCDownloadItem对象：`kDownloadTaskFinishedNoti`

7. 某一任务下载的状态发生变化的通知: `kDownloadStatusChangedNoti` 主要用于状态改变后，及时保存下载数据信息。



### 使用效果图

1. 单文件下载测试

  ![单文件下载测试](http://src.onezen.cc/demo/download/1.gif)

2. 多视频下载测试

  ![多视频下载测试](http://src.onezen.cc/demo/download/2.gif)
  
3. 下载通知

  ![下载通知](http://src.onezen.cc/demo/download/4.png)


### TODO

1. 4G/流量下载管理（完成）
2. 对下载任务个数进一步优化和管理（完成）
3. 下载完成后添加本地通知（完成）
4. 301/302 视频模拟测试 （完成）
5. Swift 版的下载 - 第一个稳定版发布后开始 (正在进行)


### 关于

后台下载详情： [http://www.jianshu.com/p/2ccb34c460fd](http://www.jianshu.com/p/2ccb34c460fd)

**欢迎各位关注该库，如果你有任何问题请issues我，将会随时更新新功能和解决存在的问题。**

**技术交流/反馈QQ群： 304468625**


