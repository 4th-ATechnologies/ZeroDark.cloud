/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
 **/

#import "ZDCSharesManager.h"

#import "ZDCDatabaseManager.h"
#import "ZDCLogging.h"
#import "ZDCSplitKey.h"

// Categories
#import "NSError+S4.h"

// Log Levels: off, error, warn, info, verbose
// Log Flags : trace
#if DEBUG && robbie_hanson
static const int ddLogLevel = DDLogLevelInfo;
#elif DEBUG
static const int ddLogLevel = DDLogLevelWarning;
#else
static const int ddLogLevel = DDLogLevelWarning;
#endif
#pragma unused(ddLogLevel)

@implementation ZDCSharesManager {
	
	__weak ZeroDarkCloud *owner;
}

- (instancetype)init
{
	return nil; // To access this class use: ZeroDarkCloud.localUserManager
}

- (instancetype)initWithOwner:(ZeroDarkCloud *)inOwner
{
	if ((self = [super init]))
	{
		owner = inOwner;
		
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}



-(ZDCSplitKey*) splitKeyForLocalUserID:(NSString *)localUserID
								  withSplitNum:(NSUInteger) splitNum
{
	__block ZDCSplitKey* splitKey = NULL;
	
	[owner.databaseManager.roDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction)
	 {
		 
		 YapDatabaseAutoViewTransaction *viewTransaction = [transaction ext:Ext_View_SplitKeys];
		 if (viewTransaction)
		 {
			 YapDatabaseViewFind *find = [YapDatabaseViewFind withObjectBlock:
													^(NSString *collection, NSString *key, id object)
													{
														__unsafe_unretained ZDCSplitKey* split = (ZDCSplitKey *)object;
														
														// IMPORTANT: YapDatabaseViewFind must match the sortingBlock such that:
														//
														// myView = @[ A, B, C, D, E, F, G ]
														//                ^^^^^^^
														//   sortingBlock(A, B) => NSOrderedAscending
														//   findBlock(A)       => NSOrderedAscending
														//
														//   sortingBlock(E, D) => NSOrderedDescending
														//   findBlock(E)       => NSOrderedDescending
														//
														//   findBlock(B) => NSOrderedSame
														//   findBlock(C) => NSOrderedSame
														//   findBlock(D) => NSOrderedSame
														
														return [@(split.splitNum) compare:@(splitNum)];
													}];
			 
			 // binary search performance !!!
			 NSUInteger index = [viewTransaction findFirstMatchInGroup:localUserID using:find];
			 
			 splitKey = [viewTransaction objectAtIndex:index inGroup:localUserID];
		 }
		 
	 }];
	
	return splitKey;
}

@end
