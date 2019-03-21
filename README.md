## 为什么造这个轮子

很多情况下，APP都有这样一个需求：

* 一边不停的产出大量的数据，要将其记录
* 另一边将这些记录读出来，然后发送到服务器，上传成功删除，失败下次继续发送
* 两边逻辑相互独立不影响
* 这些数据存数据库还不太合适，但是又要频繁增删
* 最好能够有序


比如APP产生的大量埋点日志文件、用户行为日志、一些监控日志、甚至崩溃日志(卡顿)

## 功能使用，以埋点日志文件为例

所有文件操作都放在了串行队列里面，保证线程安全，处理结果为block异步回调。

先内存缓存，然后再存磁盘，尽量减少磁盘操作

* 初始化

```
#import "DDCacheStorage.h"

@interface ViewController ()
@property (nonatomic, strong) DDCacheStorage *cacheFile;
@property (nonatomic, strong) NSMutableDictionary *dictM;
@end


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


```

* 一般使用--产生日志并存储

```

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

```

> 存储的文件必须是可序列化的

* 一般使用--发送日志以及成功失败的处理

```

- (IBAction)sendEarlyFileData:(UIButton *)sender {
    static long long count = 0;
    /** 2.3 发送逻辑
     取出最早的一个文件发送。data以文件名为key，内容为value。
     这里文件名并不是完整路径，另外发送后需要记住这个文件名，后续成功或者失败要根据文件名操做
     */
    [self.cacheFile earlyFile:^(NSDictionary *data) {
        if (!data) {
            NSLog(@"no valid file");
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
```

## 提供API说明

```

#pragma - mark get

/// 文件夹路径。若用户自定义路径创建文件夹成功则返回用户自定义路径，否则返回默认
- (NSString *)dirPath;
/// 是否有文件
- (BOOL)isHasValuedFile;
/// 当前所有文件名。不是文件路径，文件路径还需要拼接 “dirPath”
- (void)fileList:(DDGetFileListCompleteBlock)block;
/// 根据文件名获取文件
- (void)fileDataWithFile:(NSString *)file withCompleteBlock:(DDGetFileDataCompleteBlock)block;

#pragma - mark delete

/// 文件删除成功或失败结果在block回调中给出，block回调为异步
- (void)deleteFile:(NSString *)fileName withCompleteBlock:(DDSaveDeleteCompleteBlock)block;

#pragma - mark save

/// 存储文件到磁盘或者内存。文件名，内部自己生成
- (void)saveData:(NSDictionary *)data;
/// 将内存文件存入磁盘，比如退到后台，退出程序一些情况 需要将缓存存入磁盘。 block 返回成功或失败，block回调为异步。
- (void)saveCacheToFile:(DDSaveDeleteCompleteBlock) block;

#pragma - mark 发送相关

/// 根据时间排序获取最早的文件，key为文件名，block回调为异步
- (void)earlyFile:(DDGetFileDataCompleteBlock) block;
/// 根据时间排序获取最近的文件，key为文件名，block回调为异步
- (void)latelyFile:(DDGetFileDataCompleteBlock) block;

/// 文件发送失败，文件名放入发送队列，不涉及文件操作
- (void)earlyAddFile:(NSString *)fileName;
/// 文件发送失败，文件名放入发送队列，不涉及文件操作
- (void)latelyAddFile:(NSString *)fileName;

#pragma - mark 设置部分

/// 内存缓存文件个数，大于此值会存入磁盘。默认值5
@property (nonatomic, assign) NSUInteger maxMemCacheSize;
/// 允许存储文件的个数，超过此值会删掉当前文件总量的5%。如果maxFileSize为0则无限制。
@property (nonatomic, assign) NSUInteger maxFileSize;

```





