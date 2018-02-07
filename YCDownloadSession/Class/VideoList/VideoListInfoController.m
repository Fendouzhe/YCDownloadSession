//
//  VideoListInfoController.m
//  YCDownloadSession
//
//  Created by wz on 17/3/23.
//  Copyright © 2017年 onezen.cc. All rights reserved.
//

#import "VideoListInfoController.h"
#import "VideoListInfoCell.h"
#import "VideoListInfoModel.h"
#import "VideoCacheController.h"
#import "YCDownloadManager.h"
#import "YCDownloadInfo.h"

@interface VideoListInfoController ()<VideoListInfoCellDelegate>

@property (nonatomic, strong) NSMutableArray *videoListArr;

@end

@implementation VideoListInfoController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"视频列表";
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self getVideoList];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"缓存" style:UIBarButtonItemStylePlain target:self action:@selector(goCache)];
}

- (void)viewWillAppear:(BOOL)animated {
    
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (void)getVideoList {
    
    NSString *dataPath = [[NSBundle mainBundle] pathForResource:@"video.json" ofType:nil];
    NSData *videoData = [[NSData alloc] initWithContentsOfFile:dataPath];
    NSArray *videoArr = [NSJSONSerialization JSONObjectWithData:videoData options:0 error:nil];
    _videoListArr = [VideoListInfoModel getVideoListInfo:videoArr];
    [self.tableView reloadData];
}


- (void)goCache {
    VideoCacheController *vc = [[VideoCacheController alloc] init];
    [self.navigationController pushViewController:vc animated:true];
}
#pragma mark - videolistcell delegate


/**
 点击下载
 */
- (void)videoListCell:(VideoListInfoCell *)cell downloadVideo:(VideoListInfoModel *)model {

    if ([model.file_id isEqualToString:@"10000"]) {
        YCDownloadInfo *info = [[YCDownloadInfo alloc] initWithUrl:model.mp4_url fileId:model.file_id];
        info.thumbImageUrl = model.cover;
        info.fileName = model.title;
        info.desc = @"扩展字段描述";
        info.date = [NSDate date];
        [YCDownloadManager startDownloadWithItem:info priority:0.8];
    }else{
        [YCDownloadManager startDownloadWithUrl:model.mp4_url fileName:model.title imageUrl:model.cover fileId:model.file_id];
    }
    VideoCacheController *vc = [[VideoCacheController alloc] init];
    [self.navigationController pushViewController:vc animated:true];
}

#pragma mark - Table view data source & delegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {

    return self.videoListArr.count;
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    VideoListInfoCell *cell = [VideoListInfoCell videoListInfoCellWithTableView:tableView];
    VideoListInfoModel *model = self.videoListArr[indexPath.row];
    [cell setVideoModel:model];
    cell.delegate = self;
    [cell setDownloadStatus:[YCDownloadManager downloasStatusWithId:model.mp4_url]];
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return [VideoListInfoCell rowHeight];
}

@end
