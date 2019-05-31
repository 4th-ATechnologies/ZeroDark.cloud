/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import "ZDCFilesystemMonitor.h"

#import <os/lock.h>
#import <YapDatabase/YapDatabaseAtomic.h>


@implementation ZDCFilesystemMonitor {
	
	YAPUnfairLock spinlock;
	dispatch_source_t monitorSource;
}

@synthesize url = url;
@synthesize isDirectory = isDirectory;

- (instancetype)initWithFileURL:(NSURL *)fileURL
{
	if ((self = [super init]))
	{
		url = fileURL;
		isDirectory = NO;
		spinlock = YAP_UNFAIR_LOCK_INIT;
	}
	return self;
}

- (instancetype)initWithDirectoryURL:(NSURL *)directoryURL
{
	if ((self = [super init]))
	{
		url = directoryURL;
		isDirectory = YES;
		spinlock = YAP_UNFAIR_LOCK_INIT;
	}
	return self;
}

- (void)dealloc
{
	if (monitorSource) {
		dispatch_source_cancel(monitorSource);
	}
}

- (BOOL)monitorWithMask:(dispatch_source_vnode_flags_t)mask
                  queue:(dispatch_queue_t)queue
                  block:(void (^)(dispatch_source_vnode_flags_t mask))block
{
	if (queue == NULL)
		queue = dispatch_get_main_queue();
	
	int fd;
	if (isDirectory) {
		fd = open([url fileSystemRepresentation], O_EVTONLY);
	}
	else {
		fd = open([url fileSystemRepresentation], O_RDONLY);
	}
	
	if (fd < 0)
	{
		return NO;
	}
	
	dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, fd, mask, queue);
	
	dispatch_source_set_event_handler(source, ^{
		
		dispatch_source_vnode_flags_t changes = dispatch_source_get_data(source);
		block(changes);
	});
	
	dispatch_source_set_cancel_handler(source, ^{
		close(fd);
	});
	
	BOOL success = YES;
	YAPUnfairLockLock(&spinlock);
	{
		if (monitorSource == NULL) {
			monitorSource = source;
			success = YES;
		}
	}
	YAPUnfairLockUnlock(&spinlock);
	
	if (success)
	{
		dispatch_resume(source);
		return YES;
	}
	else
	{
		dispatch_source_cancel(source);
		return NO;
	}
}

/**
 * Returns a mask with every possible event
**/
+ (dispatch_source_vnode_flags_t)vnode_flags_all
{
	dispatch_source_vnode_flags_t mask =
	  DISPATCH_VNODE_DELETE | DISPATCH_VNODE_WRITE | DISPATCH_VNODE_EXTEND |
	  DISPATCH_VNODE_ATTRIB | DISPATCH_VNODE_LINK  | DISPATCH_VNODE_RENAME | DISPATCH_VNODE_REVOKE;
	
	return mask;
}

/**
 * Returns a mask with flags only for when the actual bytes change
**/
+ (dispatch_source_vnode_flags_t)vnode_flags_data_changed
{
	dispatch_source_vnode_flags_t mask =
	  DISPATCH_VNODE_DELETE | DISPATCH_VNODE_WRITE | DISPATCH_VNODE_EXTEND | DISPATCH_VNODE_REVOKE;
	
	return mask;
}

/**
 * Utility method that returns a string listing the flags specified by the given mask;
**/
+ (NSString *)vnode_flags_description:(dispatch_source_vnode_flags_t)mask
{
	NSMutableArray *flags = [NSMutableArray arrayWithCapacity:8];
	
	if (mask & DISPATCH_VNODE_DELETE)
		[flags addObject:@"DISPATCH_VNODE_DELETE"];
	
	if (mask & DISPATCH_VNODE_WRITE)
		[flags addObject:@"DISPATCH_VNODE_WRITE"];
	
	if (mask & DISPATCH_VNODE_EXTEND)
		[flags addObject:@"DISPATCH_VNODE_EXTEND"];
	
	if (mask & DISPATCH_VNODE_ATTRIB)
		[flags addObject:@"DISPATCH_VNODE_ATTRIB"];
	
	if (mask & DISPATCH_VNODE_LINK)
		[flags addObject:@"DISPATCH_VNODE_LINK"];
	
	if (mask & DISPATCH_VNODE_RENAME)
		[flags addObject:@"DISPATCH_VNODE_RENAME"];
	
	if (mask & DISPATCH_VNODE_REVOKE)
		[flags addObject:@"DISPATCH_VNODE_REVOKE"];
	
	return [flags componentsJoinedByString:@", "];
}

@end
