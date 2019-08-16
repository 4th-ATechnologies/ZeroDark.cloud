/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCCloudPathManager.h"

#import "ZDCLogging.h"
#import "ZDCNodeManager.h"
#import "ZDCTrunkNode.h"

#import "NSString+S4.h"
#import "NSString+ZeroDark.h"

// Log Levels: off, error, warn, info, verbose
// Log Flags : trace
#if DEBUG
  static const int zdcLogLevel = ZDCLogLevelWarning;
#else
  static const int zdcLogLevel = ZDCLogLevelWarning;
#endif

@implementation ZDCCloudPathManager

static ZDCCloudPathManager *sharedInstance = nil;

+ (void)initialize
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{ @autoreleasepool {
		
		sharedInstance = [[ZDCCloudPathManager alloc] init];
	}});
}

+ (instancetype)sharedInstance
{
	return sharedInstance;
}

/**
 * See header file for description.
 * Or view the reference docs online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudPathManager.html
 */
- (nullable ZDCCloudLocator *)cloudLocatorForNode:(ZDCNode *)node
                                      transaction:(YapDatabaseReadTransaction *)transaction
{
	return [self cloudLocatorForNode:node fileExtension:nil transaction:transaction];
}

/**
 * See header file for description.
 * Or view the reference docs online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudPathManager.html
 */
- (nullable ZDCCloudLocator *)cloudLocatorForNode:(ZDCNode *)node
                                    fileExtension:(nullable NSString *)fileExt
                                      transaction:(YapDatabaseReadTransaction *)transaction
{
	ZDCUser *owner = [[ZDCNodeManager sharedInstance] ownerForNode:node transaction:transaction];
	if (owner == nil || owner.aws_bucket == nil || owner.aws_region == AWSRegion_Invalid) {
		return nil;
	}
	
	ZDCCloudPath *cloudPath =
	  [self cloudPathForNode: node
	           fileExtension: fileExt
	             transaction: transaction];
	
	if (cloudPath == nil) {
		return nil;
	}
	
	return [[ZDCCloudLocator alloc] initWithRegion: owner.aws_region
	                                        bucket: owner.aws_bucket
	                                     cloudPath: cloudPath];
}

/**
 * See header file for description.
 * Or view the reference docs online:
 * https://apis.zerodark.cloud/Classes/ZDCCloudPathManager.html
 */
- (nullable ZDCCloudPath *)cloudPathForNode:(ZDCNode *)node
                                transaction:(YapDatabaseReadTransaction *)transaction
{
	return [self cloudPathForNode:node fileExtension:nil transaction:transaction];
}

/**
 * See header file for description.
 * Or view the reference docs online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudPathManager.html
 */
- (ZDCCloudPath *)cloudPathForNode:(ZDCNode *)node
                     fileExtension:(NSString *)fileExt
                       transaction:(YapDatabaseReadTransaction *)transaction
{
	ZDCNode *anchorNode = [[ZDCNodeManager sharedInstance] anchorNodeForNode:node transaction:transaction];
	
	NSString *appID = anchorNode.anchor.zAppID;
	if (!appID && [anchorNode isKindOfClass:[ZDCTrunkNode class]]) {
		appID = [(ZDCTrunkNode *)anchorNode zAppID];
	}
	
	if (appID == nil) {
		return nil;
	}
	
	NSString *dirPrefix = nil;
	
	if (node.anchor)
	{
		dirPrefix = node.anchor.dirPrefix;
	}
	else
	{
		ZDCNode *parent = [transaction objectForKey:node.parentID inCollection:kZDCCollection_Nodes];
		dirPrefix = parent.dirPrefix;
	}
	
	if (dirPrefix == nil) {
		return nil;
	}
	
	NSString *cloudName = [self cloudNameForNode:node transaction:transaction];
	
	if (cloudName.length == 0) {
		return nil;
	}
	
	NSString *fileName = nil;
	if (fileExt.length > 0)
		fileName = [NSString stringWithFormat:@"%@.%@", cloudName, fileExt];
	else
		fileName = cloudName;
	
	return [[ZDCCloudPath alloc] initWithZAppID: appID
	                                  dirPrefix: dirPrefix
	                                   fileName: fileName];
}

/**
 * See header file for description.
 * Or view the reference docs online (for both Swift & Objective-C):
 * https://apis.zerodark.cloud/Classes/ZDCCloudPathManager.html
 */
- (NSString *)cloudNameForNode:(ZDCNode *)node transaction:(YapDatabaseReadTransaction *)transaction
{
	if (node.explicitCloudName) {
		return node.explicitCloudName;
	}
	
	NSString *parentID = node.parentID;
	if (parentID == nil) {
		ZDCLogWarn(@"Cannot derive cloudName for node(%@): node.parentID is nil", node.name);
		return nil;
	}
	
	ZDCNode *parent = [transaction objectForKey:parentID inCollection:kZDCCollection_Nodes];
	if (parent == nil) {
		ZDCLogWarn(@"Cannot derive cloudName for node(%@): node.parent is missing", node.name);
		return nil;
	}
	
	NSData *parentDirSalt = parent.dirSalt;
	if (parentDirSalt == nil) {
		ZDCLogWarn(@"Cannot derive cloudName for node(%@): node.parent.dirSalt is nil", node.name);
		return nil;
	}
	
	return [self cloudNameForName:node.name withParentDirSalt:parentDirSalt];
}

/**
 * Private method - declared in ZDCCloudPathManagerPrivate.h
 */
- (NSString *)cloudNameForName:(NSString *)name withParentDirSalt:(NSData *)parentDirSalt
{
	// The treesystem is case-insensitive.
	// See discussion here for details & explanation:
	// https://zerodarkcloud.readthedocs.io/en/latest/client/tree/
	//
	NSString *nameToHash = [name lowercaseString];
	
	return [nameToHash KDFWithSeedKey:parentDirSalt label:@"file_salt_label"];
}

@end
