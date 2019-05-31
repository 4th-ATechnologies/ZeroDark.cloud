#import "ZDCChangeList.h"
#import "ZDCCloudPath.h"

static int const kCurrentVersion = 1;
#pragma unused(kCurrentVersion)

static NSString *const k_version                  = @"version";
static NSString *const k_latestChangeID_local     = @"latestChangeToken_local";  // 'token' is historical name
static NSString *const k_latestChangeID_remote    = @"latestChangeToken_remote"; // 'token' is historical name
static NSString *const k_pendingChanges           = @"pendingChanges";
static NSString *const k_skippedPendingChangeIDs  = @"skippedPendingChangeIDs";

@interface ZDCChangeList ()

// Add readwrite access
@property (nonatomic, copy, readwrite) NSString *latestChangeID_local;
@property (nonatomic, copy, readwrite) NSString *latestChangeID_remote;

// Declare as properties so S4DatabaseObject will monitor it for us.
// (Ensure values cannot be changed when object is marked as immutable.)
//
@property (nonatomic, copy, readwrite) NSArray<ZDCChangeItem *> *pendingChanges;
@property (nonatomic, copy, readwrite) NSSet<NSString *> *skippedPendingChangeIDs;
@end


@implementation ZDCChangeList

@synthesize latestChangeID_local = latestChangeID_local;
@synthesize latestChangeID_remote = latestChangeID_remote;

@synthesize pendingChanges = pendingChanges;
@synthesize skippedPendingChangeIDs = skippedPendingChangeIDs;

- (instancetype)initWithLatestChangeID_remote:(NSString *)_latestChangeID_remote
{
	if ((self = [super init]))
	{
		self.latestChangeID_remote = _latestChangeID_remote;
		
		// Note: latestChangeID_local should remain nil here.
		// A nil latestChangeID_local indicates we need to do a full pull.
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCoding
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]))
	{
		int version = [decoder decodeIntForKey:k_version];
		
		latestChangeID_local = [decoder decodeObjectForKey:k_latestChangeID_local];
		latestChangeID_remote = [decoder decodeObjectForKey:k_latestChangeID_remote];
		
		if (version == 0)
		{
			NSArray<NSDictionary *> *v0 = [decoder decodeObjectForKey:k_pendingChanges];
			NSMutableArray<ZDCChangeItem *> *v1 = [NSMutableArray arrayWithCapacity:v0.count];
			
			for (NSDictionary *dict in v0)
			{
				ZDCChangeItem *changeInfo = [ZDCChangeItem parseChangeInfo:dict];
				if (changeInfo) {
					[v1 addObject:changeInfo];
				}
			}
			
			pendingChanges = [v1 copy];
		}
		else
		{
			pendingChanges = [decoder decodeObjectForKey:k_pendingChanges];
		}
		
		skippedPendingChangeIDs = [decoder decodeObjectForKey:k_skippedPendingChangeIDs];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	if (kCurrentVersion != 0) {
		[coder encodeInt:kCurrentVersion forKey:k_version];
	}
	
	[coder encodeObject:latestChangeID_local forKey:k_latestChangeID_local];
	[coder encodeObject:latestChangeID_remote forKey:k_latestChangeID_remote];
	
	[coder encodeObject:pendingChanges forKey:k_pendingChanges];
	[coder encodeObject:skippedPendingChangeIDs forKey:k_skippedPendingChangeIDs];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark NSCopying
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (id)copyWithZone:(NSZone *)zone
{
	ZDCChangeList *copy = [super copyWithZone:zone]; // [S4DatabaseObject copyWithZone:]
	
	copy->latestChangeID_local = latestChangeID_local;
	copy->latestChangeID_remote = latestChangeID_remote;
	
	copy->pendingChanges = pendingChanges;
	copy->skippedPendingChangeIDs = skippedPendingChangeIDs;
	
	return copy;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Standard API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)hasPendingChange
{
	BOOL found = NO;
	for (ZDCChangeItem *change in pendingChanges)
	{
		NSString *changeID = change.uuid;
		if (![skippedPendingChangeIDs containsObject:changeID])
		{
			found = YES;
			break;
		}
	}
	
	return found;
}

- (void)didCompleteFullPull
{
	if (latestChangeID_local == nil)
	{
		self.latestChangeID_local = latestChangeID_remote;
		self.pendingChanges = nil;
		self.skippedPendingChangeIDs = nil;
	}
}

- (void)didFetchChanges:(NSArray<ZDCChangeItem *> *)changes
                  since:(NSString *)sinceChangeID
                 latest:(NSString *)latestChangeID
{
	if ([latestChangeID_local isEqualToString:sinceChangeID])
	{
		self.pendingChanges = changes;
		self.latestChangeID_remote = latestChangeID;
	}
	else if (pendingChanges.count == 0)
	{
		// Defensive programming.
		// We seem to have gotten into a bad state.
		//
		// This is likely due to the server sending us a bad change dictionary,
		// which was subsequently dropped/ignored by the client (during conversion to ZDCChangeItem).
		
		self.pendingChanges = changes;
		self.latestChangeID_remote = latestChangeID;
	}
	else
	{
		// We may be slightly ahead of the timeline.
		// This happens when:
		// - we start a pull since changeToken #1
		// - a push arrives announcing changeToken #2
		// - the pull comes back with changeTokens #2 & #3
		//
		// So we just need match up the changeTokens from the 2 arrays,
		// and then properly merge them.
		
		ZDCChangeItem *lastChange = [pendingChanges lastObject];
		NSString *lastChangeID = lastChange.uuid;
		
		NSMutableArray<ZDCChangeItem *> *newPendingChanges = [pendingChanges mutableCopy];
		BOOL found = NO;
		
		for (ZDCChangeItem *change in changes)
		{
			if (found)
			{
				[newPendingChanges addObject:change];
			}
			else
			{
				NSString *changeID = change.uuid;
				found = [lastChangeID isEqualToString:changeID];
			}
		}
		
		if (found)
		{
			self.pendingChanges = newPendingChanges;
			self.latestChangeID_remote = latestChangeID;
		}
	}
}

- (void)didProcessChangeIDs:(NSSet<NSString *> *)processedChangeIDs
{
	NSString *newLatestChangeID_local = latestChangeID_local;
	NSMutableArray<ZDCChangeItem *> *newPendingChanges = [pendingChanges mutableCopy];
	
	NSMutableSet<NSString *> *newSkippedPendingChangeIDs = [skippedPendingChangeIDs mutableCopy];
	if (newSkippedPendingChangeIDs == nil) {
		newSkippedPendingChangeIDs = [[NSMutableSet alloc] init];
	}
	
	NSUInteger i = 0;
	while (i < newPendingChanges.count)
	{
		ZDCChangeItem *change = newPendingChanges[i];
		NSString *changeID = change.uuid;
		
		if ([processedChangeIDs containsObject:changeID] ||
		    [skippedPendingChangeIDs containsObject:changeID])
		{
			if (i == 0)
			{
				[newPendingChanges removeObjectAtIndex:i];
				[newSkippedPendingChangeIDs removeObject:changeID];
				newLatestChangeID_local = changeID;
			}
			else
			{
				[newSkippedPendingChangeIDs addObject:changeID];
				i++;
			}
		}
		else
		{
			i++;
		}
	}
	
	self.pendingChanges = newPendingChanges;
	self.skippedPendingChangeIDs = newSkippedPendingChangeIDs;
	self.latestChangeID_local = newLatestChangeID_local;
}

- (void)didReceiveLocallyTriggeredPushWithOldChangeID:(NSString *)oldChangeID
                                          newChangeID:(NSString *)newChangeID
{
	if ([latestChangeID_local isEqualToString:oldChangeID])
	{
		self.latestChangeID_local = newChangeID;
		
		if ([latestChangeID_remote isEqualToString:oldChangeID])
		{
			self.latestChangeID_remote = newChangeID;
		}
		
		if (pendingChanges.count > 0)
		{
			ZDCChangeItem *firstChange = [pendingChanges firstObject];
			NSString *firstChangeID = firstChange.uuid;
			
			if ([firstChangeID isEqualToString:oldChangeID])
			{
				NSMutableArray<ZDCChangeItem *> *newPendingChanges = [pendingChanges mutableCopy];
				[newPendingChanges removeObjectAtIndex:0];
				
				self.pendingChanges = newPendingChanges;
			}
		}
	}
}

- (void)didReceivePushWithChange:(ZDCChangeItem *)change
                     oldChangeID:(NSString *)oldChangeID
                     newChangeID:(NSString *)newChangeID
{
	NSParameterAssert([change isKindOfClass:[ZDCChangeItem class]]);
	NSParameterAssert(oldChangeID != nil);
	NSParameterAssert(newChangeID != nil);
	
	// This is similar to didFetchChanges:since:latest:, with 2 key differences:
	//
	// - we're only getting a single change
	// - the newChangeToken may not be the latestChangeToken
	//
	// This is because the push chould be delayed.
	
	if ([latestChangeID_local isEqualToString:oldChangeID])
	{
		if (pendingChanges.count == 0)
		{
			self.pendingChanges = @[ change ];
		}
	}
	else
	{
		ZDCChangeItem *lastChange = [pendingChanges lastObject];
		NSString *lastChangeID = lastChange.uuid;
		
		if ([lastChangeID isEqualToString:oldChangeID])
		{
			NSMutableArray<ZDCChangeItem *> *newPendingChanges = [pendingChanges mutableCopy];
			[newPendingChanges addObject:change];
			
			self.pendingChanges = newPendingChanges;
		}
	}
	
	if ([latestChangeID_remote isEqualToString:oldChangeID])
	{
		self.latestChangeID_remote = newChangeID;
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Optimization Engine
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Returns the next change that can be processed.
 * The optimization engine may merge multiple changes in the queue into a single change,
 * and then return that change to you. When this occurs, the outChangeIDs will contain multiple values.
 *
 * You should ALWAYS use the returned outChangeIDs when invoking `didProcessChangeIDs`.
**/
- (ZDCChangeItem *)popNextPendingChange:(NSOrderedSet<NSString *> **)outChangeIDs
{
	// We implement minor optimizations available during a quick sync.
	// At this point in time, it only implements the low-hanging fruit.
	//
	// More advanced optimizations are definitely possible,
	// but they appear to come with exponentially diminishing returns.
	// This is due largely to the complexity of analyzing all the possible
	// combinations of changes that could potentially be in the queue.
	
	ZDCChangeItem *nextChange = [pendingChanges firstObject];
	if (nextChange == nil)
	{
		if (outChangeIDs) *outChangeIDs = nil;
		return nil;
	}
	
	NSMutableOrderedSet *allChangeIDs = [[NSMutableOrderedSet alloc] init]; // all changes for node (rcrd & data)
	NSMutableOrderedSet *effectiveChangeIDs = [[NSMutableOrderedSet alloc] init]; // only changes for mergedChange
	
	[allChangeIDs addObject:nextChange.uuid];
	[effectiveChangeIDs addObject:nextChange.uuid];
	
	NSString *const kPutIfMatch       = @"put-if-match";
	NSString *const kPutIfNonexistent = @"put-if-nonexistent";
	NSString *const kMove             = @"move";
	NSString *const kDeleteLeaf       = @"delete-leaf";
	NSString *const kDeleteNode       = @"delete-node";
	
	NSString *requiredFileID = nextChange.fileID;
	ZDCMutableChangeItem *mergedChange = [nextChange mutableCopy];
	
	for (NSUInteger i = 1; i < pendingChanges.count; i++)
	{
		ZDCChangeItem *change = pendingChanges[i];
		
		if (![change.fileID isEqualToString:requiredFileID])
		{
			// Change is for a different fileID.
			// Thus it can't be merged with this one.
			
			continue;
		}
		
		NSString *commandA = mergedChange.command;
		NSString *commandB =       change.command;
		
		if ([commandA isEqualToString:kPutIfMatch] ||
			 [commandA isEqualToString:kPutIfNonexistent])
		{
			if ([commandB isEqualToString:kPutIfMatch])
			{
				// Are both changes for the same component ? (rcrd vs data)
				
				NSString *pathA = mergedChange.path;
				NSString *pathB =       change.path;
				
				if (![pathA isEqualToString:pathB])
				{
					// Ignore.
					// E.g.: one change is for the RCRD, while the other is for the DATA.
					
					[allChangeIDs addObject:change.uuid];
					continue;
				}
				else
				{
					// FOUND:
					// - put-if-match + put-if-match
					// - put-if-nonexistent + put-if-match
					
					// Consecutive update commands for the same fileID & path.
					// We can merge them, which just requires updating the eTag value.
					
					mergedChange.eTag = change.eTag;
					
					[allChangeIDs addObject:change.uuid];
					[effectiveChangeIDs addObject:change.uuid];
				}
			}
			else if ([commandB isEqualToString:kPutIfNonexistent])
			{
				// Are both changes for the same component ? (rcrd vs data)
				
				NSString *pathA = mergedChange.path;
				NSString *pathB =       change.path;
				
				if (![pathA isEqualToString:pathB])
				{
					// Ignore.
					// E.g.: one change is for the RCRD, while the other is for the DATA.
					
					[allChangeIDs addObject:change.uuid];
					continue;
				}
				else
				{
					// FOUND:
					// - put-if-match + put-if-nonexistent
					// - put-if-nonexistent + put-if-nonexistent
					
					// This doesn't make any sense.
					// And so we abort at this point.
					
					break;
				}
			}
			else if ([commandB isEqualToString:kMove])
			{
				// FOUND:
				// - put-if-match + move
				// - put-if-nonexistent + move
				//
				// We've got updates to a file, followed by a move.
				
				if ([commandA isEqualToString:kPutIfNonexistent] ||
					 [skippedPendingChangeIDs containsObject:change.uuid])
				{
					// Two possibilities here:
					//
					// A. put-if-nonexistent + move
					//
					//    We can't process either operation independently of the other.
					//    The put-if-nonexistent won't work, because the file has been moved.
					//    The move won't work, because we haven't fetched it yet.
					//
					//    So we'll process the put-if-nonexistent op,
					//    but we need to update its path accordingly.
					//
					// B. put-if-nonexistent + move
					//    put-if-match + move
					//
					//    Or we've already processed this move operation.
					//    So we just need to update the path (and maybe the eTag) of our op.
					
					NSString *ext = [mergedChange.path pathExtension];
					ZDCCloudPath *dstPath = [ZDCCloudPath cloudPathFromPath:change.dstPath];
					
					mergedChange.path = [dstPath pathWithExt:ext];
					
					if ([ext isEqualToString:@"rcrd"])
					{
						mergedChange.eTag = change.eTag;
					}
					
					[allChangeIDs addObject:change.uuid];
					[effectiveChangeIDs addObject:change.uuid];
				}
				else
				{
					// FOUND:
					// - put-if-match + move
					
					if ([change.path.pathExtension isEqualToString:@"rcrd"])
					{
						// FOUND
						// - put-if-match(RCRD) + move
						//
						// We need to process the move first.
						// But in doing so, we will effectively process the put-if-match(RCRD) too,
						// as processing a move requires us to download the new RCRD from the server.
						
						mergedChange = [change mutableCopy];
						
						[allChangeIDs addObject:change.uuid];
						[effectiveChangeIDs addObject:change.uuid];
					}
					else
					{
						// FOUND
						// - put-if-match(DATA) + move
						//
						// We can't process the update yet.
						// So we're going to switch to processing the move instead.
						
						mergedChange = [change mutableCopy];
						
						[allChangeIDs addObject:change.uuid];
						[effectiveChangeIDs removeAllObjects]; // DATA only
						[effectiveChangeIDs addObject:change.uuid];
					}
				}
			}
			else if ([commandB isEqualToString:kDeleteLeaf] ||
						[commandB isEqualToString:kDeleteNode])
			{
				// FOUND:
				// - put-if-match + delete
				// - put-if-nonexistent + delete
				//
				// The delete takes over, and ends the chain of changes for the fileID.
				
				mergedChange = [change mutableCopy];
				
				[allChangeIDs addObject:change.uuid];
				effectiveChangeIDs = [allChangeIDs mutableCopy];
			}
		}
		else if ([commandA isEqualToString:kMove])
		{
			if ([commandB isEqualToString:kPutIfMatch])
			{
				// FOUND:
				// - move + put-if-match
				//
				// We're still going to process the move first,
				// but we may need to update the eTag here.
				
				if ([change.path.pathExtension isEqualToString:@"rcrd"])
				{
					// move + put-if-match (rcrd)
					
					mergedChange.eTag = change.eTag;
					
					[allChangeIDs addObject:change.uuid];
					[effectiveChangeIDs addObject:change.uuid];
				}
				else
				{
					// move + put-if-match (data)
					
					[allChangeIDs addObject:change.uuid];
					// Does NOT change effectiveChangeIDs
				}
			}
			else if ([commandB isEqualToString:kPutIfNonexistent])
			{
				// FOUND:
				// - move + put-if-nonexistent
				//
				// This doesn't make any sense.
				// And so we abort at this point.
				
				break;
			}
			else if ([commandB isEqualToString:kMove])
			{
				// FOUND:
				// - move + move
				//
				// We use the original srcPath and the new dstPath
				
				mergedChange.dstPath = change.dstPath;
				mergedChange.eTag    = change.eTag;
				
				[allChangeIDs addObject:change.uuid];
				[effectiveChangeIDs addObject:change.uuid];
			}
			else if ([commandB isEqualToString:kDeleteLeaf] ||
						[commandB isEqualToString:kDeleteNode])
			{
				// FOUND:
				// - move + delete-leaf
				// - move + delete-node
				
				NSString *srcPath = mergedChange.srcPath;
				
				mergedChange = [change mutableCopy];
				mergedChange.path = srcPath;
				
				[allChangeIDs addObject:change.uuid];
				effectiveChangeIDs = [allChangeIDs mutableCopy];
			}
		}
		else // if isNonStandardCommand(commandA)
		{
			// Other commands are not mergeable:
			//
			// - delete-leaf
			// - delete-node
			// - update-avatar
			// - update-auth0
			
			break;
		}
		
	} // end: for (NSUInteger i = 1; i < pendingChanges.count; i++)
	
	if (outChangeIDs) *outChangeIDs = effectiveChangeIDs;
	return [mergedChange copy];
}

@end
