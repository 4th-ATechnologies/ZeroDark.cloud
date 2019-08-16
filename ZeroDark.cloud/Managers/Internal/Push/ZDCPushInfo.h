/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <Foundation/Foundation.h>

#import "ZDCChangeItem.h"
@class ZDCRequestInfo;

NS_ASSUME_NONNULL_BEGIN

/**
 * Used for parsing the received dictionary from a remote push notification.
 */
@interface ZDCPushInfo : NSObject

/**
 * Attempts to parse the given dictionary.
 * Returns nil if the dictionary doesn't appear to originate from the ZeroDark.cloud servers.
 */
+ (nullable ZDCPushInfo *)parsePushInfo:(NSDictionary *)pushDict;

/**
 * The intended recipient of the push notification.
 */
@property (nonatomic, readonly, nullable) NSString *localUserID;

@property (nonatomic, readonly, nullable) NSString *changeID_new;
@property (nonatomic, readonly, nullable) NSString *changeID_old;

@property (nonatomic, readonly, nullable) ZDCChangeItem *changeInfo;
@property (nonatomic, readonly, nullable) ZDCRequestInfo *requestInfo;

@property (nonatomic, readonly) BOOL isActivation;

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * This may be included within a remote push notification IFF
 * the recipient is the one who initiated the request.
 *
 * That is:
 * - we're receiving a push notification because something changed in the cloud
 * - who initiated the change ?
 * - if it was Alice, and the push notification is for Alice, then it will contain the request info
 * - the request info is the same thing Alice gets when she polls the server for the response to her request
 * - the request info thus allows us to short-circuit Alice's polling mechanism
 */
@interface ZDCRequestInfo : NSObject

@property (nonatomic, readonly, nullable) NSString *requestID;
@property (nonatomic, readonly, nullable) NSString *localUserID;

@property (nonatomic, readonly, nullable) NSDictionary *status;
@property (nonatomic, readonly) NSInteger statusCode;

@end

NS_ASSUME_NONNULL_END
