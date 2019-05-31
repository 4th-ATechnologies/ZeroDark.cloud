/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import <XCTest/XCTest.h>

#import "ZDCNode.h"
#import "ZDCShareList.h"
#import "ZDCShareItem.h"

@interface test_Models : XCTestCase
@end

static NSString *const userA = @"z55tqmfr9kix1p1gntotqpwkacpuoyno";
static NSString *const userB = @"ncn3tcwifzxzohnt1id6cbdyq5739d44";
static NSString *const userC = @"jag15iacxneuco7owmegke63msbgyuyx";

@implementation test_Models

- (NSDictionary *)sampleKeysDict
{
	return @{
		@"UID:z55tqmfr9kix1p1gntotqpwkacpuoyno": @{
			@"perms": @"rws",
			@"key"  : @"eyJ2ZXJzaW9uIjoxLCJlbmNvZGluZyI6IkN1cnZlNDE0MTciLCJrZXlJRCI6InlLcVl3U2dzL2drUTRSTVlsME9wYVE9PSIsImtleVN1aXRlIjoiVGhyZWVGaXNoLTUxMiIsIm1hYyI6IndYczN5aXJlYkZvPSIsImVuY3J5cHRlZCI6Ik1JSEVCZ2xnaGtnQlpRTUVBZ01FZFRCekF3SUhBQUlCTkFJMEVhYUhYZk5IWlUvellpRWNXRCtvYzJwWmhqcmxXTUJFR1dwck1KLzZrVGdFbmRGL2ZCSGlldjBWaU41ZmR2R3cxQ0Yzb0FJMEVURGNXNVJObXUzRm9kMUp4RnVsb0Y3ZWd6Z3NKTUpGQllEMnQ2cG1LTEFpVElFcWxxam1HNDBMb3g0QkNnaFllUzBDWkFSQVF4UzF0eGZSSXB6L2tTU3Njb280Rk45blc2NHpad2hlaGRDeElYZjBDUGNHMUJQTlNlbmtwU1Q2RHJQZHZGQ1E5T3JJZlZFVDFuTk01eFNLWGRmSnRnPT0ifQ=="
		},
		@"UID:ncn3tcwifzxzohnt1id6cbdyq5739d44": @{
			@"perms": @"r",
			@"key"  : @"eyJ2ZXJzaW9uIjoxLCJlbmNvZGluZyI6IkN1cnZlNDE0MTciLCJrZXlJRCI6IkxPaUlhVFRWeTg1ZjhRckFKMUYvc1E9PSIsImtleVN1aXRlIjoiVGhyZWVGaXNoLTUxMiIsIm1hYyI6IndYczN5aXJlYkZvPSIsImVuY3J5cHRlZCI6Ik1JSEVCZ2xnaGtnQlpRTUVBZ01FZFRCekF3SUhBQUlCTkFJMEdic0hkbVZCQStWN21qb3U3MU5CODJYdmRYOWlsZ3RORlRzbEU1bDhQUDBxZzVGZFlNS0pwM0hycHVtTGQzajF4WnYwNFFJME1JNmFsWi9EdmxQL2JVb1FIQktMWW9qQVlWQzJRbmZ3YzdCUEhlNndlMG0vZUpYbWFoeng1ZEFXSGovaHVtR2FtSFkyS1FSQUp2Smd1L0I1bVA4ODlNNzJnb1pzWFpQNnhrdExzcUs4ODFvYm1CYlMzZzZnZlE0MHB6ZFJrWmJqd0dwQ2dFUkJyejFtcTE2OVBKTUk3ZU1ZT28zYndBPT0ifQ=="
		}
	};
}

- (void)test_shareList_basic
{
	ZDCShareList *shareList = [[ZDCShareList alloc] initWithDictionary:[self sampleKeysDict]];
	
	XCTAssert(shareList.count == 2);
	
	XCTAssert([shareList hasShareItemForUserID:userA]);
	XCTAssert([shareList hasShareItemForUserID:userB]);
	XCTAssert([shareList hasShareItemForUserID:userC] == NO);
	
	ZDCShareItem *itemA = [shareList shareItemForUserID:userA];
	ZDCShareItem *itemB = [shareList shareItemForUserID:userB];
	ZDCShareItem *itemC = [shareList shareItemForUserID:userC];
	
	XCTAssert(itemA != nil);
	XCTAssert(itemB != nil);
	XCTAssert(itemC == nil);
	
	XCTAssert([itemA hasPermission:ZDCSharePermission_Read]);
	XCTAssert([itemA hasPermission:ZDCSharePermission_Write]);
	XCTAssert([itemA hasPermission:ZDCSharePermission_Share]);
	XCTAssert([itemA hasPermission:ZDCSharePermission_RecordsOnly] == NO);
	
	XCTAssert([itemB hasPermission:ZDCSharePermission_Read]);
	XCTAssert([itemB hasPermission:ZDCSharePermission_Write] == NO);
	
	XCTAssert([itemA.key isKindOfClass:[NSData class]]);
	XCTAssert([itemB.key isKindOfClass:[NSData class]]);
	
	XCTAssert(itemA.key.length > 0);
	XCTAssert(itemB.key.length > 0);
}

- (void)test_shareList_makeImmutable
{
	ZDCShareList *shareList = [[ZDCShareList alloc] initWithDictionary:[self sampleKeysDict]];
	
	ZDCShareItem *itemA = [shareList shareItemForUserID:userA];
	ZDCShareItem *itemB = [shareList shareItemForUserID:userB];
	
	XCTAssert(shareList.isImmutable == NO);
	
	XCTAssert(itemA.isImmutable == NO);
	XCTAssert(itemB.isImmutable == NO);
	
	[shareList makeImmutable];
	
	XCTAssert(shareList.isImmutable == YES);
	
	XCTAssert(itemA.isImmutable == YES);
	XCTAssert(itemB.isImmutable == YES);
	
	XCTAssertThrows([itemA addPermission:ZDCSharePermission_LeafsOnly]);
}

- (void)test_shareList_deepCopy
{
	ZDCShareList *shareList = [[ZDCShareList alloc] initWithDictionary:[self sampleKeysDict]];
	
	[shareList clearChangeTracking];
	XCTAssert([shareList hasChanges] == NO);
	
	[[shareList shareItemForUserID:userB] addPermission:ZDCSharePermission_Write];
	XCTAssert([shareList hasChanges] == YES);
	
	ZDCShareList *copy = [shareList copy];
	XCTAssert([copy.rawDictionary isEqualToDictionary:shareList.rawDictionary]);
	
	XCTAssert([copy hasChanges] == YES);
	
	NSDictionary *changeset_a = [shareList changeset];
	NSDictionary *changeset_b = [copy changeset];
	
	XCTAssert([changeset_a isEqualToDictionary:changeset_b]);
	
	[[copy shareItemForUserID:userB] removePermission:ZDCSharePermission_Write];
	
	XCTAssert(![copy.rawDictionary isEqualToDictionary:shareList.rawDictionary]);
}

- (void)test_node_container
{
	ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
	
	{ // scoping
		
		ZDCShareList *temp = [[ZDCShareList alloc] initWithDictionary:[self sampleKeysDict]];
		[node.shareList mergeCloudVersion:temp withPendingChangesets:nil error:nil];
	}
	
	[node clearChangeTracking];
	
	XCTAssert(node.shareList.count == 2);
	
	ZDCShareItem *itemA = [node.shareList shareItemForUserID:userA];
	ZDCShareItem *itemB = [node.shareList shareItemForUserID:userB];
	
	[itemB addPermission:ZDCSharePermission_Write];
	
	[node makeImmutable];
	
	XCTAssert(node.isImmutable == YES);
	XCTAssert(node.shareList.isImmutable == YES);
	
	XCTAssert(itemA.isImmutable == YES);
	XCTAssert(itemB.isImmutable == YES);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Original={ alice }, LocalChanges={ }, RemoteChanges={ +bob }
 */
- (void)test_shareList_merge_2_1
{
	ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
	
	ZDCShareItem *itemA = [[ZDCShareItem alloc] init];
	[itemA addPermission:ZDCSharePermission_Read];
	[itemA addPermission:ZDCSharePermission_Write];
	[itemA addPermission:ZDCSharePermission_Share];
	
	[node.shareList addShareItem:itemA forUserID:@"alice"];
	
	[node clearChangeTracking];
	ZDCShareList *remoteList = [node.shareList copy];
	
	// Change cloud version
	
	ZDCShareItem *itemB = [[ZDCShareItem alloc] init];
	[itemB addPermission:ZDCSharePermission_Read];
	
	[remoteList addShareItem:itemB forUserID:@"bob"];
	
	// Perform merge
	
	NSError *error = nil;
	[node.shareList mergeCloudVersion:remoteList withPendingChangesets:nil error:nil];
	
	XCTAssert(error == nil);
	
	ZDCShareItem *_itemA = [node.shareList shareItemForUserID:@"alice"];
	ZDCShareItem *_itemB = [node.shareList shareItemForUserID:@"bob"];
		
	XCTAssertNotNil(_itemA);
	XCTAssertNotNil(_itemB);
		
	XCTAssert([_itemA.permissions isEqualToString:itemA.permissions]);
	XCTAssert([_itemB.permissions isEqualToString:itemB.permissions]);
}

/**
 * Original={ alice, bob }, LocalChanges={ }, RemoteChanges={ -bob }
 */
- (void)test_shareList_merge_2_2
{
	ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
	
	ZDCShareItem *itemA = [[ZDCShareItem alloc] init];
	[itemA addPermission:ZDCSharePermission_Read];
	[itemA addPermission:ZDCSharePermission_Write];
	[itemA addPermission:ZDCSharePermission_Share];
	
	ZDCShareItem *itemB = [[ZDCShareItem alloc] init];
	[itemB addPermission:ZDCSharePermission_Read];
	
	[node.shareList addShareItem:itemA forUserID:@"alice"];
	[node.shareList addShareItem:itemB forUserID:@"bob"];
	
	[node clearChangeTracking];
	ZDCShareList *remoteList = [node.shareList copy];
	
	// Change cloud version
	
	[remoteList removeShareItemForUserID:@"bob"];
	
	// Perform merge
	
	NSError *error = nil;
	[node.shareList mergeCloudVersion:remoteList withPendingChangesets:nil error:nil];
	
	XCTAssert(error == nil);
	
	ZDCShareItem *_itemA = [node.shareList shareItemForUserID:@"alice"];
	ZDCShareItem *_itemB = [node.shareList shareItemForUserID:@"bob"];
	
	XCTAssert(_itemA != nil);
	XCTAssert(_itemB == nil);
}

/**
 * Original={ alice, bob }, LocalChanges={ }, RemoteChanges={ -bob, +carol }
 */
- (void)test_shareList_merge_2_3
{
	ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
	
	ZDCShareItem *itemA = [[ZDCShareItem alloc] init];
	[itemA addPermission:ZDCSharePermission_Read];
	[itemA addPermission:ZDCSharePermission_Write];
	[itemA addPermission:ZDCSharePermission_Share];
	
	ZDCShareItem *itemB = [[ZDCShareItem alloc] init];
	[itemB addPermission:ZDCSharePermission_Read];
	
	[node.shareList addShareItem:itemA forUserID:@"alice"];
	[node.shareList addShareItem:itemB forUserID:@"bob"];
	
	[node clearChangeTracking];
	ZDCShareList *remoteList = [node.shareList copy];
	
	// Change cloud version
	
	ZDCShareItem *itemC = [[ZDCShareItem alloc] init];
	[itemC addPermission:ZDCSharePermission_Read];
	
	[remoteList removeShareItemForUserID:@"bob"];
	[remoteList addShareItem:itemC forUserID:@"carol"];
	
	// Perform merge
	
	NSError *error = nil;
	[node.shareList mergeCloudVersion:remoteList withPendingChangesets:nil error:nil];
	
	XCTAssert(error == nil);
	
	ZDCShareItem *_itemA = [node.shareList shareItemForUserID:@"alice"];
	ZDCShareItem *_itemB = [node.shareList shareItemForUserID:@"bob"];
	ZDCShareItem *_itemC = [node.shareList shareItemForUserID:@"carol"];
	
	XCTAssert(_itemA != nil);
	XCTAssert(_itemB == nil);
	XCTAssert(_itemC != nil);
}

/**
 * Original={ alice }, LocalChanges={ +bob }, RemoteChanges={ +carol }
 */
- (void)test_shareList_merge_2_4
{
	ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
	
	ZDCShareItem *itemA = [[ZDCShareItem alloc] init];
	[itemA addPermission:ZDCSharePermission_Read];
	[itemA addPermission:ZDCSharePermission_Write];
	[itemA addPermission:ZDCSharePermission_Share];
	
	[node.shareList addShareItem:itemA forUserID:@"alice"];
	
	[node clearChangeTracking];
	ZDCShareList *remoteList = [node.shareList copy];
	
	// Change local version
	
	ZDCShareItem *itemB = [[ZDCShareItem alloc] init];
	[itemB addPermission:ZDCSharePermission_Read];
	
	[node.shareList addShareItem:itemB forUserID:@"bob"];
	NSDictionary *changeset = [node.shareList changeset];
	
	// Change cloud version
	
	ZDCShareItem *itemC = [[ZDCShareItem alloc] init];
	[itemC addPermission:ZDCSharePermission_Read];
	
	[remoteList addShareItem:itemC forUserID:@"carol"];
	
	// Perform merge
	
	NSArray<NSDictionary *> *pendingChanges = @[ changeset ];
	
	NSError *error = nil;
	[node.shareList mergeCloudVersion:remoteList withPendingChangesets:pendingChanges error:nil];
	
	XCTAssert(error == nil);
	
	ZDCShareItem *_itemA = [node.shareList shareItemForUserID:@"alice"];
	ZDCShareItem *_itemB = [node.shareList shareItemForUserID:@"bob"];
	ZDCShareItem *_itemC = [node.shareList shareItemForUserID:@"carol"];
	
	XCTAssert(_itemA != nil);
	XCTAssert(_itemB != nil);
	XCTAssert(_itemC != nil);
}

/**
 * Original={ alice, bob }, LocalChanges={ +carol }, RemoteChanges={ -bob }
 */
- (void)test_shareList_merge_2_5
{
	ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
	
	ZDCShareItem *itemA = [[ZDCShareItem alloc] init];
	[itemA addPermission:ZDCSharePermission_Read];
	[itemA addPermission:ZDCSharePermission_Write];
	[itemA addPermission:ZDCSharePermission_Share];
	
	ZDCShareItem *itemB = [[ZDCShareItem alloc] init];
	[itemB addPermission:ZDCSharePermission_Read];
	
	[node.shareList addShareItem:itemA forUserID:@"alice"];
	[node.shareList addShareItem:itemB forUserID:@"bob"];
	
	[node clearChangeTracking];
	ZDCShareList *remoteList = [node.shareList copy];
	
	// Change local version
	
	ZDCShareItem *itemC = [[ZDCShareItem alloc] init];
	[itemC addPermission:ZDCSharePermission_Read];
	
	[node.shareList addShareItem:itemC forUserID:@"carol"];
	NSDictionary *changeset = [node.shareList changeset];
	
	// Change cloud version
	
	[remoteList removeShareItemForUserID:@"bob"];
	
	// Perform merge
	
	NSArray<NSDictionary *> *pendingChanges = @[ changeset ];
	
	NSError *error = nil;
	[node.shareList mergeCloudVersion:remoteList withPendingChangesets:pendingChanges error:nil];
	
	XCTAssert(error == nil);
	
	ZDCShareItem *_itemA = [node.shareList shareItemForUserID:@"alice"];
	ZDCShareItem *_itemB = [node.shareList shareItemForUserID:@"bob"];
	ZDCShareItem *_itemC = [node.shareList shareItemForUserID:@"carol"];
	
	XCTAssert(_itemA != nil);
	XCTAssert(_itemB == nil);
	XCTAssert(_itemC != nil);
}

/**
 * Original={ alice, bob }, LocalChanges={ -bob }, RemoteChanges={ +carol }
 */
- (void)test_shareList_merge_2_6
{
	ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
	
	ZDCShareItem *itemA = [[ZDCShareItem alloc] init];
	[itemA addPermission:ZDCSharePermission_Read];
	[itemA addPermission:ZDCSharePermission_Write];
	[itemA addPermission:ZDCSharePermission_Share];
	
	ZDCShareItem *itemB = [[ZDCShareItem alloc] init];
	[itemB addPermission:ZDCSharePermission_Read];
	
	[node.shareList addShareItem:itemA forUserID:@"alice"];
	[node.shareList addShareItem:itemB forUserID:@"bob"];
	
	[node clearChangeTracking];
	ZDCShareList *remoteList = [node.shareList copy];
	
	// Change local version
	
	[node.shareList removeShareItemForUserID:@"bob"];
	NSDictionary *changeset = [node.shareList changeset];
	
	// Change cloud version
	
	ZDCShareItem *itemC = [[ZDCShareItem alloc] init];
	[itemC addPermission:ZDCSharePermission_Read];
	
	[remoteList addShareItem:itemC forUserID:@"carol"];
	
	// Perform merge
	
	NSArray<NSDictionary *> *pendingChanges = @[ changeset ];
	
	NSError *error = nil;
	[node.shareList mergeCloudVersion:remoteList withPendingChangesets:pendingChanges error:nil];
	
	XCTAssert(error == nil);

	ZDCShareItem *_itemA = [node.shareList shareItemForUserID:@"alice"];
	ZDCShareItem *_itemB = [node.shareList shareItemForUserID:@"bob"];
	ZDCShareItem *_itemC = [node.shareList shareItemForUserID:@"carol"];
		
	XCTAssert(_itemA != nil);
	XCTAssert(_itemB == nil);
	XCTAssert(_itemC != nil);
}

/**
 * Original={ alice, bob, carol }, LocalChanges={ -bob }, RemoteChanges={ -carol }
 */
- (void)test_shareList_merge_2_7
{
	ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
	
	ZDCShareItem *itemA = [[ZDCShareItem alloc] init];
	[itemA addPermission:ZDCSharePermission_Read];
	[itemA addPermission:ZDCSharePermission_Write];
	[itemA addPermission:ZDCSharePermission_Share];
	
	ZDCShareItem *itemB = [[ZDCShareItem alloc] init];
	[itemB addPermission:ZDCSharePermission_Read];
	
	ZDCShareItem *itemC = [[ZDCShareItem alloc] init];
	[itemC addPermission:ZDCSharePermission_Read];
	
	[node.shareList addShareItem:itemA forUserID:@"alice"];
	[node.shareList addShareItem:itemB forUserID:@"bob"];
	[node.shareList addShareItem:itemC forUserID:@"carol"];
	
	[node clearChangeTracking];
	ZDCShareList *remoteList = [node.shareList copy];
	
	// Change local version
	
	[node.shareList removeShareItemForUserID:@"bob"];
	NSDictionary *changeset = [node.shareList changeset];
	
	// Change cloud version
	
	[remoteList removeShareItemForUserID:@"carol"];
	
	// Perform merge
	
	NSArray<NSDictionary *> *pendingChanges = @[ changeset ];
	
	NSError *error = nil;
	[node.shareList mergeCloudVersion:remoteList withPendingChangesets:pendingChanges error:nil];
	
	XCTAssert(error == nil);
	
	ZDCShareItem *_itemA = [node.shareList shareItemForUserID:@"alice"];
	ZDCShareItem *_itemB = [node.shareList shareItemForUserID:@"bob"];
	ZDCShareItem *_itemC = [node.shareList shareItemForUserID:@"carol"];
		
	XCTAssert(_itemA != nil);
	XCTAssert(_itemB == nil);
	XCTAssert(_itemC == nil);
}

/**
 * Original={ alice }, LocalChanges={ +bob }, RemoteChanges={ +bob }
 */
- (void)test_shareList_merge_2_8
{
	ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
	
	ZDCShareItem *itemA = [[ZDCShareItem alloc] init];
	[itemA addPermission:ZDCSharePermission_Read];
	[itemA addPermission:ZDCSharePermission_Write];
	[itemA addPermission:ZDCSharePermission_Share];
	
	[node.shareList addShareItem:itemA forUserID:@"alice"];
	
	[node clearChangeTracking];
	ZDCShareList *remoteList = [node.shareList copy];
	
	// Change local version
	
	ZDCShareItem *itemB_local = [[ZDCShareItem alloc] init];
	[itemB_local addPermission:ZDCSharePermission_Read];
	
	[node.shareList addShareItem:itemB_local forUserID:@"bob"];
	NSDictionary *changeset = [node.shareList changeset];
	
	// Change cloud version
	
	ZDCShareItem *itemB_remote = [[ZDCShareItem alloc] init];
	[itemB_remote addPermission:ZDCSharePermission_Read];
	
	[remoteList addShareItem:itemB_remote forUserID:@"bob"];
	
	// Perform merge
	
	NSArray<NSDictionary *> *pendingChanges = @[ changeset ];
	
	NSError *error = nil;
	[node.shareList mergeCloudVersion:remoteList withPendingChangesets:pendingChanges error:nil];
	
	XCTAssert(error == nil);
	
	ZDCShareItem *_itemA = [node.shareList shareItemForUserID:@"alice"];
	ZDCShareItem *_itemB = [node.shareList shareItemForUserID:@"bob"];
	
	XCTAssert(_itemA != nil);
	XCTAssert(_itemB != nil);
}

/**
 * Original={ alice, bob }, LocalChanges={ -bob }, RemoteChanges={ -bob }
 */
- (void)test_shareList_merge_2_9
{
	ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
	
	ZDCShareItem *itemA = [[ZDCShareItem alloc] init];
	[itemA addPermission:ZDCSharePermission_Read];
	[itemA addPermission:ZDCSharePermission_Write];
	[itemA addPermission:ZDCSharePermission_Share];
	
	ZDCShareItem *itemB = [[ZDCShareItem alloc] init];
	[itemB addPermission:ZDCSharePermission_Read];
	
	[node.shareList addShareItem:itemA forUserID:@"alice"];
	[node.shareList addShareItem:itemB forUserID:@"bob"];
	
	[node clearChangeTracking];
	ZDCShareList *remoteList = [node.shareList copy];
	
	// Change local version
	
	[node.shareList removeShareItemForUserID:@"bob"];
	NSDictionary *changeset = [node.shareList changeset];
	
	// Change remote version
	
	[remoteList removeShareItemForUserID:@"bob"];
	
	// Perform merge
	
	NSArray<NSDictionary *> *pendingChanges = @[ changeset ];
	
	NSError *error = nil;
	[node.shareList mergeCloudVersion:remoteList withPendingChangesets:pendingChanges error:nil];
	
	XCTAssert(error == nil);
	
	ZDCShareItem *_itemA = [node.shareList shareItemForUserID:@"alice"];
	ZDCShareItem *_itemB = [node.shareList shareItemForUserID:@"bob"];
	
	XCTAssert(_itemA != nil);
	XCTAssert(_itemB == nil);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Original={ alice, bob }, LocalChanges={ #bob.key }, RemoteChanges={ #bob.permissions }
 */
- (void)test_3_1
{
	ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
	
	ZDCShareItem *itemA = [[ZDCShareItem alloc] init];
	[itemA addPermission:ZDCSharePermission_Read];
	[itemA addPermission:ZDCSharePermission_Write];
	[itemA addPermission:ZDCSharePermission_Share];
	
	ZDCShareItem *itemB = [[ZDCShareItem alloc] init];
	[itemB addPermission:ZDCSharePermission_Read];
	
	[node.shareList addShareItem:itemA forUserID:@"alice"];
	[node.shareList addShareItem:itemB forUserID:@"bob"];
	
	[node clearChangeTracking];
	ZDCShareList *remoteList = [node.shareList copy];
	
	// Change local version
	
	NSData *newKey = [@"foobar" dataUsingEncoding:NSUTF8StringEncoding];
	
	ZDCShareItem *itemB_local = [node.shareList shareItemForUserID:@"bob"];
	itemB_local.key = newKey;
	
	NSDictionary *changeset = [node.shareList changeset];
	
	// Change cloud version
	
	ZDCShareItem *itemB_remote = [remoteList shareItemForUserID:@"bob"];
	[itemB_remote addPermission:ZDCSharePermission_Write];
	
	// Perform merge
	
	NSArray<NSDictionary *> *pendingChanges = @[ changeset ];
	
	NSError *error = nil;
	[node.shareList mergeCloudVersion:remoteList withPendingChangesets:pendingChanges error:nil];
	
	XCTAssert(error == nil);
	
	ZDCShareItem *_itemA = [node.shareList shareItemForUserID:@"alice"];
	ZDCShareItem *_itemB = [node.shareList shareItemForUserID:@"bob"];
		
	XCTAssert(_itemA != nil);
	XCTAssert(_itemB != nil);
	
	XCTAssert([_itemB.key isEqual:newKey]);
	XCTAssert([_itemB hasPermission:ZDCSharePermission_Write]);
}

/**
 * Original={ alice, bob }, LocalChanges={ #bob.key }, RemoteChanges={ #bob.key }
 */
- (void)test_3_2
{
	ZDCNode *node = [[ZDCNode alloc] initWithLocalUserID:@"abc123"];
	
	ZDCShareItem *itemA = [[ZDCShareItem alloc] init];
	[itemA addPermission:ZDCSharePermission_Read];
	[itemA addPermission:ZDCSharePermission_Write];
	[itemA addPermission:ZDCSharePermission_Share];
	
	ZDCShareItem *itemB = [[ZDCShareItem alloc] init];
	[itemB addPermission:ZDCSharePermission_Read];
	
	[node.shareList addShareItem:itemA forUserID:@"alice"];
	[node.shareList addShareItem:itemB forUserID:@"bob"];
	
	[node clearChangeTracking];
	ZDCShareList *remoteList = [node.shareList copy];
	
	// Change local version
	
	NSData *newKey_local = [@"foobar" dataUsingEncoding:NSUTF8StringEncoding];
	
	ZDCShareItem *itemB_local = [node.shareList shareItemForUserID:@"bob"];
	itemB_local.key = newKey_local;
	
	NSDictionary *changeset = [node.shareList changeset];
	
	// Change cloud version
	
	NSData *newKey_remote = [@"moocow" dataUsingEncoding:NSUTF8StringEncoding];
	
	ZDCShareItem *itemB_remote = [remoteList shareItemForUserID:@"bob"];
	itemB_remote.key = newKey_remote;
	
	// Perform merge
	
	NSArray<NSDictionary *> *pendingChanges = @[ changeset ];
	
	NSError *error = nil;
	[node.shareList mergeCloudVersion:remoteList withPendingChangesets:pendingChanges error:nil];
	
	XCTAssert(error == nil);
	
	ZDCShareItem *_itemA = [node.shareList shareItemForUserID:@"alice"];
	ZDCShareItem *_itemB = [node.shareList shareItemForUserID:@"bob"];
	
	XCTAssert(_itemA != nil);
	XCTAssert(_itemB != nil);
	
	XCTAssert([_itemB.key isEqual:newKey_local] == NO);
	XCTAssert([_itemB.key isEqual:newKey_remote] == YES);
}

@end
