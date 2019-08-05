/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import <Foundation/Foundation.h>

#import "ZDCCloudPath.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * This class represents the decrypted information within a RCRD file.
 *
 * Every node that gets stored in the cloud gets split into 2 files:
 * - the RCRD file contains the filesystem metadata (name of file, permissions, etc)
 * - the DATA file contains the actual content of the node
 *
 * ZeroDark.cloud downloads RCRD files automatically (which are small),
 * in order to keep the local treesystem up-to-date with the cloud.
 * Note, however, that it does NOT automatically download DATA files.
 * Your application gets to decide which DATA files to download & when.
 */
@interface ZDCCloudRcrd : NSObject

/**
 * Every RCRD has a version number.
 * This relates to the version of the RCRD structure itself (so it's NOT related to syncing).
 */
@property (nonatomic, assign, readwrite) NSUInteger version;

/**
 * Every RCRD has a cloudID, which is assigned by the server (it's a UUID).
 * The cloudID is immutable — it cannot be changed.
 * In other words:
 *
 * Say a RCRD exists on the server with cloudPath `P`.
 * Attempting to overwrite the RCRD at P with a new RCRD is only allowed
 * if the newRcrd.cloudID matches oldRcrd.cloudID.
 * If the cloudID's don't match, the server requires the oldRCRD to either be deleted or moved first.
 *
 * CloudID's are used to uniquely track a particular item in the cloud.
 * This allows the object to be moved or renamed on the server,
 * while still maintaining a reference to previous versions that may exists on various clients.
 */
@property (nonatomic, copy, readwrite, nullable) NSString *cloudID;

/**
 * If the RCRD was written by a different user (i.e. not the owner of the bucket),
 * the server will automatically set the `sender` property to
 * the userID of the user who PUT the item into the bucket.
 *
 * This is primarily used in messaging,
 * where the sender of the file is important,
 * and we need to be able to protect against spoofing.
 */
@property (nonatomic, copy, readwrite, nullable) NSString *sender;

/**
 * The symmetric key that is used for:
 * - the metadata and/or data section of the RCRD
 * - the DATA fork (if there is one)
 *
 * This value was decrypted using the localUser's private key.
 */
@property (nonatomic, copy, readwrite, nullable) NSData *encryptionKey;

/**
 * The RAW children dictionary.
 * 
 * This structure is scheduled to change in the next version of the RCRD structure.
 * It's recommended you use the `dirPrefix` method for now.
 */
@property (nonatomic, copy, readwrite, nullable) NSDictionary *children;

/**
 * The RAW share dictionary.
 * Use ZDCShareList to parse it.
 */
@property (nonatomic, copy, readwrite, nullable) NSDictionary *share;

/**
 * Optional burn date.
 * If set, the server will automatically delete the item at approximately this time.
 */
@property (nonatomic, copy, readwrite, nullable) NSDate *burnDate;

/**
 * Every RCRD must have either a metadata || data section.
 * If it has a data section, the RCRD is not allowed to have an accompanying DATA fork.
 */
@property (nonatomic, copy, readwrite, nullable) NSDictionary *metadata;

/**
 * Every RCRD must have either a metadata || data section.
 * If it has a data section, the RCRD is not allowed to have an accompanying DATA fork.
 */
@property (nonatomic, copy, readwrite, nullable) NSDictionary *data;

#pragma mark Parsing Children

/**
 * Standard nodes just have a single "container".
 *
 * However, advanced configurations are possible.
 * For example, when using group conversations.
 */
- (BOOL)usingAdvancedChildrenContainer;

/**
 * Enumerates the children containers.
 */
- (void)enumerateChildrenWithBlock:(void (^)(NSString *name, NSString *dirPrefix, BOOL *stop))block;

/**
 * Extracts the standard dirPrefix from the `children` dictionary.
 */
- (nullable NSString *)dirPrefix;

#pragma mark Parsing Data

/**
 * Returns YES if the data component contains valid pointer info.
 */
- (BOOL)isPointer;

/**
 * Extracts pointer information from the data component.
 */
- (BOOL)getPointerCloudPath:(ZDCCloudPath *_Nullable *_Nullable)outPath
                    cloudID:(NSString *_Nullable *_Nullable)outCloudID
                    ownerID:(NSString *_Nullable *_Nullable)outOwnerID;

@end

NS_ASSUME_NONNULL_END
