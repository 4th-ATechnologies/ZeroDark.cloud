/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/


#import <Foundation/Foundation.h>
#import "ZDCLocalPreferences.h"
#import "ZeroDarkCloud.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ZDCprefs_recentRecipients;
extern NSString *const ZDCprefs_preferedAuth0IDs;

@interface ZDCInternalPreferences : ZDCLocalPreferences

- (instancetype)initWithOwner:(ZeroDarkCloud *)owner;

@property (atomic) NSDate *lastProviderTableUpdate;

//TODO: we probably have to move recentRecipients to shared prefs

// this keeps N of the most recent shared Ids
@property (atomic, nullable) NSArray<NSArray *> *recentRecipients;
- (void)setRecentRecipient:(NSString *)recipientID auth0ID:(NSString * __nullable)auth0ID;
- (void)removeRecentRecipient:(NSString *)recipientID;

// this keeps a map of prefered Auth0/SocialIDs for userIDS
@property (atomic, nullable, readonly) NSDictionary<NSString *,NSString *> * preferedAuth0IDs;
- (void)setPreferedAuth0ID:(NSString *__nullable )auth0ID userID:(NSString *)userID;


// the last type of activity the user asked to look at
@property (atomic) NSInteger  activityMonitor_lastActivityType;


@end

NS_ASSUME_NONNULL_END
