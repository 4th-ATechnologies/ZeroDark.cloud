/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
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

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCFilesystemMonitor.html
 */
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

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCFilesystemMonitor.html
 */
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

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCFilesystemMonitor.html
 */
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
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCFilesystemMonitor.html
 */
+ (dispatch_source_vnode_flags_t)vnode_flags_all
{
	dispatch_source_vnode_flags_t mask =
	  DISPATCH_VNODE_DELETE | DISPATCH_VNODE_WRITE | DISPATCH_VNODE_EXTEND |
	  DISPATCH_VNODE_ATTRIB | DISPATCH_VNODE_LINK  | DISPATCH_VNODE_RENAME | DISPATCH_VNODE_REVOKE;
	
	return mask;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCFilesystemMonitor.html
 */
+ (dispatch_source_vnode_flags_t)vnode_flags_data_changed
{
	dispatch_source_vnode_flags_t mask =
	  DISPATCH_VNODE_DELETE | DISPATCH_VNODE_WRITE | DISPATCH_VNODE_EXTEND | DISPATCH_VNODE_REVOKE;
	
	return mask;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://4th-atechnologies.github.io/ZeroDark.cloud/Classes/ZDCFilesystemMonitor.html
 */
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
