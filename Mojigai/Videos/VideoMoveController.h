//
//  VideoMoveController.h
//  MojiGai
//
//  Created by zhaohongbin on 2026/10/21.
//  Copyright © 2026 zhaohongbin. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 视频「移动」选择页:列表展示 Documents/videos 下所有文件夹,单选一个,点「移动」把视频移过去。
/// 由调用方包一层 UINavigationController present 出来。
@interface VideoMoveController : UIViewController

/// 视频当前所在文件夹名(从候选列表排除,避免移动到自身)
@property (nonatomic, copy) NSString *currentFolderName;

/// 要移动的视频完整路径
@property (nonatomic, copy) NSString *videoPath;

/// 移动成功后回调(参数为目标文件夹名);失败留在本页并 toast
@property (nonatomic, copy, nullable) void (^onMoved)(NSString *folderName);

@end

NS_ASSUME_NONNULL_END
