//
//  main.m
//  Dedup
//
//  Created by ASPCartman on 09/04/15.
//  Copyright (c) 2015 aspcartman. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>

@interface ASPFile : NSObject
@property (nonatomic, readonly, strong) NSURL *path;
+ (instancetype) fileAtPath:(NSURL *)path;
- (BOOL) equals:(ASPFile *)file;
@end

@implementation ASPFile
{
	unsigned char md5[CC_MD5_DIGEST_LENGTH];
	unsigned char sha1[CC_SHA1_DIGEST_LENGTH];
}
+ (instancetype) fileAtPath:(NSURL *)path
{
	return [[self alloc] initWithFilePath:path];
}

- (instancetype) initWithFilePath:(NSURL *)url
{
	if ((self = [super init]))
	{
		NSFileHandle *const handle = [NSFileHandle fileHandleForReadingFromURL:url error:nil];
		NSData *data = [handle readDataToEndOfFile];

		uint offset = (uint) (0.1*data.length);

		CC_MD5(data.bytes + offset, (CC_LONG) data.length - offset, md5);
		CC_SHA1(data.bytes + offset, (CC_LONG) data.length - offset, sha1);

		[handle closeFile];

		_path = url;
	}
	return self;
}

- (BOOL) equals:(ASPFile *)file
{
	return (memcmp(md5, file->md5, CC_MD5_DIGEST_LENGTH) == 0) && (memcmp(sha1, file->sha1, CC_SHA1_DIGEST_LENGTH) == 0);

}
@end

NSMutableArray *filesInDirectory(NSString *dirPath)
{

	NSDirectoryEnumerator *const folderEnumerator = [[NSFileManager defaultManager] enumeratorAtURL:[NSURL fileURLWithPath:dirPath] includingPropertiesForKeys:@[ ] options:0 errorHandler:nil];

	NSMutableArray     *files    = [NSMutableArray new];
	__block OSSpinLock nextLock  = OS_SPINLOCK_INIT;
	__block OSSpinLock printLock = OS_SPINLOCK_INIT;
	__block uint32     counter   = 0;

	const dispatch_queue_t fileReadQueue = dispatch_queue_create("File read queue", DISPATCH_QUEUE_CONCURRENT);
	const dispatch_group_t importGroup   = dispatch_group_create();

	printf("Going to import %s\n", [dirPath UTF8String]);
	for (int i = 0; i < 4; ++i)
	{
		dispatch_group_async(importGroup, fileReadQueue, ^{
			NSURL *url = nil;
			OSSpinLockLock(&nextLock);
			while ((url = [folderEnumerator nextObject]))
			{
				@autoreleasepool
				{
					OSSpinLockUnlock(&nextLock);
					ASPFile *file = [ASPFile fileAtPath:url];
					OSSpinLockLock(&printLock);
					[files addObject:file];
					counter++;
//					printf("\r%s\n", file.path.absoluteString.UTF8String);
					printf("\rProcessed: %u", counter);
					fflush(stdout);
					OSSpinLockUnlock(&printLock);
					OSSpinLockLock(&nextLock);
				}
			}
			OSSpinLockUnlock(&nextLock);
		});
	}
	dispatch_group_wait(importGroup, DISPATCH_TIME_FOREVER);
	printf("\nFinished\n");
	return files;
}

int main(int argc, const char *argv[])
{
	if (argc != 3)
	{
		NSLog(@"Usage: dedup exportPath originalPath");
	}

	NSString *importPath   = [NSString stringWithUTF8String:argv[1]];
	NSString *originalPath = [NSString stringWithUTF8String:argv[2]];

	NSLog(@"Going to:\nDelete files in %@\nthat are already present in %@.", importPath, originalPath);

	NSMutableArray *importFiles   = filesInDirectory(importPath);
	NSMutableArray *originalFiles = filesInDirectory(originalPath);

	uint counter = 0;
	for (ASPFile *file in importFiles)
	{
		for (ASPFile *orig in originalFiles)
		{
			if ([file equals:orig])
			{
//				NSLog(@"Found %@",file.path);
				[[NSFileManager defaultManager] removeItemAtURL:file.path error:nil];
				break;
			}

		}
		counter++;
		printf("\rCompared: %d",counter);
	}

	NSLog(@"Done");

	return 0;
};