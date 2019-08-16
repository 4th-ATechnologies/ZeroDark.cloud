/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCLocalUser.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZDCLocalUser ()

/**
 * The pushToken that's in effect for the user.
 * If the OS gives us a different pushToken then we know we have to re-register using the new pushToken.
 *
 * @note All pushToken related values auto-swap for debug/release builds.
 *       That is, the code knows you may receive different push tokens from the OS
 *       based on whether you compiled in DEBUG vs RELEASE mode.
 *       So, internally, it uses different stored values based on how it was compiled.
 *       This prevents constantly re-registering push tokens when
 *       switching back and forth between build types.
 */
@property (nonatomic, copy, readwrite, nullable) NSString *pushToken;

/**
 * Date in which the pushToken was registered for the user.
 *
 * @note All pushToken related values auto-swap for debug/release builds.
 *       For more information, see the notes in `-pushToken`.
 */
@property (nonatomic, strong, readwrite) NSDate *lastPushTokenRegistration;


/**
 * Set this flag to YES to trigger a pushToken registration with the server.
 * This gets handled automatically via YapDatabaseActionManager extension.
 * (For implementation, see [ZDCDatabaseManager actionManagerScheduler]).
 *
 * @note All pushToken related values auto-swap for debug/release builds.
 *       For more information, see the notes in `-pushToken`.
 */
@property (nonatomic, assign, readwrite) BOOL needsRegisterPushToken;

/**
 * Set this flag to YES to trigger the the corresponding REST API call with the server.
 *
 * This gets handled automatically via YapDatabaseActionManager extension.
 * (For implementation, see [ZDCDatabaseManager actionManagerScheduler]).
 */
@property (nonatomic, assign, readwrite) BOOL needsCreateRecoveryConnection;

/**
 * Indicates whether the localUser profile has a recovery connection.
 */
@property (nonatomic, readonly) BOOL hasRecoveryConnection;

@property (nonatomic, assign, readwrite) BOOL needsCheckAccountDeleted;
@property (nonatomic, assign, readwrite) BOOL needsUserMetadataUpload;

@end

NS_ASSUME_NONNULL_END
