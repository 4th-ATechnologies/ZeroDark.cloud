/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/


#import <Foundation/Foundation.h>
#import "ZDCLocalPreferences.h"
#import "ZeroDarkCloud.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDCInternalPreferences : ZDCLocalPreferences

- (instancetype)initWithOwner:(ZeroDarkCloud *)owner;

/**
 * Used by the activity monitor.
 * Keeps track of the last selected type: uploads, downloads, both, raw
 */
@property (atomic) NSInteger activityMonitor_lastActivityType;

/**
 * What is this ?
 */
@property (atomic) NSDate *lastProviderTableUpdate;

/**
 * Keeps track of the most recenlty selected userID's
 */
@property (atomic, nullable) NSArray<NSString *> *recentRecipients;

- (void)addRecentRecipient:(NSString *)userID;
- (void)removeRecentRecipient:(NSString *)userID;

// this keeps a map of prefered Auth0/SocialIDs for userIDS
@property (atomic, nullable, readonly) NSDictionary<NSString *,NSString *> * preferedAuth0IDs;
- (void)setPreferedAuth0ID:(NSString *__nullable )auth0ID userID:(NSString *)userID;

@end

NS_ASSUME_NONNULL_END
