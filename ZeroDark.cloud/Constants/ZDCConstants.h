/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import <Foundation/Foundation.h>

/**
 * The block size used for encryption/decryption.
 * The TBC tweak is manually changed every so many bytes.
 */
#define kZDCNode_TweakBlockSizeInBytes 1024

/**
 * The "dirSalt" is used when hashing file names.
 * This prevents leaking file names. (i.e. well known filename, with known hash)
 */
#define kZDCNode_DirSaltKeySizeInBytes (160 / 8) // bits / 8 = bytes

/**
 * Size of S4Node.encryptionKey
 */
#define kZDCNode_EncryptionKeySizeInBytes (512 / 8) // bits / 8 = bytes

/**
 * Magic bytes (file data prefix)
 */
#define kZDCFileCloudContextMagic 0x286F202928206F29

/**
 * The primary AWS region, used for:
 * - account activation
 * - account configuration
 * - billing
 * - payment
 * - and other activities that are restricted to a single region
 */
#define AWSRegion_Master AWSRegion_US_West_2

NS_ASSUME_NONNULL_BEGIN

//
// YapDatabase collection constants
//

/** Name of collection in YapDatabase. All ZeroDark collection constants start with "ZDC" */
extern NSString *const kZDCCollection_CachedResponse;
/** Name of collection in YapDatabase. All ZeroDark collection constants start with "ZDC" */
extern NSString *const kZDCCollection_CloudNodes;
/** Name of collection in YapDatabase. All ZeroDark collection constants start with "ZDC" */
extern NSString *const kZDCCollection_Messages;
/** Name of collection in YapDatabase. All ZeroDark collection constants start with "ZDC" */
extern NSString *const kZDCCollection_Nodes;
/** Name of collection in YapDatabase. All ZeroDark collection constants start with "ZDC" */
extern NSString *const kZDCCollection_Prefs;
/** Name of collection in YapDatabase. All ZeroDark collection constants start with "ZDC" */
extern NSString *const kZDCCollection_PublicKeys;
/** Name of collection in YapDatabase. All ZeroDark collection constants start with "ZDC" */
extern NSString *const kZDCCollection_PullState;
/** Name of collection in YapDatabase. All ZeroDark collection constants start with "ZDC" */
extern NSString *const kZDCCollection_Reminders;
/** Name of collection in YapDatabase. All ZeroDark collection constants start with "ZDC" */
extern NSString *const kZDCCollection_SessionStorage;
/** Name of collection in YapDatabase. All ZeroDark collection constants start with "ZDC" */
extern NSString *const kZDCCollection_SymmetricKeys;
/** Name of collection in YapDatabase. All ZeroDark collection constants start with "ZDC" */
extern NSString *const kZDCCollection_Tasks;
/** Name of collection in YapDatabase. All ZeroDark collection constants start with "ZDC" */
extern NSString *const kZDCCollection_Users;
/** Name of collection in YapDatabase. All ZeroDark collection constants start with "ZDC" */
extern NSString *const kZDCCollection_UserAuth;
/** Name of collection in YapDatabase. All ZeroDark collection constants start with "ZDC" */
extern NSString *const kZDCCollection_SplitKeys;
/** Name of collection in YapDatabase. All ZeroDark collection constants start with "ZDC" */
extern NSString *const kZDCCollection_SplitKeyShares;

//
// Cloud Filenames
//

/**
 * Every account has a ".pubKey" file.
 * This file is accessible to the world, and is stored using a JSON format.
 * The file contains the public key information for the user.
 */
extern NSString *const kZDCCloudFileName_PublicKey;

/**
 * Every account has a ".privKey" file.
 * This file is only readable by the user who owns it.
 * The file contains a PBKDF2 encrypted version of the private key.
 * It can only be read if you have the access key (which only the user has access to).
 */
extern NSString *const kZDCCloudFileName_PrivateKey; // PBKDF2 encrypted, requires access key to unlock

//
// Cloud File Extensions
//

/**
 * The RCRD file contains ONLY the filesystem metadata.
 * That is:
 * - the (encrypted) filename
 * - the list of permissions
 * - the (encrypted) file encryption key
 * - other bookkeeping information used by the sync system such as the server-assigned cloudID
 */
extern NSString *const kZDCCloudFileExtension_Rcrd;

/**
 * The DATA file contains the (encrypted) content of the node.
 * The DATA file is always in ZDCCryptoFileFormat_CloudFile.
 *
 * A DATA file requires a corresponding RCRD file to accompany it on the server.
 * The DATA file can only be decrypted using the corresponding file encryption key.
 */
extern NSString *const kZDCCloudFileExtension_Data;

//
// Names of special files, paths
//

extern NSString *const kZDCDirPrefix_Home;
extern NSString *const kZDCDirPrefix_Msgs;
extern NSString *const kZDCDirPrefix_Prefs;
extern NSString *const kZDCDirPrefix_Inbox;
extern NSString *const kZDCDirPrefix_Outbox;
extern NSString *const kZDCDirPrefix_Avatar;

extern NSString *const kAttachmentParentIDPrefix;

NSString* AttachmentParentID(NSString *localUserID);

// Dictionary keys within .rcrd files

extern NSString *const kZDCCloudRcrd_Version;
extern NSString *const kZDCCloudRcrd_FileID;
extern NSString *const kZDCCloudRcrd_Sender;
extern NSString *const kZDCCloudRcrd_Keys;
extern NSString *const kZDCCloudRcrd_Children;
extern NSString *const kZDCCloudRcrd_Meta;
extern NSString *const kZDCCloudRcrd_Data;
extern NSString *const kZDCCloudRcrd_BurnDate;

extern NSString *const kZDCCloudRcrd_Keys_Perms;
extern NSString *const kZDCCloudRcrd_Keys_Burn;
extern NSString *const kZDCCloudRcrd_Keys_Key;

extern NSString *const kZDCCloudRcrd_Keys_Deprecated_Perms;
extern NSString *const kZDCCloudRcrd_Keys_Deprecated_Burn;
extern NSString *const kZDCCloudRcrd_Keys_Deprecated_PubKeyID;
extern NSString *const kZDCCloudRcrd_Keys_Deprecated_SymKey;

extern NSString *const kZDCCloudRcrd_Children_Prefix;

extern NSString *const kZDCCloudRcrd_Meta_Type;
extern NSString *const kZDCCloudRcrd_Meta_Filename;
extern NSString *const kZDCCloudRcrd_Meta_DirSalt; // if (type == "directory")
extern NSString *const kZDCCloudRcrd_Meta_OwnerID; // if (type == "share")
extern NSString *const kZDCCloudRcrd_Meta_Path;    // if (type == "share")
extern NSString *const kZDCCloudRcrd_Meta_FileID;  // if (type == "share")

extern NSString *const kZDCCloudRcrd_Meta_Type_Directory;
extern NSString *const kZDCCloudRcrd_Meta_Type_Share;

extern NSString *const kZDCCloudRcrd_Data_Key;
extern NSString *const kZDCCloudRcrd_Data_Value;

// Dictionary keys used in .pubKey/.privKey files

extern NSString *const kZDCCloudRcrd_UserID;
extern NSString *const kZDCCloudRcrd_Auth0ID;

// Auth0 API

extern NSString *const kAuth04thA_AppClientID;
extern NSString *const kAuth04thADomain;

// Auth0 Database acccount

extern NSString *const kAuth04thAUserDomain;
extern NSString *const kAuth04thARecoveryDomain;

extern NSString *const kAuth0DBConnection_UserAuth;
extern NSString *const kAuth0DBConnection_Recovery;

// Auth0 Error codes

extern NSString *const kAuth0Error_RateLimit;
extern NSString *const kAuth0Error_Unauthorized;
extern NSString *const kAuth0Error_InvalidRefreshToken;
extern NSString *const kAuth0Error_InvalidGrant;
extern NSString *const kAuth0Error_UserExists;
extern NSString *const kAuth0Error_UserNameExists;

extern NSString *const kAuth0ErrorDescription_Blocked; // extra qualifier for unauthorized

// ZDC activation code file extension
extern NSString *const kZDCFileExtension_ActivationCode;


@interface ZDCConstants : NSObject

@end

NS_ASSUME_NONNULL_END
