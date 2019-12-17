/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>

#import "AWSRegions.h"
#import "ZDCUser.h"

@class ZDCSearchOptions;
@class ZDCSearchResult;
@class ZDCSearchMatch;

NS_ASSUME_NONNULL_BEGIN

/**
 * When you perform a search, the framework actually searches 3 different sources:
 * - the local database (for ZDCUser's & ZDCLocalUser's)
 * - the local cache (from previous queries to the server)
 * - the remote server
 *
 * The matches from each of these sources will be returned to you independently.
 * This gives you the option of populating the UI immediately (with local matches),
 * rather than waiting for a round-trip to the server.
 *
 * @note The order of the stages is not guaranteed. You may receive results from stages in any order.
 */
typedef NS_ENUM(NSInteger, ZDCSearchResultStage) {
	ZDCSearchResultStage_Database,
	ZDCSearchResultStage_Cache,
	ZDCSearchResultStage_Server,
	ZDCSearchResultStage_Done,
};

/**
 * The SearchManager allows you to search for other users within the system.
 *
 * Recall that user's are allows to link multiple identities to their account.
 * For example, a user may choose to link all of the following:
 * - Facebook
 * - LinkedIn
 * - GitHub
 *
 * This makes searching much easier for the user.
 * They can search for friends & colleagus using the social connections in which they already interact.
 * And the search API allows them to limit their search to particular networks (e.g. only seach GitHub).
 */
@interface ZDCUserSearchManager : NSObject

/**
 * Searches for co-op users who have linked identities which match a given query.
 *
 * @param queryString
 *   The search query the user typed into the search field.
 * @param treeID
 *   The treeID to search.
 *   Only co-op users who have signed into this app will be included in the search results.
 * @param localUserID
 *   The localUser to use when sending the request to the server.
 *   The localUserID must be valid, and must be a co-op user.
 * @param options
 *   Allows you optionally specify advanced search options.
 * @param completionQueue
 *   The queue on which to invoke the resultsBlock.
 *   If you specify nil, the main thread will be used.
 * @param resultsBlock
 *   This closure will be invoked multiple times — once for each ZDCSearchResultStage.
 *   When the search has completed, this closure will be invoked one last time with ZDCSearchResultStage_Done.
 */
- (void)searchForUsersWithQuery:(NSString *)queryString
                         treeID:(NSString *)treeID
                    requesterID:(NSString *)localUserID
                        options:(nullable ZDCSearchOptions *)options
                completionQueue:(nullable dispatch_queue_t)completionQueue
                   resultsBlock:(void (^)(ZDCSearchResultStage stage,
                                          NSArray<ZDCSearchResult*> *_Nullable results,
                                          NSError *_Nullable error))resultsBlock;

/**
 * Allows you to clear the search cache.
 * The search cache includes results from previous queries.
 */
- (void)flushCache;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@interface ZDCSearchOptions: NSObject <NSCopying>

/**
 * The default value is "*", which searches all providers.
 */
@property (nonatomic, copy, readwrite) NSString *providerToSearch;

/**
 * Whether or not to search the local database.
 * When this is enabled, it allows results to be quickly returned via the resultsBlock.
 *
 * The default value is YES.
 */
@property (nonatomic, assign, readwrite) BOOL searchLocalDatabase;

/**
 * Whether or not to search the local cache (from previous search queries).
 * When this is enabled, it allows results to be quickly returned via the resultsBlock.
 *
 * The default value is YES.
 */
@property (nonatomic, assign, readwrite) BOOL searchLocalCache;

/**
 * Whether or not to send the search query to the server.
 * You can optionally disable this if you want to perform a local-only search.
 *
 * The default value is YES.
 */
@property (nonatomic, assign, readwrite) BOOL searchRemoteServer;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * A search result represents a particular user, along with their basic cloud information & linked identities.
 */
@interface ZDCSearchResult : NSObject <NSCopying>

/** The user's ID (a 32 character string) */
@property (nonatomic, readonly) NSString *userID;

/** The AWS region where the user's bucket resides. */
@property (nonatomic, readonly) AWSRegion aws_region;

/** The name of the user's S3 bucket. */
@property (nonatomic, readonly) NSString * aws_bucket;

/** The list of linked social identities for the user's account. */
@property (nonatomic, readonly) NSArray<ZDCUserIdentity*> *identities;

/** Detailed information concerning how this user matched the query. */
@property (nonatomic, readonly) NSArray<ZDCSearchMatch*> *matches;

/** The preferredIdentityID controls how the system prefers to display the user within the UI. */
@property (nonatomic, copy, readwrite) NSString *preferredIdentityID;

/**
 * Extracts an identity for the user from their list of linked identities.
 * The preferredIdentity is used, if configured.
 * Otherwise, an identity is selected from the list of identities.
 */
@property (nonatomic, readonly) ZDCUserIdentity *displayIdentity;

/**
 * Returns the identity with the given ID, if it exists.
 */
- (nullable ZDCUserIdentity *)identityWithID:(NSString *)identityID;

/**
 * create a ZDCSearchResult from an existing ZDCUser
 */
- (instancetype)initWithUser:(ZDCUser *)user;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Provides detailed information concerning which identities matched the search,
 * and where the match occurred. A UI may use this information to highlight the match sequence.
 */
@interface ZDCSearchMatch : NSObject <NSCopying>

/** A reference to the corresponding ZDCUserIdentity. */
@property (nonatomic, copy, readonly) NSString * identityID;

/** The string that matched the user's query. */
@property (nonatomic, copy, readonly) NSString * matchingString;

/** An array of NSRange values (wrapped in NSValue). */
@property (nonatomic, copy, readonly) NSArray<NSValue*> * matchingRanges;

@end

NS_ASSUME_NONNULL_END
