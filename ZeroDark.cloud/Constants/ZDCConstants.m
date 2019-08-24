/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCConstants.h"

// YapDatabase collection constants

/* extern */ NSString *const kZDCCollection_CachedResponse  = @"ZDCCachedResponse";
/* extern */ NSString *const kZDCCollection_CloudNodes      = @"ZDCCloudNodes";
/* extern */ NSString *const kZDCCollection_Nodes           = @"ZDCNodes";
/* extern */ NSString *const kZDCCollection_Prefs           = @"ZDCPrefs";
/* extern */ NSString *const kZDCCollection_PublicKeys      = @"ZDCPublicKeys";
/* extern */ NSString *const kZDCCollection_PullState       = @"ZDCSyncState";
/* extern */ NSString *const kZDCCollection_Reminders       = @"ZDCReminders";
/* extern */ NSString *const kZDCCollection_SessionStorage  = @"ZDCSessionStorage";
/* extern */ NSString *const kZDCCollection_SymmetricKeys   = @"ZDCSymmetricKeys";
/* extern */ NSString *const kZDCCollection_Tasks           = @"ZDCTasks";
/* extern */ NSString *const kZDCCollection_Users           = @"ZDCUsers";
/* extern */ NSString *const kZDCCollection_UserAuth        = @"ZDCUserAuth";
/* extern */ NSString *const kZDCCollection_SplitKeys       = @"ZDCSplitKeys";
/* extern */ NSString *const kZDCCollection_SplitKeyShares  = @"ZDCSplitKeyShare";

// Names of special cloud files & file extensions

/* extern */ NSString *const kZDCCloudFileName_PrivateKey = @".privKey";
/* extern */ NSString *const kZDCCloudFileName_PublicKey  = @".pubKey";

/* extern */ NSString *const kZDCCloudFileExtension_Rcrd  = @"rcrd";
/* extern */ NSString *const kZDCCloudFileExtension_Data  = @"data";

// Names of special local files & file extensions

/* extern */ NSString *const kZDCDirPrefix_Home    = @"00000000000000000000000000000000";
/* extern */ NSString *const kZDCDirPrefix_Prefs   = @"prefs";
/* extern */ NSString *const kZDCDirPrefix_MsgsIn  = @"msgsIn";
/* extern */ NSString *const kZDCDirPrefix_MsgsOut = @"msgsOut";
/* extern */ NSString *const kZDCDirPrefix_Avatar  = @"avatar";

/* extern */ NSString *const kZDCDirPrefix_Deprecated_Msgs   = @"msgs";
/* extern */ NSString *const kZDCDirPrefix_Deprecated_Inbox  = @"inbox";
/* extern */ NSString *const kZDCDirPrefix_Deprecated_Outbox = @"outbox";

// Dictionary keys used in .rcrd files

/* extern */ NSString *const kZDCCloudRcrd_Version  = @"version";
/* extern */ NSString *const kZDCCloudRcrd_FileID   = @"fileID";
/* extern */ NSString *const kZDCCloudRcrd_Sender   = @"sender";
/* extern */ NSString *const kZDCCloudRcrd_Keys     = @"keys";
/* extern */ NSString *const kZDCCloudRcrd_Children = @"children";
/* extern */ NSString *const kZDCCloudRcrd_Meta     = @"metadata";
/* extern */ NSString *const kZDCCloudRcrd_Data     = @"data";
/* extern */ NSString *const kZDCCloudRcrd_BurnDate = @"burnDate";

/* extern */ NSString *const kZDCCloudRcrd_Keys_Perms               = @"perms";
/* extern */ NSString *const kZDCCloudRcrd_Keys_Burn                = @"burn";
/* extern */ NSString *const kZDCCloudRcrd_Keys_Key                 = @"key";

/* extern */ NSString *const kZDCCloudRcrd_Keys_Deprecated_Perms    = @"Share";
/* extern */ NSString *const kZDCCloudRcrd_Keys_Deprecated_Burn     = @"BurnDate";
/* extern */ NSString *const kZDCCloudRcrd_Keys_Deprecated_PubKeyID = @"pubKeyID";
/* extern */ NSString *const kZDCCloudRcrd_Keys_Deprecated_SymKey   = @"symKey";

/* extern */ NSString *const kZDCCloudRcrd_Children_Prefix = @"prefix";

/* extern */ NSString *const kZDCCloudRcrd_Meta_Filename       = @"filename";
/* extern */ NSString *const kZDCCloudRcrd_Meta_DirSalt        = @"dirSalt";

/* extern */ NSString *const kZDCCloudRcrd_Data_Pointer        = @"pointer";

/* extern */ NSString *const kZDCCloudRcrd_Data_Pointer_Owner   = @"owner";
/* extern */ NSString *const kZDCCloudRcrd_Data_Pointer_Path    = @"path";
/* extern */ NSString *const kZDCCloudRcrd_Data_Pointer_CloudID = @"cloudID";

// Dictionary keys used in .pubKey/.privKey files

NSString *const kZDCCloudRcrd_UserID  = @"userID";
NSString *const kZDCCloudRcrd_Auth0ID = @"auth0ID";

// Auth0 API

//4th-A App ID
NSString *const kAuth04thA_AppClientID   		= @"iLjaFx3CHIyzaXYjrundOOzmYIvS1nbu";
NSString *const kAuth04thADomain     		    = @"4th-a.auth0.com";

// Auth0 Database acccount

NSString *const kAuth04thAUserDomain          = @"users.4th-a.com";
NSString *const kAuth04thARecoveryDomain      = @"recovery.4th-a.com";

NSString *const kAuth0DBConnection_UserAuth   = @"Username-Password-Authentication";
NSString *const kAuth0DBConnection_Recovery   = @"Storm4-Recovery";


// ZDC activation code file extension
NSString *const kZDCFileExtension_ActivationCode = @"zdcactivationcode";
