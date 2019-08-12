/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
 **/

#import "ZDCSearchUserManagerPrivate.h"

#import "ZeroDarkCloud.h"
#import "ZeroDarkCloudPrivate.h"

#import "ZDCConstantsPrivate.h"
#import "Auth0ProviderManager.h"
#import "ZDCLocalUserManagerPrivate.h"

#import "Auth0Utilities.h"
#import "AWSRegions.h"

// Categories
#import "NSDate+ZeroDark.h"
#import "NSString+ZeroDark.h"

// Libraries
#import <YapDatabase/YapCache.h>

#import "ZDCLogging.h"

// Log Levels: off, error, warning, info, verbose
// Log Flags : trace
#if DEBUG
static const int zdcLogLevel = ZDCLogLevelWarning;
#else
static const int zdcLogLevel = ZDCLogLevelWarning;
#endif

@interface ZDCSearchUserMatching ()
@property (nonatomic, copy, readwrite) NSString     * auth0_profileID;
@property (nonatomic, copy, readwrite) NSString     * matchingString;
@property (nonatomic, copy, readwrite) NSArray <NSValue /*(NSRange) */*> * matchingRanges;
@end

@implementation ZDCSearchUserMatching

- (id)copyWithZone:(NSZone *)zone
{
    ZDCSearchUserMatching *copy = [[[self class] alloc] init];
    [self copyTo:copy];
    return copy;
}

- (void)copyTo:(ZDCSearchUserMatching *)copy
{
    copy->_auth0_profileID = _auth0_profileID;
    copy->_matchingString = _matchingString;
    copy->_matchingRanges = _matchingRanges;
 }

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p, auth0_profileID: %@, matchingString: %@, rangesFound: %ld>", NSStringFromClass([self class]), self,
            self.auth0_profileID, self.matchingString, self.matchingRanges.count ];
}

@end
/**
 * ZDCSearchUserResult is s similar to ZDCUser and it's values can be copied to ZDCUser
 */

@interface ZDCSearchUserResult  ()
@property (nonatomic, copy, readwrite)           NSString     * uuid;
@property (nonatomic, readwrite)                 AWSRegion      aws_region;
@property (nonatomic, copy, readwrite, nullable) NSString     * aws_bucket;
@property (nonatomic, copy, readwrite)           NSDictionary * auth0_profiles;
//@property (nonatomic, copy, readwrite ,nullable) NSString     * auth0_preferredID;
@property (nonatomic, copy, readwrite, nullable) NSDate       * auth0_lastUpdated;
@property (nonatomic, copy, readwrite, nullable) NSArray<ZDCSearchUserMatching*>* matches;
@end

@implementation ZDCSearchUserResult

- (instancetype)initWithUser:( ZDCUser* _Nonnull )inUser
{
    if ((self = [super init]))
    {
        self.uuid = inUser.uuid;
        self.aws_region = inUser.aws_region;
        self.aws_bucket = inUser.aws_bucket;
        
        NSDictionary * auth0_profiles = [Auth0Utilities excludeRecoveryProfile:inUser.auth0_profiles];
        self.auth0_profiles = auth0_profiles;
        self.auth0_lastUpdated = inUser.auth0_lastUpdated;
        self.auth0_preferredID = inUser.auth0_preferredID;
     }
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    ZDCSearchUserResult *copy = [[[self class] alloc] init];
    [self copyTo:copy];
    return copy;
}

- (void)copyTo:(ZDCSearchUserResult *)copy
{
    copy->_uuid = _uuid;
    copy->_aws_region = _aws_region;
    copy->_aws_bucket = _aws_bucket;
    copy->_auth0_profiles = _auth0_profiles;
    copy->_auth0_preferredID = _auth0_preferredID;
    copy->_auth0_lastUpdated = _auth0_lastUpdated;
    copy->_matches = _matches;
}

- (NSString *)description {
     return [NSString stringWithFormat:@"<%@: %p, uuid: %@, aws_region: %@, bucket: %@, auth0_profile count <%ld>",
            NSStringFromClass([self class]), self,
            self.uuid,
            [AWSRegions shortNameForRegion:self.aws_region],
            self.aws_bucket,
            self.auth0_profiles.count ];
}
@end


@interface NSString (ZDCSearchUserManager)

-(NSArray*) compareQueryAndCreateRanges:(NSString*)queryString;
@end

@implementation NSString (ZDCSearchUserManager)

-(NSArray*) compareQueryAndCreateRanges:(NSString*)queryString
{
    __block NSMutableArray* results = NSMutableArray.array;
    NSMutableArray* words = NSMutableArray.array;
    
    for( NSString* word in  [queryString componentsSeparatedByCharactersInSet: [NSCharacterSet whitespaceCharacterSet]])
    {
        if(word.length)
            [words addObject:word];
    }
    
    [words enumerateObjectsUsingBlock:^(NSString* word, NSUInteger idx, BOOL * _Nonnull stop) {
        
        NSRange searchRange = NSMakeRange(0, self.length);
        
        NSValue *lastVal = results.lastObject;
        if(lastVal)
        {
            NSRange lastRange = lastVal.rangeValue;
            NSUInteger start = lastRange.location + lastRange.length;
            NSUInteger length = self.length - start;
            searchRange = NSMakeRange(start, length );
        }
        
        NSRange range = [self rangeOfString:word
                                    options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch
                                      range:searchRange];
        
        
        if(range.location != NSNotFound)
        {
            [results addObject: [NSValue valueWithRange:range]];
        }
    }];
    
    return results;
}

@end

@implementation ZDCSearchUserManager
{
    __weak ZeroDarkCloud *zdc;
    
    dispatch_queue_t cacheQueue;
    void *IsOnCacheQueueKey;
    
    YapCache *resultsCache;         // must be accessed from within cacheQueue
    
    YapDatabaseConnection     *databaseConnection;
    Auth0ProviderManager        *providerManager;
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
        
        cacheQueue = dispatch_queue_create("SearchUserManager.cacheQueue", DISPATCH_QUEUE_SERIAL);
    
        IsOnCacheQueueKey = &IsOnCacheQueueKey;
        dispatch_queue_set_specific(cacheQueue, IsOnCacheQueueKey, IsOnCacheQueueKey, NULL);
        
        NSUInteger resultsCacheSize = 32;
        
        resultsCache = [[YapCache alloc] initWithCountLimit:resultsCacheSize];
        resultsCache.allowedKeyClasses = [NSSet setWithObject:[NSString class]];
        resultsCache.allowedObjectClasses = [NSSet setWithObject:[ZDCSearchUserResult class]];

        databaseConnection  = zdc.databaseManager.roDatabaseConnection;
        providerManager     = zdc.auth0ProviderManager;

    }
    return self;
}

- (NSError *)errorWithDescription:(NSString *)description
{
    NSDictionary *userInfo = nil;
    if (description) {
        userInfo = @{ NSLocalizedDescriptionKey: description };
    }
    
    NSString *domain = NSStringFromClass([self class]);
    
    return [NSError errorWithDomain:domain code:0 userInfo:userInfo];
}

#pragma mark - cache control

- (void)unCacheAll
{
	__weak typeof(self) weakSelf = self;
	dispatch_async(cacheQueue, ^{
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf)
		{
			[strongSelf->resultsCache removeAllObjects];
		}
	});
}

- (void)unCacheUserID:(NSString*)userID
{
	__weak typeof(self) weakSelf = self;
	dispatch_async(cacheQueue, ^{
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf)
		{
			[strongSelf->resultsCache removeObjectForKey:userID];
		}
	});
}

#pragma mark - search results processing




-(NSArray<ZDCSearchUserMatching*>*) createMatchingFromProfiles:(NSDictionary*) auth0_profiles
                                        queryString:(NSString *)queryString
{
    __block NSMutableArray<ZDCSearchUserMatching*>* matching = NSMutableArray.array;
    
    [auth0_profiles enumerateKeysAndObjectsUsingBlock:^(NSString* key, NSDictionary* profile, BOOL * _Nonnull stop) {
        
        NSString* connection   = [profile objectForKey:@"connection"];
        NSString* username         = [profile objectForKey:@"username"];
        NSString* email         = [profile objectForKey:@"email"];  // dont use subscript for dictionary -- it return [NSNull null]
        NSString* name              = [profile objectForKey:@"name"];
        NSString* nickname         = [profile objectForKey:@"nickname"];
        
        // process nsdictionary issues
        if([username isKindOfClass:[NSNull class]])
            username = nil;
        if([email isKindOfClass:[NSNull class]])
            email = nil;
        if([name isKindOfClass:[NSNull class]])
            name = nil;
        if([nickname isKindOfClass:[NSNull class]])
            nickname = nil;
        
        if(email.length)
        {
            email = [email substringToIndex:[email rangeOfString:@"@"].location];
        }
        
        if(![connection isEqualToString:kAuth0DBConnection_Recovery])
        {
            NSArray* ranges = nil;
            NSString* matchItem = nil;
            
            NSMutableArray* words = NSMutableArray.array;

            for( NSString* word in  [queryString componentsSeparatedByCharactersInSet: [NSCharacterSet whitespaceCharacterSet]])
            {
                if(word.length)
                   [words addObject:word];
            }
 
            ranges = [name compareQueryAndCreateRanges:queryString];
            if(ranges.count == words.count)
            {
                matchItem = name;
                goto found;
            }
            
            ranges = [username compareQueryAndCreateRanges:queryString];
            if(ranges.count == words.count)
            {
                matchItem = username;
                goto found;
            }
            
            ranges = [email compareQueryAndCreateRanges:queryString];
            if(ranges.count == words.count)
            {
                matchItem = email;
                goto found;
            }
            
            ranges = [nickname compareQueryAndCreateRanges:queryString];
            if(ranges.count == words.count)
            {
                matchItem = nickname;
                goto found;
            }
            
        found:
            
            if(matchItem)
            {
                ZDCSearchUserMatching* match =  [[ZDCSearchUserMatching alloc] init];
                match.auth0_profileID = key;
                match.matchingString = matchItem;
                match.matchingRanges = ranges;
                [matching addObject:match];
            }
        }
        
    }];
    
    return matching;
}

#pragma mark - Search Database

- (NSArray<ZDCSearchUserResult *> *)searchDatabaseForQuery:(NSString *)queryString
                                    providerFilters:(NSArray<NSString *> *)providers
                                    withTransaction:(YapDatabaseReadTransaction *)transaction
{
    NSMutableArray <ZDCSearchUserResult*>* searchResults = [NSMutableArray array];
    
    [transaction enumerateKeysAndObjectsInCollection:kZDCCollection_Users
                                          usingBlock:^(NSString *uuid, ZDCUser *user, BOOL *stop)
     {
         if (user.hasRegionAndBucket)
         {
             __block BOOL hasMatch = NO;
             __block NSMutableDictionary *profiles =  [NSMutableDictionary dictionary];
             
             [user.auth0_profiles enumerateKeysAndObjectsUsingBlock:^(id key, NSDictionary *profile, BOOL *stop)
              {
                  NSString * email    = profile[@"email"];
                  NSString * name     = profile[@"name"];
                  NSString * username = profile[@"username"];
                  NSString * nickname = profile[@"nickname"];
                  BOOL isRecoveryId   = [Auth0Utilities isRecoveryProfile:profile];
                  
                  // process nsdictionary issues
                  if ([username isKindOfClass:[NSNull class]])
                      username = nil;
                  if ([email isKindOfClass:[NSNull class]])
                      email = nil;
                  if ([name isKindOfClass:[NSNull class]])
                      name = nil;
                  if ([nickname isKindOfClass:[NSNull class]])
                      nickname = nil;
                  
                  
                  // filter out the recovery ID
                  if (!isRecoveryId)
                  {
                      NSArray* comps = [key componentsSeparatedByString:@"|"];
                      NSString* provider = comps[0];
                      //    NSString* user_id  = comps[1];
                      
                      NSString* displayName = nil;
                      
                      if (!providers.count || [providers containsObject:provider])
                      {
                          if ([provider isEqualToString:A0StrategyNameAuth0])
                          {
                              if ([Auth0Utilities is4thAEmail:email])
                              {
                                  displayName = [Auth0Utilities usernameFrom4thAEmail:email];
                                  email = nil;
                              }
                          }
                          
                          if(email.length)
                          {
                              email = [email substringToIndex:[email rangeOfString:@"@"].location];
                          }
                          
                          if (!displayName && name.length)
                              displayName =  name;
                          
                          if (!displayName && username.length)
                              displayName =  username;
                          
                          if (!displayName && email.length)
                              displayName =  email;
                          
                          if (!displayName && nickname.length)
                              displayName =  nickname;
                          
                          NSArray *words = [queryString componentsSeparatedByCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
                          
                          if (!hasMatch)
                          {
                              if ([displayName compareQueryAndCreateRanges:queryString].count == words.count)
                                  hasMatch = YES;
                              else if ([name compareQueryAndCreateRanges:queryString].count == words.count)
                                  hasMatch = YES;
                              else if ([username compareQueryAndCreateRanges:queryString].count == words.count)
                                  hasMatch = YES;
                              else if ([nickname compareQueryAndCreateRanges:queryString].count == words.count)
                                  hasMatch = YES;
                              else if([email compareQueryAndCreateRanges:queryString].count == words.count)
                                  hasMatch = YES;
                          }
                          
                      }
                      
                      [profiles setObject:profile forKey:key];
                  }
              }];
             
             if (hasMatch)
             {
                 ZDCSearchUserResult* result =  [[ZDCSearchUserResult alloc] init];
                 result.uuid = user.uuid;
                 result.aws_bucket = user.aws_bucket;
                 result.aws_region = user.aws_region;
                 result.auth0_profiles = profiles;        // profiles wth recovery key filtered out
                 result.auth0_preferredID = user.auth0_preferredID;
                 result.auth0_lastUpdated = user.auth0_lastUpdated;
                 
                 NSArray<ZDCSearchUserMatching*>* matches = [self createMatchingFromProfiles:user.auth0_profiles
                                                                                 queryString:queryString];
                 if(matches.count)
                     result.matches = matches;
                 
                 [searchResults addObject:result];
                 
             }
         }
     }];
    
    return searchResults;
}


#pragma mark Search Cache

-(NSArray <ZDCSearchUserResult*>*) searchCacheForQuery:(NSString *)queryString
                                providerFilters:(NSArray <NSString*>*)providers
{
    __block NSMutableArray <ZDCSearchUserResult*>* searchResults = NSMutableArray.array;
    
    dispatch_sync(cacheQueue, ^{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-retain-self"
        
        [ resultsCache enumerateKeysAndObjectsWithBlock:^(id  _Nonnull key, ZDCSearchUserResult* result, BOOL * _Nonnull stop)
         {
             NSDictionary* auth0_profiles     = result.auth0_profiles;
             __block BOOL hasMatch = NO;
             
             [auth0_profiles enumerateKeysAndObjectsUsingBlock:^(NSString* profileID, NSDictionary* profile, BOOL * _Nonnull stop2)
              {
                  NSString* email          = [profile objectForKey:@"email"];
                  NSString* name              = [profile objectForKey:@"name"];
                  NSString* username          = [profile objectForKey:@"username"];
                  NSString* nickname       = [profile objectForKey:@"nickname"];
                  BOOL isRecoveryId =  [Auth0Utilities isRecoveryProfile:profile];
                  
                  // process nsdictionary issues
                  if([username isKindOfClass:[NSNull class]])
                      username = nil;
                  if([email isKindOfClass:[NSNull class]])
                      email = nil;
                  if([name isKindOfClass:[NSNull class]])
                      name = nil;
                  if([nickname isKindOfClass:[NSNull class]])
                      nickname = nil;
                  
                  if(!isRecoveryId)
                  {
                      NSArray* comps = [profileID componentsSeparatedByString:@"|"];
                      NSString* provider = comps[0];
                      
                      if(!providers.count || [providers containsObject:provider])
                      {
                          NSString* displayName = nil;
                          
                          if([provider isEqualToString:A0StrategyNameAuth0])
                          {
                              if([Auth0Utilities is4thAEmail:email])
                              {
                                  displayName = [Auth0Utilities usernameFrom4thAEmail:email];
                                  email = nil;
                              }
                          }
                          
                          if(email.length)
                          {
                              email = [email substringToIndex:[email rangeOfString:@"@"].location];
                          }
                          
                          if(!displayName && name.length)
                              displayName =  name;
                          
                          if(!displayName && username.length)
                              displayName =  username;
                          
                          if(!displayName && email.length)
                              displayName =  email;
                          
                          if(!displayName && nickname.length)
                              displayName =  nickname;
                          
                          NSArray *words = [queryString componentsSeparatedByCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
                          
                          if(!hasMatch)
                          {
                              if([displayName compareQueryAndCreateRanges:queryString].count == words.count)
                                  hasMatch = YES;
                              else if([name compareQueryAndCreateRanges:queryString].count == words.count)
                                  hasMatch = YES;
                              else if([username compareQueryAndCreateRanges:queryString].count == words.count)
                                  hasMatch = YES;
                              else if([nickname compareQueryAndCreateRanges:queryString].count == words.count)
                                  hasMatch = YES;
                              else if([email compareQueryAndCreateRanges:queryString].count == words.count)
                                  hasMatch = YES;
                          }
                          
                          if(hasMatch)
                          {
                              NSArray<ZDCSearchUserMatching*>* matches = [self createMatchingFromProfiles:auth0_profiles
                                                                                              queryString:queryString];
                              if(matches.count)
                              {
                                  result.matches = matches;
                                  [searchResults addObject:result];
                                  *stop2 = YES;
                              }
                          }
                          
                      }
                  };
              }];
             
         }];
#pragma clang diagnostic pop
        
    });
    
    return searchResults;
}


#pragma mark Search Server

- (void)searchServerForQuery:(NSString *)queryString
                   forUserID:(NSString *)userID
             providerFilters:(NSArray <NSString*>*)providers
             completionQueue:(dispatch_queue_t)inCompletionQueue
             completionBlock:(void (^)(NSArray<ZDCSearchUserResult*>* results,  NSError *error))completionBlock
{
    void (^InvokeCompletionBlock)(NSArray <ZDCSearchUserResult*>*, NSError*) =
    ^(NSArray <ZDCSearchUserResult*>* results, NSError *error)
    {
        if (completionBlock)
        {
            dispatch_async(inCompletionQueue ?: dispatch_get_main_queue(), ^{ @autoreleasepool {
                completionBlock(results, error);
            }});
        }
    };
    
    if(providers.count > 1)
    {
        InvokeCompletionBlock(nil, [self errorWithDescription:@"Internal Error - Can only search one provider."]);
        return;
    }
    
  	[zdc.restManager searchUserMatch: queryString
	                        provider: providers.count ? providers.firstObject : nil
	                          zAppID: zdc.zAppID
	                     requesterID: userID
	                 completionQueue: dispatch_get_main_queue()
	                 completionBlock:^(NSURLResponse *response, id responseObject, NSError *error)
	{
		if (error != nil || responseObject == nil)
		{
			InvokeCompletionBlock(nil, error);
		}
		else
		{
			if ([responseObject isKindOfClass:[NSDictionary class]])
			{
				NSDictionary* dict = (NSDictionary*)responseObject;
				NSError* serverError = NULL;
                 
				NSArray<ZDCSearchUserResult*>* results =
					[self processSearchResults: dict
					               queryString: queryString
					           providerFilters: providers
					                     error: &serverError];
				
				if (!serverError)
				{
					[self cacheServerResults:results];
				}
				
				InvokeCompletionBlock(results, serverError);
				return;
			}
			
			InvokeCompletionBlock(nil, [self errorWithDescription:@"Server returned unexpected results"]);
		}
	}];
}

-(void)cacheServerResults:(NSArray<ZDCSearchUserResult*>*)results
{

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-retain-self"

    [databaseConnection readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        
        [results enumerateObjectsUsingBlock:^(ZDCSearchUserResult* result, NSUInteger idx, BOOL * _Nonnull stop) {
            
            NSString*  userID =  result.uuid;
            
            // Skip database users
            ZDCUser *user = [transaction objectForKey:userID inCollection:kZDCCollection_Users];
            
            if(!user)
            {
                ZDCSearchUserResult* cachedResult = result.copy;
                cachedResult.matches = nil;     // remove the matches - we recalulate these
                
                dispatch_async(cacheQueue, ^{
						 
                    [resultsCache setObject:cachedResult forKey:userID];
                });
                
            }
        }];
    }];
#pragma clang diagnostic pop

}


-(NSMutableArray <ZDCSearchUserResult*>*)  processSearchResults:(NSDictionary*) response
                     queryString:(NSString*)queryString
                 providerFilters:(NSArray <NSString*>*)providers
                           error:(NSError **)errorOut
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-retain-self"

	NSError             *error = NULL;
    NSMutableArray <ZDCSearchUserResult*>* searchResults = NULL;
    
    if([[response objectForKey:@"results"] isKindOfClass:[NSArray class]])
    {
        NSArray* items = (NSArray*)[response objectForKey:@"results"];
        
        if(items.count)
        {
             searchResults = [NSMutableArray arrayWithCapacity:items.count];
            
            [items enumerateObjectsUsingBlock:^(NSDictionary* item, NSUInteger idx, BOOL * _Nonnull stop) {
                
                NSDictionary* s4     = [item objectForKey:@"s4"];
                NSString* bucket     = [s4 objectForKey:@"bucket"];
                NSString* region     = [s4 objectForKey:@"region"];
                NSString* user_id     = [s4 objectForKey:@"user_id"];
                
                NSDictionary* auth0 = [item objectForKey:@"auth0"];
                NSArray* identities = [auth0 objectForKey:@"identities"];
                NSDictionary* user_metadata = [auth0 objectForKey:kZDCUser_metadataKey];
                
                NSDictionary* auth0_profiles = [zdc.localUserManager createProfilesFromIdentities:identities
                                                                                     region:[AWSRegions regionForName:region]
                                                                                     bucket:bucket];
                if(user_id
                   && bucket
                   && region
                   && auth0_profiles.count)
                {
                    ZDCSearchUserResult* result =  [[ZDCSearchUserResult alloc] init];
                    result.uuid = user_id;
                    result.aws_bucket = bucket;
                    result.aws_region = [AWSRegions regionForName:region];
                    result.auth0_profiles = auth0_profiles;
                    
                     if(user_metadata)
                     {
                         NSString* auth0_preferredID = [user_metadata objectForKey:kZDCUser_metadata_preferedAuth0ID];
                         if(auth0_preferredID.length)
                         {
                             result.auth0_preferredID = auth0_preferredID;
                         }
                     }
                    
                    if(auth0[@"updated_at"])
                    {
                        NSDate* date  = [NSDate dateFromRfc3339String:auth0[@"updated_at"]];
                        if(date)
                        {
                            result.auth0_lastUpdated = date;
                        }
                    }
                    
                    if(!result.auth0_lastUpdated)
                        result.auth0_lastUpdated = NSDate.distantPast;
                    
                    
                    NSArray<ZDCSearchUserMatching*>* matches = [self createMatchingFromProfiles:auth0_profiles
                                                                                    queryString:queryString];
                    if(matches.count)
                    {
                        result.matches = matches;
                        [searchResults addObject:result];
                    }
                    
                }
            }];
            
        }
    }
    else
    {
        error = [self errorWithDescription:@"Server returned unexpected results"];
    }
    
    if(errorOut)
        *errorOut = error;
    
    return searchResults;
#pragma clang diagnostic pop

}


#pragma mark - Public API

- (void)queryForUsersWithString:(NSString *)queryString
                      forUserID:(NSString *)userID
                providerFilters:(NSArray <NSString*>*)providers
                localSearchOnly:(BOOL)localSearchOnly
                completionQueue:(dispatch_queue_t)inCompletionQueue
                   resultsBlock:(void (^)(ZDCSearchUserManagerResultStage stage, NSArray<ZDCSearchUserResult*>* results,  NSError *error))inResultsBlock
{
    ZDCLogAutoTrace();
    
    if (!inResultsBlock)
        return;
    
    if (!inCompletionQueue)
        inCompletionQueue = dispatch_get_main_queue();
    
    
    void (^foundResultsBlock)(ZDCSearchUserManagerResultStage,NSArray <ZDCSearchUserResult*>*, NSError*)
    = ^(ZDCSearchUserManagerResultStage stage, NSArray <ZDCSearchUserResult*>* results,  NSError *searchError) {
        
        if(inResultsBlock)
            dispatch_async(inCompletionQueue, ^{ @autoreleasepool {
                inResultsBlock(stage, results, searchError );
            }});
        
    };
    
    NSMutableDictionary* updatedUserIDs = NSMutableDictionary.dictionary; // userID is key / NSDate of auth0 update is value
    
    __block NSMutableArray<ZDCSearchUserResult*>* searchResults = NSMutableArray.array;
    
#if DEBUGGING_SEARCH_SERVER
#else
    /* Search the local Database */
    __block NSArray<ZDCSearchUserResult*>* databaseResults = nil;

    [databaseConnection readWithBlock:^(YapDatabaseReadTransaction * _Nonnull transaction) {
        databaseResults = [self searchDatabaseForQuery:queryString
                                       providerFilters:providers
                                       withTransaction:transaction];
    }];

    if(databaseResults.count)
    {
        [databaseResults enumerateObjectsUsingBlock:^(ZDCSearchUserResult* result, NSUInteger idx, BOOL * _Nonnull stop) {
            
            NSString*  userID = result.uuid;
            NSDate*   auth0_lastUpdated = result.auth0_lastUpdated;
            NSDate*   lastDate = [updatedUserIDs objectForKey:userID];
            
            if(!lastDate || [lastDate isBefore:auth0_lastUpdated])
            {
                [searchResults addObject:result];
                [updatedUserIDs setObject:auth0_lastUpdated?auth0_lastUpdated:NSDate.distantPast
                                   forKey:userID];
            }
        }];

        foundResultsBlock(ZDCSearchUserManagerResultStage_Database, searchResults.copy, nil);
        [searchResults removeAllObjects];
        databaseResults = nil;
    }
#endif

#if DEBUGGING_SEARCH_SERVER
#else
    /* search the cache */
    __block NSArray<ZDCSearchUserResult*>* cacheResults = nil;

    cacheResults = [self searchCacheForQuery:queryString
                             providerFilters:providers];

    if(cacheResults.count)
    {
        [cacheResults enumerateObjectsUsingBlock:^(ZDCSearchUserResult* result, NSUInteger idx, BOOL * _Nonnull stop) {

            NSString*  userID = result.uuid;
            NSDate*   auth0_lastUpdated = result.auth0_lastUpdated;
            NSDate*   lastDate = [updatedUserIDs objectForKey:userID];
            
            if(!lastDate || [lastDate isBefore:auth0_lastUpdated])
            {
                [searchResults addObject:result];
                
                [updatedUserIDs setObject:auth0_lastUpdated?auth0_lastUpdated:NSDate.distantPast
                                   forKey:userID];
            }


        }];

        foundResultsBlock(ZDCSearchUserManagerResultStage_Cache, searchResults.copy, nil);
        [searchResults removeAllObjects];
        cacheResults = nil;
    }
#endif
    
    /* search the Server */
    if(!localSearchOnly)
    {
        [self searchServerForQuery:queryString
                         forUserID:userID
                   providerFilters:providers
                   completionQueue:inCompletionQueue
                   completionBlock:^(NSArray<ZDCSearchUserResult*> *serverResults, NSError *error) {
                       
                       if(error)
                       {
                           foundResultsBlock(ZDCSearchUserManagerResultStage_Server, nil, error);
                       }
                       else if(serverResults.count)
                       {
                           [serverResults enumerateObjectsUsingBlock:^(ZDCSearchUserResult* result, NSUInteger idx, BOOL * _Nonnull stop) {
                               
                               NSString*  userID = result.uuid;
                               NSDate*   auth0_lastUpdated = result.auth0_lastUpdated;
                               NSDate*   lastDate = [updatedUserIDs objectForKey:userID];
                               
                               if(!lastDate || [lastDate isBefore:auth0_lastUpdated])
                               {
                                  [searchResults addObject:result];
                                   
                                   [updatedUserIDs setObject:auth0_lastUpdated?auth0_lastUpdated:NSDate.distantPast
                                                      forKey:userID];
                               }
                               
                           }];
                           
                           foundResultsBlock(ZDCSearchUserManagerResultStage_Server, searchResults.copy, nil);
                       }
                       
                       // call this when server search is done
                       
                       foundResultsBlock(ZDCSearchUserManagerResultStage_Done, nil, nil);
                       
                   }];
    }
    
}
@end
