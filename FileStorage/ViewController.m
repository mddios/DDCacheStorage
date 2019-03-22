//
//  ViewController.m
//  FileStorage
//
//  Created by mdd on 2019/3/21.
//  Copyright © 2019年 mdd. All rights reserved.
//


#import "ViewController.h"

#import "DDCacheStorage.h"

static NSString *const gStringQCacheDirName = @"/DDCacheStorage";

@interface ViewController ()
@property (nonatomic, strong) DDCacheStorage *cacheFile;
@property (nonatomic, strong) NSMutableDictionary *dictM;
@end

@implementation ViewController
/// 第1大步为初始化，第2大步为使用
- (void)viewDidLoad {
    [super viewDidLoad];
    // 1.1 新建文件存储的文件夹，这里放在.../Document/DDCacheStorage/
    self.cacheFile = [DDCacheStorage cacheStorageWithDir:[self defaultDirectory]];
    // 1.2 设置内存缓存文件个数
    self.cacheFile.maxMemCacheSize = 3;
    // 1.3 最多存1万个文件，当超过此值时，删除最早5%的文件
    self.cacheFile.maxFileSize = 10000;
    self.dictM = @{}.mutableCopy;
}

/**
 Document/DDCacheStorage
 */
- (NSString *)defaultDirectory {
    NSString *defaultDirectory = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
    NSString *rlt = [defaultDirectory stringByAppendingPathComponent:gStringQCacheDirName];
    return rlt;
}


- (IBAction)addFileData:(UIButton *)sender {
    static long long count = 0;
    count++;
    NSString *key = [NSString stringWithFormat:@"data%lld",count];
    // 2.1 假设每点击一次产生一个日志，存入用户自定义的缓存中
    [self.dictM setObject:@"userClickLog" forKey:key];
    
    // 2.2 当够5条日志时，存入文件。文件名会自动生成 时间戳+自增的整型，保证唯一。 路径.../Document/DDCacheStorage/xxxx
    if (self.dictM.count >= 5) {
        [self.cacheFile saveData:self.dictM];
        [self.dictM removeAllObjects];
    }
}

- (IBAction)sendEarlyFileData:(UIButton *)sender {
    static long long count = 0;
    /** 2.3 发送逻辑
     取出最早的一个文件发送。data以文件名为key，内容为value。
     这里文件名并不是完整路径，另外发送后需要记住这个文件名，后续成功或者失败要根据文件名操做
     */
    [self.cacheFile earlyFile:^(NSDictionary *data) {
        if (!data) {
            NSLog(@"no valid file");
            self.cacheFile = nil;
            return;
        }
        NSString *fileName = data.allKeys.firstObject;
        NSDictionary *fileData = data[fileName];
        count++;
        // 2.3.1 模拟发送成功，则删除文件
        if ((count & 0x1) == 1) {
            NSLog(@"sendSuccess: %@%@",fileName,fileData);
            [self.cacheFile deleteFile:fileName withCompleteBlock:nil];
        }
        // 2.3.2 模拟发送失败，则将失败文件添加到待发送队列，这里并没有文件操作，只是将文件名添加到发送队列
        else {
            NSLog(@"sendError:%@",fileName);
            [self.cacheFile earlyAddFile:fileName];
        }
    }];
}
- (IBAction)fileList:(UIButton *)sender {
    [self.cacheFile fileList:^(NSArray *data) {
        NSLog(@"fileList:%@",data);
    }];
}

@end
