/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCDirectoryManagerPrivate.h"

#import "ZDCLogging.h"

// Log Levels: off, error, warning, info, verbose
// Log Flags : trace
#if DEBUG
  static const int zdcLogLevel = ZDCLogLevelWarning;
#else
  static const int zdcLogLevel = ZDCLogLevelWarning;
#endif

@interface ZDCDirectoryManager ()
@property (atomic, strong, readwrite) NSURL *cachedDownloadDirectoryURL;
@end

@implementation ZDCDirectoryManager
{
	__weak ZeroDarkCloud *zdc;
}

- (instancetype)init
{
	return nil; // To access this class use: ZeroDarkCloud.directoryManager (or use class methods)
}

- (instancetype)initWithOwner:(ZeroDarkCloud *)inOwner
{
	if ((self = [super init]))
	{
		zdc = inOwner;
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Top Level Directories
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCDirectoryManager.html
 */
+ (NSURL *)appSupportDirectoryURL
{
	static NSURL *appSupportDirectoryURL = nil;

	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		
		NSError *error = nil;
		NSURL *url = [[NSFileManager defaultManager] URLForDirectory: NSApplicationSupportDirectory
		                                                    inDomain: NSUserDomainMask
		                                           appropriateForURL: nil
		                                                      create: YES
		                                                       error: &error];
		
	#if !TARGET_OS_IPHONE // macOS
		if (!error)
		{
			url = [url URLByAppendingPathComponent:[self bundleIdentifier] isDirectory:YES];
			
			[[NSFileManager defaultManager] createDirectoryAtURL: url
			                         withIntermediateDirectories: YES
			                                          attributes: nil
			                                               error: &error];
		}
	#endif
		
		if (error) {
			ZDCLogError(@"%@: Error creating directory: %@", THIS_METHOD, error);
		}
		
		appSupportDirectoryURL = url;
	});
	
	return appSupportDirectoryURL;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCDirectoryManager.html
 */
+ (NSURL *)appCacheDirectoryURL
{
	static NSURL *appCacheDirectoryURL = nil;
	
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{ @autoreleasepool {
		
		NSError *error = nil;
		NSURL *url = [[NSFileManager defaultManager] URLForDirectory: NSCachesDirectory
		                                                    inDomain: NSUserDomainMask
		                                           appropriateForURL: nil
		                                                      create: YES
		                                                       error: &error];
		
	#if !TARGET_OS_IPHONE // macOS
		if (!error)
		{
			url = [url URLByAppendingPathComponent:[self bundleIdentifier] isDirectory:YES];
			
			[[NSFileManager defaultManager] createDirectoryAtURL: url
			                         withIntermediateDirectories: YES
			                                          attributes: nil
			                                               error: &error];
		}
	#endif
		
		if (error) {
			ZDCLogError(@"%@: Error creating directory: %@", THIS_METHOD, error);
		}
		
		appCacheDirectoryURL = url;
	}});
	
	return appCacheDirectoryURL;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCDirectoryManager.html
 */
+ (NSURL *)tempDirectoryURL
{
	static NSURL *tempDirectoryURL = nil;
	
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{ @autoreleasepool {
		
		NSURL *url = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
		
		NSError *error = nil;
		[[NSFileManager defaultManager] createDirectoryAtURL: url
										 withIntermediateDirectories: YES
																attributes: nil
																	  error: &error];
		
		if (error) {
			ZDCLogError(@"%@: Error creating directory: %@", THIS_METHOD, error);
		}
		
		tempDirectoryURL = url;
	}});
	
	return tempDirectoryURL;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark ZDC Containers
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCDirectoryManager.html
 */
+ (NSURL *)zdcPersistentDirectoryURL
{
	static NSURL *zdcPersistentDirectoryURL = nil;
	
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{ @autoreleasepool {
		
		NSURL *url = [[self appSupportDirectoryURL] URLByAppendingPathComponent:@"zdc" isDirectory:YES];
		
		NSError *error = nil;
		[[NSFileManager defaultManager] createDirectoryAtURL: url
										 withIntermediateDirectories: YES
																attributes: nil
																	  error: &error];
		
		if (error) {
			ZDCLogError(@"%@: Error creating directory: %@", THIS_METHOD, error);
		}
		
		zdcPersistentDirectoryURL = url;
	}});
	
	return zdcPersistentDirectoryURL;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCDirectoryManager.html
 */
+ (NSURL *)zdcCacheDirectoryURL
{
	static NSURL *zdcCacheDirectoryURL = nil;
	
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{ @autoreleasepool {
		
		NSURL *url = [[self appCacheDirectoryURL] URLByAppendingPathComponent:@"zdc" isDirectory:YES];
		
		NSError *error = nil;
		[[NSFileManager defaultManager] createDirectoryAtURL: url
										 withIntermediateDirectories: YES
																attributes: nil
																	  error: &error];
		
		if (error) {
			ZDCLogError(@"%@: Error creating directory: %@", THIS_METHOD, error);
		}
		
		zdcCacheDirectoryURL = url;
	}});
	
	return zdcCacheDirectoryURL;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCDirectoryManager.html
 */
+ (NSURL *)zdcDatabaseDirectoryURL
{
	NSURL *zdc = [self zdcPersistentDirectoryURL];
	NSURL *url = [zdc URLByAppendingPathComponent:@"db" isDirectory:YES];
	
	NSError *error = nil;
	[[NSFileManager defaultManager] createDirectoryAtURL: url
									 withIntermediateDirectories: YES
															attributes: nil
																  error: &error];
	if (error) {
		ZDCLogError(@"%@: Error creating directory: %@", THIS_METHOD, error);
	}
	
	return url;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCDirectoryManager.html
 */
+ (NSURL *)zdcPersistentDataDirectoryForDatabaseName:(NSString *)databaseName
{
	NSURL *zdc = [self zdcPersistentDirectoryURL];
	NSURL *dat = [zdc URLByAppendingPathComponent:@"data" isDirectory:YES];
	NSURL *url = [dat URLByAppendingPathComponent:databaseName isDirectory:YES];
	
	NSError *error = nil;
	[[NSFileManager defaultManager] createDirectoryAtURL: url
									 withIntermediateDirectories: YES
															attributes: nil
																  error: &error];
	if (error) {
		ZDCLogError(@"%@: Error creating directory: %@", THIS_METHOD, error);
	}
	
	return url;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCDirectoryManager.html
 */
+ (NSURL *)zdcCacheDataDirectoryForDatabaseName:(NSString *)databaseName
{
	NSURL *zdc = [self zdcCacheDirectoryURL];
	NSURL *dat = [zdc URLByAppendingPathComponent:@"data" isDirectory:YES];
	NSURL *url = [dat URLByAppendingPathComponent:databaseName isDirectory:YES];
	
	NSError *error = nil;
	[[NSFileManager defaultManager] createDirectoryAtURL: url
									 withIntermediateDirectories: YES
															attributes: nil
																  error: &error];
	if (error) {
		ZDCLogError(@"%@: Error creating directory: %@", THIS_METHOD, error);
	}
	
	return url;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Database
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCDirectoryManager.html
 */
+ (NSArray<NSURL*> *)fileURLsForDatabaseName:(NSString *)databaseName
{
	NSURL *dir = [self zdcDatabaseDirectoryURL];
	
	NSString *walName = [databaseName stringByAppendingString:@"-wal"];
	NSString *shmName = [databaseName stringByAppendingString:@"-shm"];
	
	NSURL *main = [dir URLByAppendingPathComponent:databaseName isDirectory:NO];
	NSURL *wal  = [dir URLByAppendingPathComponent:walName      isDirectory:NO];
	NSURL *shm  = [dir URLByAppendingPathComponent:shmName      isDirectory:NO];
	
	return @[main, wal, shm];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCDirectoryManager.html
 */
+ (NSURL *)smiCacheDirectoryURL
{
	static NSURL *smiCacheDirectoryURL = nil;

	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{

		NSURL *parent = [self zdcPersistentDirectoryURL];
		NSURL *url = [parent URLByAppendingPathComponent:@"socialmediaicons" isDirectory:YES];

		NSError *error = nil;
		[[NSFileManager defaultManager] createDirectoryAtURL: url
		                         withIntermediateDirectories: YES
		                                          attributes: nil
		                                               error: &error];

		if (error) {
			ZDCLogError(@"%@: Error creating directory: %@", THIS_METHOD, error);
		}

		smiCacheDirectoryURL = url;
	});

	return smiCacheDirectoryURL;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCDirectoryManager.html
 */
+ (NSURL *)emptyUploadFileURL
{
	static NSURL *emptyUploadFileURL = nil;
	
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{ @autoreleasepool {
		
		NSURL *directory = [self zdcPersistentDirectoryURL];
		NSURL *url = [directory URLByAppendingPathComponent:@"empty" isDirectory:NO];
		
		NSString *path = [url path];
		
		if (![[NSFileManager defaultManager] fileExistsAtPath:path])
		{
			NSDictionary *attribute = @{
			  NSFileImmutable : @"YES"
			};
			
			[[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:attribute];
		}
		
		emptyUploadFileURL = url;
	}});
	
	return emptyUploadFileURL;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCDirectoryManager.html
 */
+ (NSURL *)generateTempURL
{
	NSString *randomUUID = [[NSUUID UUID] UUIDString];
	
	NSURL *dirURL = [self tempDirectoryURL];
	NSURL *fileURL = [dirURL URLByAppendingPathComponent:randomUUID isDirectory:NO];
	
	return fileURL;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Downloads
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@synthesize cachedDownloadDirectoryURL = __mustUseAtomicProperty_cachedDownloadDirectoryURL;

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCDirectoryManager.html
 */
- (NSURL *)downloadDirectoryURL
{
	NSURL *url = self.cachedDownloadDirectoryURL;
	if (url == nil)
	{
		NSURL *databasePath = zdc.databasePath;
		NSString *databaseName = [databasePath lastPathComponent];
		
		NSURL *dat = [[self class] zdcCacheDataDirectoryForDatabaseName:databaseName];
		url = [dat URLByAppendingPathComponent:@"downloads" isDirectory:YES];
		
		NSError *error = nil;
		[[NSFileManager defaultManager] createDirectoryAtURL: url
		                         withIntermediateDirectories: YES
		                                          attributes: nil
		                                               error: &error];

		if (error) {
			ZDCLogError(@"%@: Error creating directory: %@", THIS_METHOD, error);
		}
		else {
			self.cachedDownloadDirectoryURL = url;
		}
	}
	
	return url;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCDirectoryManager.html
 */
- (NSURL *)generateDownloadURL
{
	NSString *randomUUID = [[NSUUID UUID] UUIDString];
	
	NSURL *downloadDirectoryURL = [self downloadDirectoryURL];
	NSURL *downloadURL = [downloadDirectoryURL URLByAppendingPathComponent:randomUUID isDirectory:NO];
	
	return downloadURL;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Bundle Info
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCDirectoryManager.html
 */
+ (NSString *)bundleIdentifier
{
	static NSString *bundleIdentifier = nil;
	
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{ @autoreleasepool {
		
		bundleIdentifier = [[NSBundle mainBundle] objectForInfoDictionaryKey:(NSString *)kCFBundleIdentifierKey];
		
		if (bundleIdentifier == nil) {
			@throw [NSException exceptionWithName: @"ZDCDirectoryManager"
			                               reason: @"Unable to extract `kCFBundleIdentifierKey` from mainBundle"
			                             userInfo: nil];
		}
	}});
	
	return bundleIdentifier;
}

/**
 * See header file for description.
 * Or view the api's online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCDirectoryManager.html
 */
+ (NSString *)bundleName
{
	static NSString *bundleName = nil;
	
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{ @autoreleasepool {
		
		bundleName = [[NSBundle mainBundle] objectForInfoDictionaryKey:(NSString *)kCFBundleNameKey];
		
		if (bundleName == nil) {
			@throw [NSException exceptionWithName: @"ZDCDirectoryManager"
			                               reason: @"Unable to extract `kCFBundleNameKey` from mainBundle"
			                             userInfo: nil];
		}
	}});
	
	return bundleName;
}

@end
