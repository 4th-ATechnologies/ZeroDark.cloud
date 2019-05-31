/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import "ZDCShareItem.h"

@interface ZDCShareItem ()

/**
 * Extracts the keyID property from the key (if possible).
 *
 * Here's the deal:
 * - The `-key` is actually a base64-encoded JSON blob
 * - So you can base64-decode it, and get a dictionary
 * - The dictionary has a bunch of stuff required  by the underlying crypto.
 *   (For example, we may want to upgrade the encryption algorithms at a future date.
 *    So one of the things we do is encode the encryption algorithms within the JSON.)
 * - This method extracts the keyID from the JSON blob.
 */
@property (nonatomic, readonly, nullable) NSString *pubKeyID;

@end
