//
//  DDCacheStorage.m
//  FileStorage
//
//  Created by mdd on 2019/3/21.
//  Copyright © 2019年 mdd. All rights reserved.
//

#import "DDCacheStorage.h"

static NSMapTable *gDDCacheStorageMap = nil;

@interface DDCacheStorage ()
/// 当前的所有文件名（后续可以做成最早或者最晚的n个文件）
@property (nonatomic, strong)   NSMutableArray *pendingFiles;
/// 内存缓存中间层，使日志读写更高效，同时减少文件读写次数
@property (nonatomic, strong)   NSMutableDictionary *memoryCacher;
/// 串行队列
@property (nonatomic, strong)   dispatch_queue_t squeue;
@property (nonatomic, copy)     NSString *dirPath;
@end

@implementation DDCacheStorage

+ (instancetype)cacheStorageWithDir:(NSString *)dirPath {
    @synchronized (self) {
        if (dirPath.length < 1) {
            return nil;
        }
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            gDDCacheStorageMap = [NSMapTable strongToWeakObjectsMapTable];
        });
        // 已经存在
        if ([gDDCacheStorageMap objectForKey:dirPath]) {
            return [gDDCacheStorageMap objectForKey:dirPath];
        }
        // 创建失败
        if (![self createDirectory:dirPath]) {
            return nil;
        }
        NSString *queueName = [dirPath lastPathComponent];
        queueName = [NSString stringWithFormat:@"CacheStorageQueue.%@",queueName];
        DDCacheStorage *cacheStorage = [[DDCacheStorage alloc] init];
        cacheStorage.squeue = dispatch_queue_create([queueName UTF8String], DISPATCH_QUEUE_SERIAL);
        cacheStorage.dirPath = dirPath;
        cacheStorage.pendingFiles = [NSMutableArray arrayWithCapacity:1];
        cacheStorage.maxMemCacheSize = 5;
        cacheStorage.maxFileSize = 0;
        cacheStorage.pendingFiles = [cacheStorage _existingDataFiles].mutableCopy;
        [gDDCacheStorageMap setObject:cacheStorage forKey:[dirPath copy]];
        return cacheStorage;
    }
}

#pragma mark - 对外提供api

- (void)fileList:(DDGetFileListCompleteBlock)block {
    if (!block) {
        return;
    }
    dispatch_async(self.squeue, ^{
        block([self.pendingFiles copy]);
    });
}

- (void)fileDataWithFile:(NSString *)file withCompleteBlock:(DDGetFileDataCompleteBlock)block {
    if (!block) {
        return;
    }
    if (file) {
        dispatch_async(self.squeue, ^{
            NSDictionary *data = [self _dataFromFile:file];
            block(data);
        });
    }
    else {
        block(nil);
    }
}

/// 返回最早的{文件名:文件数据}
- (void)earlyFile:(DDGetFileDataCompleteBlock)block {
    if (!block) {
        return;
    }
    dispatch_async(self.squeue, ^{
        if (self.pendingFiles.count > 0) {
            NSString *key = self.pendingFiles.firstObject;
            NSDictionary *data = [self _dataFromFile:key];
            if (key && data) {
                block(@{key:data});
            }
            else {
                block(nil);
            }
            [self.pendingFiles removeObjectAtIndex:0];
        }
        else {
            block(nil);
        }
    });
}

/// 返回最近的{文件名:文件数据}
- (void)latelyFile:(DDGetFileDataCompleteBlock) block {
    if (!block) {
        return;
    }
    dispatch_async(self.squeue, ^{
        if (self.pendingFiles.count > 0) {
            NSString *key = self.pendingFiles.lastObject;
            NSDictionary *data = [self _dataFromFile:key];
            if (key && data) {
                block(@{key:data});
            }
            [self.pendingFiles removeObjectAtIndex:self.pendingFiles.count - 1];
        }
        else {
            block(nil);
        }
    });
}

/// 发送文件失败，将文件再写到pendingFiles
- (void)earlyAddFile:(NSString *)fileName {
    if (!fileName) {
        return;
    }
    dispatch_async(self.squeue, ^{
        [self.pendingFiles insertObject:fileName atIndex:0];
    });
}

/// 发送文件失败，将文件再写到pendingFiles
- (void)latelyAddFile:(NSString *)fileName {
    if (!fileName) {
        return;
    }
    dispatch_async(self.squeue, ^{
        [self.pendingFiles addObject:fileName];
    });
}

- (BOOL)isHasValuedFile {
    return self.pendingFiles.count > 0;
}

/// 生成一个有序的文件名，下次读取时方便根据文件名排序
+ (NSString *)autoIncrementFileName {
    // 时间戳+自增数
    static long long index = 0;
    static long long timeStamp = 0;
    if (timeStamp == 0) {
        timeStamp = [[NSDate date] timeIntervalSince1970];
    }
    return [NSString stringWithFormat:@"CS_%lld_%lld",timeStamp, ++index];
}

- (NSString *)dirPath {
    return _dirPath;
}
/// 存储文件到本地或者内存
- (void)saveData:(NSDictionary *)data {
    NSDictionary *dict = [data copy];
    dispatch_async(self.squeue, ^{
        NSString *fileName = [[self class] autoIncrementFileName];
        [self.pendingFiles addObject:fileName];
        [self.memoryCacher setObject:dict forKey:fileName];
        
        if ([self.memoryCacher count] >= MAX(self.maxMemCacheSize, 1) ) {
            // 把现有的内存缓存日志存到本地
            [self _saveCacheToFile];
        }
        if (self.maxFileSize != 0 && self.pendingFiles.count >= self.maxFileSize) {
            // 删掉最早的5%
            NSUInteger fileCount = self.pendingFiles.count;
            NSUInteger removeFileCount = MAX(fileCount * 0.05, 20);
            NSArray *removeFiles = [self.pendingFiles subarrayWithRange:NSMakeRange(0, removeFileCount)];
            NSArray *saveFiles = [self.pendingFiles subarrayWithRange:NSMakeRange(removeFileCount, fileCount - removeFileCount)];
            for (NSString *file in removeFiles) {
                [self _deleteFile:file withCompleteBlock:nil];
            }
            self.pendingFiles = saveFiles.mutableCopy;
        }
    });
}

/// 从缓存或者本地删掉文件
- (void)deleteFile:(NSString *)fileName withCompleteBlock:(DDSaveDeleteCompleteBlock)block {
    dispatch_async(self.squeue, ^{
        [self _deleteFile:fileName withCompleteBlock:block];
    });
}

/// 进入后台时全部存到本地
- (void)saveCacheToFile:(DDSaveDeleteCompleteBlock) block{
    dispatch_async(self.squeue, ^{
        BOOL rlt = [self _saveCacheToFile];
        if (block) {
            block(rlt);
        }
    });
}
/// 取出文件
- (void)dataFromFile:(NSString *)fileName withComplete:(DDGetFileDataCompleteBlock) block{
    if (!block) {
        return;
    }
    dispatch_async(self.squeue, ^{
        block([self _dataFromFile:fileName]);
    });
}

- (void)existingDataFiles:(DDGetFileListCompleteBlock)block {
    if (!block) {
        return;
    }
    dispatch_async(self.squeue, ^{
        block([[self _existingDataFiles] mutableCopy]);
    });
}

#pragma mark - 对外提供api对应的内部方法

- (void)_deleteFile:(NSString *)fileName withCompleteBlock:(DDSaveDeleteCompleteBlock)block {
    BOOL rlt = NO;
    if (fileName == nil || fileName.length == 0) {
        if (block) {
            block(rlt);
        }
        return;
    }
    // 删除本地文件
    if ([self.memoryCacher objectForKey:fileName]) {
        // 如果在内存缓存中，则直接删除
        [self.memoryCacher removeObjectForKey:fileName];
        rlt = YES;
    } else {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        rlt = [fileManager removeItemAtPath:[self saveFilePathWithFileName:fileName] error:nil];
    }
    if (block) {
        block(rlt);
    }
}

- (BOOL)_saveCacheToFile {
    // 并非把所有缓存写入一个文件，而依然是单独写入各自的文件。之所以这样做是考虑到如果写入一个文件中，那么当需要其中任意一个时都需要把整个文件全量读出。
    __block BOOL rlt = YES;
    NSMutableArray *deleteArr = @[].mutableCopy;
    [self.memoryCacher enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSDictionary * _Nonnull logs, BOOL * _Nonnull stop) {
        if ([logs writeToFile:[self saveFilePathWithFileName:key] atomically:YES]) {
            [deleteArr addObject:key];
        } else {
            rlt = NO;
            *stop = YES;
        }
    }];
    for (NSString *key in deleteArr) {
        if (key) {
            [self.memoryCacher removeObjectForKey:key];
        }
    }
    return rlt;
}

- (NSDictionary *)_dataFromFile:(NSString *)fileName {
    NSDictionary *cachedLogs = [self.memoryCacher objectForKey:fileName];
    if (cachedLogs) {
        return cachedLogs;
    }
    // 去本地找
    cachedLogs = [NSDictionary dictionaryWithContentsOfFile:[self saveFilePathWithFileName:fileName]];
    return cachedLogs;
}

- (NSArray *)_existingDataFiles {
    // 缓存中的所有key + 本地的所有文件
    NSArray *sortedCachedKeys = [self.memoryCacher allKeys];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    // 比较耗时，采用一级目录，避免更大的耗时
    NSArray *rlt = [fileManager subpathsAtPath:[self dirPath]];
    sortedCachedKeys = [[sortedCachedKeys arrayByAddingObjectsFromArray:rlt] sortedArrayUsingComparator:^NSComparisonResult(NSString*  _Nonnull obj1, NSString*  _Nonnull obj2) {
        return [obj1 compare:obj2];
    }];
    return sortedCachedKeys;
}

#pragma mark - 内部方法

- (NSString *)saveFilePathWithFileName:(NSString *)fileName {
    NSString *rlt = [[self dirPath] stringByAppendingPathComponent:[NSString stringWithFormat:@"/%@", fileName]];
    return rlt;
}

- (NSMutableDictionary *)memoryCacher {
    if (_memoryCacher == nil) {
        _memoryCacher = [NSMutableDictionary dictionaryWithCapacity: MIN(self.maxMemCacheSize, 20)];
    }
    return _memoryCacher;
}

/**
 日志存储文件夹
 */
+ (BOOL)createDirectory:(NSString *)dirPath {
    if (dirPath == nil) {
        return NO;
    }
    // 文件夹不存在时新建
    BOOL isDir = NO;
    BOOL rlt = YES;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:dirPath isDirectory:&isDir]) {
        rlt = [fileManager createDirectoryAtPath:dirPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return rlt;
}

@end
