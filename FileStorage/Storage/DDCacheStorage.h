//
//  DDCacheStorage.h
//  FileStorage
//
//  Created by mdd on 2019/3/21.
//  Copyright © 2019年 mdd. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface DDCacheStorage : NSObject

/// 以文件名为key，文件内容为value
typedef void (^DDGetFileDataCompleteBlock)(NSDictionary *data);

typedef void (^DDGetFileListCompleteBlock)(NSArray *data);

typedef void (^DDSaveDeleteCompleteBlock)(BOOL rlt);

/**
 @param dirPath 用户自定义文件夹路径，如果指定路径已经存在则返回已存在的对象。不存在，则新建文件夹，失败返回nil，成功返回存储对象
 */
+ (instancetype)cacheStorageWithDir:(NSString *)dirPath;

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

/// 文件发送失败，再次存入
- (void)earlyAddFile:(NSString *)fileName;
/// 文件发送失败，再次存入
- (void)latelyAddFile:(NSString *)fileName;

#pragma - mark 设置部分

/// 内存缓存文件个数，大于此值会存入磁盘。默认值5
@property (nonatomic, assign) NSUInteger maxMemCacheSize;
/// 允许存储文件的个数，超过此值会删掉当前文件总量的5%。如果maxFileSize为0则无限制。
@property (nonatomic, assign) NSUInteger maxFileSize;

@end
