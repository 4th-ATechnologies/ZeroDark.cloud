/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import "ZDCNetworkTools.h"

#import "ZDCLocalUserPrivate.h"
#import "NSError+Auth0API.h"

@implementation ZDCNetworkTools {
@private
	
	__weak ZeroDarkCloud *owner;
	dispatch_queue_t serialQueue;
	
	YapDatabaseConnection *_rwConnection;      // we queue hundreds of transctions - don't block rwDatabaseConnection
	YapDatabaseConnection *_decryptConnection; // decryption is slow - don't block roDatabaseConnection
	
	NSMutableDictionary *recentRequestDict;  // must access through serialQueue
}

- (instancetype)init
{
	return nil; // To access this class use: owner.networkTools (This class is internal)
}

- (instancetype)initWithOwner:(ZeroDarkCloud *)inOwner
{
	if ((self = [super init]))
	{
		owner = inOwner;
		serialQueue = dispatch_queue_create("ZDCNetworkTools", DISPATCH_QUEUE_SERIAL);
		
		recentRequestDict = [[NSMutableDictionary alloc] init];
	}
	return self;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Database Connections
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (YapDatabaseConnection *)rwConnection
{
	__block YapDatabaseConnection *connection = nil;
	
	dispatch_sync(serialQueue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		if (_rwConnection == nil)
		{
			_rwConnection = [owner.databaseManager.database newConnection];
			_rwConnection.name = @"ZDCNetworkTools.pushPull.rwConnection";
		}
		
		connection = _rwConnection;
		
	#pragma clang diagnostic pop
	}});
	
	return connection;
}

- (YapDatabaseConnection *)decryptConnection
{
	__block YapDatabaseConnection *connection = nil;
	
	dispatch_sync(serialQueue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		if (_decryptConnection == nil)
		{
			_decryptConnection = [owner.databaseManager.database newConnection];
			_decryptConnection.name = @"ZDCNetworkTools.pushPull.decryptConnection";
		}
		
		connection = _decryptConnection;
		
	#pragma clang diagnostic pop
	}});
	
	return connection;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Common Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSTimeInterval)exponentialBackoffForFailCount:(NSUInteger)failCount
{
	switch (failCount)
	{
		case 0 : return  0.0; // seconds
		case 1 : return  1.0;
		case 2 : return  2.0;
		case 3 : return  4.0;
		case 4 : return  8.0;
		case 5 : return 16.0;
		case 6 : return 32.0;
		default: return 60.0;
	}
}

- (void)addRecentRequestID:(NSString *)requestID forUser:(NSString *)localUserID
{
	if (requestID == nil) return;
	if (localUserID == nil) return;
	
	dispatch_sync(serialQueue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		NSMutableArray *recents = recentRequestDict[localUserID];
		if (recents == nil)
		{
			recents = recentRequestDict[localUserID] = [[NSMutableArray alloc] init];
		}
		
		if (![recents containsObject:requestID])
		{
			[recents insertObject:requestID atIndex:0];
			
			while (recents.count > 100)
			{
				[recents removeLastObject];
			}
		}
		
	#pragma clang diagnostic pop
	}});
}

- (BOOL)isRecentRequestID:(NSString *)requestID forUser:(NSString *)localUserID
{
	if (requestID == nil) return NO;
	if (localUserID == nil) return NO;
	
	__block BOOL result = NO;
	
	dispatch_sync(serialQueue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		NSMutableArray *recents = recentRequestDict[localUserID];
		if (recents)
		{
			result = [recents containsObject:requestID];
		}
		
	#pragma clang diagnostic pop
	}});
	
	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Auth Failure
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This method should be invoked whenever an authentication failure is detected.
**/
- (void)handleAuthFailureForUser:(NSString *)userID withError:(NSError *)error
{
	[self handleAuthFailureForUser:userID withError:error pullState:nil];
}

- (void)handleAuthFailureForUser:(NSString *)userID withError:(NSError *)error pullState:(ZDCPullState *)pullState
{
	if (pullState)
	{
		BOOL firstDetectedAuthFailure = [pullState isFirstAuthFailure];
		if (!firstDetectedAuthFailure)
		{
			return;
		}
	}
	
	BOOL isAccountSuspended = NO;
	BOOL accountNeedsA0Token = NO;
	if ([error.auth0API_error isEqualToString:kAuth0ErrorDescription_Blocked])
	{
		// The account still exists (in Auth0), but has been blocked.
		// So the account is suspended.
		
		isAccountSuspended = YES;
	}
	else if ([error.auth0API_error isEqualToString:kAuth0Error_InvalidRefreshToken])
	{
		accountNeedsA0Token = YES;
	}
	
	[[self rwConnection] asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
	
		ZDCLocalUser *user = [transaction objectForKey:userID inCollection:kZDCCollection_Users];
		user = [user copy];
		
		if (isAccountSuspended)
		{
			// Auth0 specific error code has informed us of the problem.
			// Our account is suspended.
			// This probably means the user owes us money. (expired credit card, etc)
			
			user.accountSuspended = YES;
		}
		else if(accountNeedsA0Token)
		{
			user.accountNeedsA0Token = YES;
		}
		else
		{
			// This flag will trigger a YapActionItem to check with the server.
			// If the server reports the account deleted, we'll set the appropriate user flag.
			//
			user.needsCheckAccountDeleted = YES;
		}
		
		[transaction setObject: user
		                forKey: user.uuid
		          inCollection: kZDCCollection_Users];
	}];
}

@end
