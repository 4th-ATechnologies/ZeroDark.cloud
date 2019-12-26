/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCCryptoTools.h"

#import "ZDCConstantsPrivate.h"
#import "ZDCNodePrivate.h"
#import "ZeroDarkCloudPrivate.h"

// Categories
#import "NSData+ZeroDark.h"
#import "NSError+S4.h"
#import "NSError+ZeroDark.h"
#import "NSMutableDictionary+ZeroDark.h"
#import "NSString+ZeroDark.h"

/**
 * Current version of JSON file, as supported by this framework.
 */
static NSUInteger const kZDCCloudRcrdCurrentVersion = 3;


@interface ZDCMissingInfo ()

- (void)addMissingKey:(NSString *)key;
- (void)addMissingUserID:(NSString *)userID;
- (void)addMissingUserPubKey:(ZDCUser *)user;
- (void)addMissingServerID:(NSString *)serverID;

@end

@implementation ZDCMissingInfo {

	NSMutableArray<NSString*> *_missingKeys;
	
	NSMutableArray<NSString*> *_missingUserIDs;
	NSMutableArray<ZDCUser*> *_missingUserPubKeys;
	
	NSMutableArray<NSString*> *_missingServerIDs;
}

@synthesize missingKeys = _missingKeys;

@synthesize missingUserIDs = _missingUserIDs;
@synthesize missingUserPubKeys = _missingUserPubKeys;

@synthesize missingServerIDs = _missingServerIDs;

- (instancetype)init
{
	if ((self = [super init]))
	{
		_missingKeys = [[NSMutableArray alloc] initWithCapacity:1];
		
		_missingUserIDs = [[NSMutableArray alloc] initWithCapacity:1];
		_missingUserPubKeys = [[NSMutableArray alloc] initWithCapacity:1];
		
		_missingServerIDs = [[NSMutableArray alloc] initWithCapacity:1];
	}
	return self;
}

- (void)addMissingKey:(NSString *)key {
	[_missingKeys addObject:key];
}

- (void)addMissingUserID:(NSString *)userID {
	[_missingUserIDs addObject:userID];
}

- (void)addMissingUserPubKey:(ZDCUser *)user {
	[_missingUserPubKeys addObject:user];
}

- (void)addMissingServerID:(NSString *)serverID {
	[_missingServerIDs addObject:serverID];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation ZDCCryptoTools {
@private
	
	__weak ZeroDarkCloud *zdc;
}

- (instancetype)initWithOwner:(ZeroDarkCloud *)inOwner
{
	if ((self = [super init]))
	{
		zdc = inOwner;
	}
	return self;
}

/**
 * Encrypts the given key using the public key.
 * To decrypt the result will require the private key.
 *
 * This process is called "wrapping a key" in cryptography.
 */
- (nullable NSData *)wrapSymmetricKey:(NSData *)symKey
                       usingPublicKey:(ZDCPublicKey *)pubKey
                                error:(NSError *_Nullable *_Nullable)errorOut
{
	NSData *dataOut = nil;
	NSError *error = nil;
	S4Err err = kS4Err_NoErr;
	
	size_t keyCount = 0;
	S4KeyContextRef *pubKeyCtxs = NULL;
	S4KeyContextRef symKeyCtx = kInvalidS4KeyContextRef;
	
	uint8_t *data = NULL;
	size_t dataLen = 0;
	
	Cipher_Algorithm algo = kCipher_Algorithm_Invalid;
	
	if (symKey == nil)
	{
		error = [NSError errorWithClass: [self class]
		                           code: 400
		                    description: @"Bad parameter: symKey is nil"];
		goto done;
	}
	if (pubKey == nil)
	{
		error = [NSError errorWithClass: [self class]
		                           code: 400
		                    description: @"Bad parameter: pubKey is nil"];
		goto done;
	}
	
	// create a S4 key context for the public key
	err = S4Key_DeserializeKeys((uint8_t *)pubKey.pubKeyJSON.UTF8String,
	                                       pubKey.pubKeyJSON.UTF8LengthInBytes,
	                                       &keyCount, &pubKeyCtxs); CKERR;
	
	ASSERTERR(keyCount == 1, kS4Err_SelfTestFailed);
	
	// create a S4 key for the cloud key
	switch(symKey.length * 8)
	{
		case  256 : algo = kCipher_Algorithm_3FISH256; break;
		case  512 : algo = kCipher_Algorithm_3FISH512; break;
		case 1024 : algo = kCipher_Algorithm_3FISH1024; break;
		default   : RETERR(kS4Err_BadParams);
	}
	
	err = S4Key_NewTBC(algo, symKey.bytes, &symKeyCtx); CKERR;

	// encode the symKe to the pubKey
	err = S4Key_SerializeToS4Key(symKeyCtx, pubKeyCtxs[0], &data, &dataLen); CKERR;
	
	dataOut = [[NSData alloc] initWithBytesNoCopy:data length:dataLen freeWhenDone:YES];
	
done:
	
	if (pubKeyCtxs)
	{
		if (S4KeyContextRefIsValid(pubKeyCtxs[0]))
		{
			S4Key_Free(pubKeyCtxs[0]);
		}
		XFREE(pubKeyCtxs);
	}

	if (S4KeyContextRefIsValid(symKeyCtx))
	{
		S4Key_Free(symKeyCtx);
	}
	
	if (IsS4Err(err)) {
		error = [NSError errorWithS4Error:err];
	}

	if(errorOut) *errorOut = error;
	return dataOut;
}

/**
 * Decrypts the given data using the corresponding private key.
 * This is the inverse of the `wrapKey:usingPubKey:transaction:error:` method.
 *
 * This process is called "unwrapping a key" in cryptography.
 *
 * @return
 *   The decrypted data, or nil if an error occurs.
 *   In the event of an error, the errorOut parameter will be set (if non-null).
 */
- (nullable NSData *)unwrapSymmetricKey:(NSData *)symKeyWrappedData
                        usingPrivateKey:(ZDCPublicKey *)privKey
                                  error:(NSError *_Nullable *_Nullable)errorOut
{
	S4Err err = kS4Err_NoErr;
	NSError *error = NULL;
	
	size_t keyCount = 0;
	
	S4KeyContextRef* privKeyCtxArray = NULL;
	S4KeyContextRef  privKeyCtx = kInvalidS4KeyContextRef;
	
	S4KeyContextRef* symKeyCtxArray = NULL;
	S4KeyContextRef  symKey = kInvalidS4KeyContextRef;
	
	S4KeyType symKeyType = kS4KeyType_Invalid;
	
	void *keyData = NULL;
	size_t keyDataLen = 0;
	
	NSData *data = nil;
	
	if (symKeyWrappedData == nil)
	{
		error = [NSError errorWithClass: [self class]
		                           code: 400
		                    description: @"Bad parameter: symKeyWrappedData is nil"];
		goto done;
	}
	if (privKey == nil)
	{
		error = [NSError errorWithClass: [self class]
		                           code: 400
		                    description: @"Bad parameter: privKey is nil"];
		goto done;
	}
	if (!privKey.isPrivateKey)
	{
		error = [NSError errorWithClass: [self class]
		                           code: 400
		                    description: @"Bad parameter: privKey is not a private key"];
		goto done;
	}
	
	// create a S4 key context for the private key
	err = S4Key_DeserializeKeys((uint8_t *)privKey.privKeyJSON.UTF8String,
	                                       privKey.privKeyJSON.UTF8LengthInBytes,
	                                       &keyCount, &privKeyCtxArray); CKERR;
	
	ASSERTERR(keyCount == 1, kS4Err_SelfTestFailed);
	
	err = S4Key_DecryptFromS4Key(privKeyCtxArray[0], zdc.storageKey, &privKeyCtx); CKERR;
	// check that it's a private key
	ASSERTERR(privKeyCtx->type == kS4KeyType_PublicKey, kS4Err_BadParams);
	ASSERTERR(privKeyCtx->pub.isPrivate, kS4Err_SelfTestFailed);
	
	// convert the encoded symKey to an S4 structure
	err = S4Key_DeserializeKeys((uint8_t *)symKeyWrappedData.bytes,
	                                       symKeyWrappedData.length,
	                                       &keyCount, &symKeyCtxArray); CKERR;
	
	ASSERTERR(keyCount == 1,  kS4Err_CorruptData);

	// unlock the cloud Key with the private key
	err = S4Key_DecryptFromS4Key(symKeyCtxArray[0], privKeyCtx, &symKey); CKERR;
	
	// check that we got what we expected
	err = S4Key_GetProperty(symKey, kS4KeyProp_KeyType, NULL, &symKeyType, sizeof(symKeyType), NULL); CKERR;
	ASSERTERR(symKeyType == kS4KeyType_Tweekable, kS4Err_CorruptData);

	// convert the cloud key to an NSData
	err = S4Key_GetAllocatedProperty(symKey, kS4KeyProp_KeyData, NULL, &keyData, &keyDataLen); CKERR;
	data = [[NSData alloc] initWithBytesNoCopy:keyData length:keyDataLen freeWhenDone:YES];
	
done:
	
	if (S4KeyContextRefIsValid(symKey)) {
		S4Key_Free(symKey);
	}
	
	if (S4KeyContextRefIsValid(privKeyCtx)) {
		S4Key_Free(privKeyCtx);
	}
	
	if (privKeyCtxArray)
	{
		if (S4KeyContextRefIsValid(privKeyCtxArray[0])) {
			S4Key_Free(privKeyCtxArray[0]);
		}
		XFREE(privKeyCtxArray);
	}
	
	if (symKeyCtxArray)
	{
		if (S4KeyContextRefIsValid(symKeyCtxArray[0])) {
			S4Key_Free(symKeyCtxArray[0]);
		}
		XFREE(symKeyCtxArray);
	}
	
	if (IsS4Err(err)) {
		error = [NSError errorWithS4Error:err];
	}
	
	if (errorOut) *errorOut = error;
	return data;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Cloud RCRD
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for description.
 */
- (nullable NSData *)cloudRcrdForNode:(ZDCNode *)node
                          transaction:(YapDatabaseReadTransaction *)transaction
                          missingInfo:(ZDCMissingInfo **)outMissingInfo
                                error:(NSError **)outError
{
	// Hello, and welcome to the crypto code !
	//
	// What is a RCRD file ?
	//
	// For each node, we store 2 files in the cloud:
	// - RCRD (short for record)
	// - DATA
	//
	// When you audit the data stored in the cloud, you'll see both these files clearly.
	// They share the same name, but use different file extensions. For example:
	//
	// - dcauqok66griorw7m7487itp3rtrceem.rcrd
	// - dcauqok66griorw7m7487itp3rtrceem.data
	//
	// The RCRD file is JSON, and stores ONLY the treesystem metadata.
	// That is, the minimum amount of information the server needs to correctly process the node.
	//
	// Here's a real world example:
	// {
	//   "metadata": "cmmDTQ8XYvajla+TtaB8QbRuSLYORQVt2hWLiqWMmGqNKjU6nNe/HmTKB+fF40lYpCwZYuBXOuYXA8q/XtDt4cxJTycT95cO8ZyJTpPM66grL04eXtUvX8ddS4BX3WEsobN+O94g2mHaXFdzePCJmyKqdlk=",
	//   "keys": {
	//     "UID:xnygbjz11arrbjfcxh7ta19yc14gm5zw": {
	//       "perms": "rws",
	//       "key": "ewogICAgInZlcnNpb24iOiAxLAogICAgImVuY29kaW5nIjogIkN1cnZlNDE0MTciLAogICAgImtleUlEIjogIkRlZXk3TmhFTEtGOWJmbTZLNjVhdGc9PSIsCiAgICAia2V5U3VpdGUiOiAiVGhyZWVGaXNoLTUxMiIsCiAgICAibWFjIjogIjd5UWlSbk5hSEdnPSIsCiAgICAiZW5jcnlwdGVkIjogIk1JSEVCZ2xnaGtnQlpRTUVBZ01FZFRCekF3SUhBQUlCTkFJME8zcVRLS1AveFNKZ1U5ZkU2OFdmZytRdkJsU2ozcXNUb1pDbHpaRWR1MHJGVzZ4QzV0a1AvRWFRMXkyMExkaVMybFBSM1FJMEVnSFQvZ3VvSVFFWDd5R2FTRTJpcVZQMEVUVzFYN2JoZ1YxNDZMS2ZFdkF6Z0RtSnVMWVVRSTRBQUFna1BNWHlmdmsxOGdSQVMwcC9TQ293U1VLc2F5ak9qOTRodE5WT3JoWUp2U3JQYm1BMTFIN1R5R2pSTDlCRHVyNHJjODgyOGo4NDRDcTlrczduUTd0aUlLdjNNb1cyMXQxWXZBPT0iCn0K"
	//     }
	//   },
	//   "version": 3,
	//   "fileID": "E0FE70C5C4894818A0B95BAEA38EDB26"
	// }
	//
	// Here's what these fields mean:
	//
	// - version
	//
	//   This is just the version of RCRD format itself.
	//   If we need to change the version of the RCRD JSON in the future, this will get incremented.
	//
	// - fileID
	//
	//   The is a UUID that is assigned by the server, and is immutable.
	//   It assists us in detecting when nodes have been moved or renamed.
	//   For example, if this file gets moved from path "/foo/bar" to "/buzz/lightyear",
	//   it will still have the same fileID, so we'll be able to detect that.
	//
	// - metadata
	//
	//   This section is encrypted, and must be decrypted in order to be read.
	//   In order to decrypt it, you'll need the node's encryptionKey.
	//   Every node has a different encryptionKey (randomly generated).
	//   Where is the encryptionKey? It's also encrypted, and stored in the keys section.
	//
	//   If we decrypt the metadata section, we'll find the node's cleartextname (i.e. ZDCNode.name).
	//   This is because the actual filename (when stored in the cloud)
	//   is a hashed version of the cleartext name (with salt that comes from the parent node).
	//   For example:
	//   - cleartext name: "The secret Coca-Cola recipe.txt"
	//   - cloud name: dcauqok66griorw7m7487itp3rtrceem.rcrd
	//
	//   This means the server cannot read filenames - it only sees hashes (with random salt!).
	//   For more information on how this works:
	//   - https://zerodarkcloud.readthedocs.io/en/latest/overview/encryption/
	//
	// - keys
	//
	//   This stores all of the permissions.
	//   In this example, the user with userID "xnygbjz11arrbjfcxh7ta19yc14gm5zw", has the following permissions:
	//   - (r)ead
	//   - (w)rite
	//   - (s)hare
	//
	//   The server will automatically send push notifications to the users in this list when the node is changed.
	//
	//   Further, this includes a wrapped version of the node's encryptionKey.
	//   The term "wrapped" means that the node's encryptionKey is first encrypted (wrapped) using the user's publicKey.
	//   And it's this wrapped version that gets stored in the JSON.
	//   Since user "xnygbjz11arrbjfcxh7ta19yc14gm5zw" is the only person who knows his/her privateKey,
	//   only they can decrypt this blob.
	//
	//
	// P.S. Thank you for performing your due dilligence.
	
	NSParameterAssert(outMissingInfo != nil);
	NSParameterAssert(outError != nil);
	
	__block ZDCMissingInfo *missingInfo = nil;
	__block NSError *error = nil;
	
	NSMutableDictionary *dict = nil;
	NSData *result = nil;
	
	// Sanity checks
	
	if (node == nil)
	{
		error = [self errorWithDescription:@"Node is nil"];
		goto done;
	}
	if (node.name == nil)
	{
		error = [self errorWithDescription:@"Node is missing name"];
		goto done;
	}
	if (node.encryptionKey == nil)
	{
		error = [self errorWithDescription:@"Node is missing encryptionKey"];
		goto done;
	}
	
	// Is this a special type of node ?
	
	const BOOL isPointer = node.isPointer;
	
	const BOOL isMessage =
	    [node.parentID hasSuffix:@"|inbox"]
	 || [node.parentID hasSuffix:@"|outbox"]
	 || [node.parentID hasSuffix:@"|signal"];
	
	// Prepare JSON dictionary
	
	dict = [NSMutableDictionary dictionaryWithCapacity:4];
	dict[kZDCCloudRcrd_Version] = @(kZDCCloudRcrdCurrentVersion);
	
	if (node.cloudID)
	{
		// This is the server assigned cloudID.
		// The very first time we upload a node, we don't know the cloudID (because the server hasn't assigned it yet).
		// After that, we have to set the cloudID in the JSON or the server will reject us.
		//
		dict[kZDCCloudRcrd_FileID] = node.cloudID;
	}
	
	// Add children section
	if (!isPointer && node.dirPrefix)
	{
		BOOL parentNodeAllowsChildren = YES;
		
		ZDCNode *parentNode = [transaction objectForKey:node.parentID inCollection:kZDCCollection_Nodes];
		ZDCShareItem *shareItem = [parentNode.shareList shareItemForUserID:node.localUserID];
		if (shareItem)
		{
			parentNodeAllowsChildren = ![shareItem hasPermission:ZDCSharePermission_LeafsOnly];
		}
		
		if (parentNodeAllowsChildren)
		{
			dict[kZDCCloudRcrd_Children] = @{
				@"": @{
					kZDCCloudRcrd_Children_Prefix: node.dirPrefix
				}
			};
		}
	}
	
	// Add keys section
	{
		ZDCShareList *shareList = node.shareList;
		NSMutableDictionary *dict_keys = [NSMutableDictionary dictionaryWithCapacity:shareList.count];
		
		[shareList enumerateListWithBlock:^(NSString *key, ZDCShareItem *shareItem, BOOL *stop) {
			
			if (shareItem.key.length > 0)
			{
				// We have everything we need already encoded for us.
				//
				// That is, shareItem.key contains a wrapped version of the node.encryptionKey.
				// So we can simply add it to the JSON.
				
				dict_keys[key] = shareItem.rawDictionary;
				return; // from block; continue;
			}
			
			if (!shareItem.canAddKey || ![shareItem hasPermission:ZDCSharePermission_Read])
			{
				// Doesn't need a key, or we haven't been granted permission to add one.
				// So we're using what we've got.
				
				dict_keys[key] = shareItem.rawDictionary;
				return; // from block; continue;
			}
			
			if ([ZDCShareList isUserKey:key])
			{
				NSString *userID = [ZDCShareList userIDFromKey:key];
				
				ZDCUser *user = [transaction objectForKey:userID inCollection:kZDCCollection_Users];
				
				if (user.accountBlocked || user.accountDeleted)
				{
					// accountBlocked:
					//   We've detected publicKey tampering for this user.
					//   So we're going to refuse to give the user acccess to the data.
					//
					// accountDeleted:
					//   The user account doesn't exist anymore.
					//   It's been deleted from the server.
					//
					// In either case, we still want to add an item to the keys section,
					// because the server might reject us without it.
					// But the item is NOT going to have an associated key.
					//
					NSAssert(shareItem.key.length == 0, @"Logic bomb");
					//
					// That is, we're not giving the user access to the file encryption key.
					// So they won't be able to decrypt the node.
					
					dict_keys[key] = shareItem.rawDictionary;
					return; // from block; continue;
				}
				
				ZDCPublicKey *pubKey =
				  [transaction objectForKey: user.publicKeyID
				               inCollection: kZDCCollection_PublicKeys];
				
				if (missingInfo == nil) {
					missingInfo = [[ZDCMissingInfo alloc] init];
				}
				
				if (user == nil)
				{
					// Missing user.
					
					[missingInfo addMissingUserID:userID];
				}
				else if (pubKey == nil)
				{
					// Missing user pubKey.
					
					[missingInfo addMissingUserPubKey:user];
				}
				else
				{
					// Missing (wrapped) node.encryptionKey for user.
					// This means we need to update the node.shareList.shareItem in the database.
					
					[missingInfo addMissingKey:key];
				}
			}
			else if ([ZDCShareList isServerKey:key])
			{
			//	NSString *serverID = [ZDCShareList serverIDFromKey:key];
				
			//	ZDCServer *server = [transaction objectForKey:serverID inCollection:kZDCCollection_Servers];
			//	if (server.accountDeleted)
			//	{
			//		return; // from block; continue;
			//	}
				
				// Future work:
				// - Need server API's for storing/retreiving server info
				// - downloading a server's publicKey based on serverID
			}
		}];
		
		dict[kZDCCloudRcrd_Keys] = dict_keys;
	}
	
	if (missingInfo == nil)
	{
		NSMutableDictionary *dict_meta = nil;
		NSMutableDictionary *dict_data = nil;
		
		if (isPointer)
		{
			dict_meta = [NSMutableDictionary dictionaryWithCapacity:1];
			dict_meta[kZDCCloudRcrd_Meta_Filename] = node.name;
			
			ZDCNode *pointee = [transaction objectForKey:node.pointeeID inCollection:kZDCCollection_Nodes];
			ZDCNodeAnchor *anchor = pointee.anchor;
			if (anchor)
			{
				NSString *cloudName =
				  [[ZDCCloudPathManager sharedInstance] cloudNameForNode:pointee transaction:transaction];
				
				NSString *path =
				  [NSString stringWithFormat:@"%@/%@/%@", anchor.treeID, anchor.dirPrefix, cloudName];
				
				NSMutableDictionary *pointer = [NSMutableDictionary dictionaryWithCapacity:3];
				
				pointer[kZDCCloudRcrd_Data_Pointer_Owner] = anchor.userID;
				pointer[kZDCCloudRcrd_Data_Pointer_Path] = path;
				pointer[kZDCCloudRcrd_Data_Pointer_CloudID] = pointee.cloudID;
				
				dict_data = [NSMutableDictionary dictionaryWithCapacity:1];
				dict_data[kZDCCloudRcrd_Data_Pointer] = pointer;
			}
		}
		else if (isMessage)
		{
			// Messages don't have metadata section.
			// But the server requires either a data or metadata section.
			
			dict[kZDCCloudRcrd_Meta] = @"";
		}
		else
		{
			dict_meta = [NSMutableDictionary dictionaryWithCapacity:2];
	
			dict_meta[kZDCCloudRcrd_Meta_Filename] = node.name;
			dict_meta[kZDCCloudRcrd_Meta_DirSalt] = [node.dirSalt base64EncodedStringWithOptions:0];
		}
		
		if (dict_meta)
		{
			if (![NSJSONSerialization isValidJSONObject:dict_meta])
			{
				error = [self errorWithDescription:@"NSJSONSerialization could not serialize 'meta' section."];
				goto done;
			}
			
			NSData *cleartext = [NSJSONSerialization dataWithJSONObject:dict_meta options:0 error:&error];
			if (error) goto done;
			
			// The section is encrypted using the node's encryption key.
			// This way, only those with permission can decrypt it.
			
			NSData *ciphertext = [cleartext encryptedDataWithSymmetricKey:node.encryptionKey error:&error];
			if (error) goto done;
			
			dict[kZDCCloudRcrd_Meta] = [ciphertext base64EncodedStringWithOptions:0];
		}
		
		if (dict_data)
		{
			if (![NSJSONSerialization isValidJSONObject:dict_data])
			{
				error = [self errorWithDescription:@"NSJSONSerialization could not serialize 'data' section."];
				goto done;
			}
			
			NSData *cleartext = [NSJSONSerialization dataWithJSONObject:dict_data options:0 error:&error];
			if (error) goto done;
			
			// The section is encrypted using the node's encryption key.
			// This way, only those with permission can decrypt it.
			
			NSData *ciphertext = [cleartext encryptedDataWithSymmetricKey:node.encryptionKey error:&error];
			if (error) goto done;
			
			dict[kZDCCloudRcrd_Data] = [ciphertext base64EncodedStringWithOptions:0];
		}
		
		// Add burnDate
		
		if (node.burnDate)
		{
			NSTimeInterval secondsSinceEpoch = [node.burnDate timeIntervalSince1970]; // ObjC format
			uint64_t millisSinceEpoch = (uint64_t)(secondsSinceEpoch * 1000);         // Javascript format
	
			dict[kZDCCloudRcrd_BurnDate] = @(millisSinceEpoch);
		}
	
		// Serialize RCRD
		
		if (![NSJSONSerialization isValidJSONObject:dict])
		{
			error = [self errorWithDescription:@"NSJSONSerialization could not serialize root dictionary."];
			goto done;
		}
	
		result = [NSJSONSerialization dataWithJSONObject:dict options:0 error:&error];
	}
	
done:
	
	*outMissingInfo = missingInfo;
	*outError = error;
	return result;
}

/**
 * See header file for description.
 */
- (NSUInteger)fixMissingKeysForShareList:(ZDCShareList *)shareList
                           encryptionKey:(NSData *)encryptionKey
                             transaction:(YapDatabaseReadTransaction *)transaction
{
	__block NSUInteger count = 0;
	
	for (NSString *key in [shareList allKeys])
	{
		ZDCShareItem *shareItem = [shareList shareItemForKey:key];
		
		if (shareItem.key.length > 0)
		{
			continue;
		}
		if (!shareItem.canAddKey || ![shareItem hasPermission:ZDCSharePermission_Read])
		{
			continue;
		}
		
		if ([ZDCShareList isUserKey:key])
		{
			NSString *userID = [ZDCShareList userIDFromKey:key];
			
			ZDCUser *user = [transaction objectForKey:userID inCollection:kZDCCollection_Users];
			if (user.accountDeleted)
			{
				continue;
			}
			
			ZDCPublicKey *pubKey =
			  [transaction objectForKey: user.publicKeyID
			               inCollection: kZDCCollection_PublicKeys];
			
			if (pubKey)
			{
				NSError *error = nil;
				NSData *wrappedNodeEncryptionKey =
				  [self wrapSymmetricKey: encryptionKey
				          usingPublicKey: pubKey
				                   error: &error];
				
				if (error)
				{
					// We're in a predicament here.
					// The user has asked us to give permission to the given user.
					// But it appears that the publicKey we have for the user is bad.
					
					[shareList removeShareItemForKey:key];
					count++;
				}
				else
				{
					[shareItem setKey:wrappedNodeEncryptionKey];
					count++;
				}
			}
		}
		else if ([ZDCShareList isServerKey:key])
		{
		//	NSString *serverID = [ZDCShareList serverIDFromKey:key];
				
		//	ZDCServer *server = [transaction objectForKey:serverID inCollection:kZDCCollection_Servers];
		//	if (server.accountDeleted)
		//	{
		//		return; // from block; continue;
		//	}
				
			// Future work:
			// - Need server API's for storing/retreiving server info
			// - downloading a server's publicKey based on serverID
		}
	}
	
	return count;
}

/**
 * See header file for description.
 */
- (ZDCCloudRcrd *)parseCloudRcrdDict:(NSDictionary *)dict
                         localUserID:(NSString *)localUserID
                         transaction:(YapDatabaseReadTransaction *)transaction
{
	ZDCLocalUser *localUser = nil;

	id value;
	NSUInteger version = 0;
	
	ZDCCloudRcrd *cloudRcrd = [[ZDCCloudRcrd alloc] init];
	
	__block NSString * encrypted_string = nil;
	__block NSData   * encrypted_data = nil;
	__block NSData   * decrypted_data = nil;
	
	// Fetch required information
	
	localUser = [transaction objectForKey:localUserID inCollection:kZDCCollection_Users];
	
	if (localUser == nil)
	{
		[cloudRcrd appendError:[self errorWithDescription:@"Missing localUser"]];
	}
	
	if (localUser.publicKeyID == nil)
	{
		[cloudRcrd appendError:[self errorWithDescription:@"Missing publicKeyID for localUser"]];
	}
	
	// Version
	value = dict[kZDCCloudRcrd_Version];
	if ([value isKindOfClass:[NSNumber class]])
	{
		version = [(NSNumber *)value unsignedIntegerValue];
		cloudRcrd.version = version;
	}
	
	// FileID
	value = dict[kZDCCloudRcrd_FileID];
	if ([value isKindOfClass:[NSString class]])
	{
		// The server calls it the `fileID`.
		// However, the term `fileID` means something completely different client-side.
		// So client-side we always refer to this value as the cloudID, since it's set by the "cloud".
		//
		cloudRcrd.cloudID = (NSString *)value;
	}
	
	// Sender
	value = dict[kZDCCloudRcrd_Sender];
	if ([value isKindOfClass:[NSString class]])
	{
		cloudRcrd.sender = (NSString *)value;
	}
	
	// BurnDate
	value = dict[kZDCCloudRcrd_BurnDate];
	if ([value isKindOfClass:[NSNumber class]])
	{
		uint64_t javascriptTs = [(NSNumber *)value unsignedLongLongValue];
		NSTimeInterval localTS = javascriptTs / (NSTimeInterval)1000;
		
		cloudRcrd.burnDate = [NSDate dateWithTimeIntervalSince1970:localTS];
	}
	
	// Children
	value = dict[kZDCCloudRcrd_Children];
	if ([value isKindOfClass:[NSDictionary class]])
	{
		cloudRcrd.children = (NSDictionary *)value;
	}
	
	// Process keys
	{
		NSDictionary *dict_keys = dict[kZDCCloudRcrd_Keys];
		
		if (dict_keys == nil)
		{
			[cloudRcrd appendError:[self errorWithDescription:@"Missing keys section"]];
		}
		if (![dict_keys isKindOfClass:[NSDictionary class]])
		{
			[cloudRcrd appendError:[self errorWithDescription:@"Invalid value for keys section: non-dictionary"]];
			dict_keys = nil;
		}
		
		ZDCShareList *shareList = [[ZDCShareList alloc] initWithDictionary:dict_keys];
		
		ZDCShareItem *shareItem = [shareList shareItemForUserID:localUserID];
		if (shareItem)
		{
			ZDCPublicKey *privKey = [transaction objectForKey: localUser.publicKeyID
			                                     inCollection: kZDCCollection_PublicKeys];
			if (privKey.isPrivateKey)
			{
				encrypted_data = shareItem.key;
				if (encrypted_data)
				{
					NSError *decryptionError = nil;
					cloudRcrd.encryptionKey =
					  [self unwrapSymmetricKey: encrypted_data
					           usingPrivateKey: privKey
					                     error: &decryptionError];
					
					if (decryptionError) {
						[cloudRcrd appendError:decryptionError];
					}
				}
			}
		}
		
		cloudRcrd.share = dict_keys;
		
		if (cloudRcrd.encryptionKey == nil)
		{
			[cloudRcrd appendError:[self errorWithDescription:@"No encyrption key found"]];
		}
	}
	
	// Process metadata
	do {
	
		encrypted_string = dict[kZDCCloudRcrd_Meta];
		
		if (encrypted_string == nil) {
			break;
		}
		
		if (![encrypted_string isKindOfClass:[NSString class]])
		{
			NSString *errMsg = @"dict[meta] has bad encrypted value: non-string";
			
			[cloudRcrd appendError:[self errorWithDescription:errMsg]];
			break;
		}
	
		encrypted_data = [[NSData alloc] initWithBase64EncodedString:encrypted_string options:0];
		if (!encrypted_data)
		{
			NSString *errMsg = @"dict[meta] has bad encrypted value: non-base64-string";
			
			[cloudRcrd appendError:[self errorWithDescription:errMsg]];
			break;
		}
		
		if (encrypted_data.length == 0)
		{
			cloudRcrd.metadata = [NSDictionary dictionary];
		}
		else if (cloudRcrd.encryptionKey)
		{
			NSError *error = nil;
			
			decrypted_data = [encrypted_data decryptedDataWithSymmetricKey:cloudRcrd.encryptionKey error:&error];
			if (error)
			{
				[cloudRcrd appendError:error];
				break;
			}
	
			NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:decrypted_data options:0 error:&error];
			if (error)
			{
				[cloudRcrd appendError:error];
				break;
			}
			
			if (![dict isKindOfClass:[NSDictionary class]])
			{
				NSString *errMsg = @"dict[meta] has bad decrypted value: non-dictionary";
				
				[cloudRcrd appendError:[self errorWithDescription:errMsg]];
				break;
			}
			
			// Since JSON doesn't support NSData (binary), we may have converted from NSData to NSString.
			// Undo that here (if needed).
			//
			NSMutableDictionary *dict_sanitized = [dict mutableCopy];
			[dict_sanitized normalizeFromJSON];
	
			cloudRcrd.metadata = dict_sanitized;
		}
	} while (NO);
	
	// Process data
	do {
		
		encrypted_string = dict[kZDCCloudRcrd_Data];
		
		if (encrypted_string == nil) {
			break;
		}
	
		if (![encrypted_string isKindOfClass:[NSString class]])
		{
			NSString *errMsg = @"dict[data] has bad encrypted value: non-string";
			
			[cloudRcrd appendError:[self errorWithDescription:errMsg]];
			break;
		}
		
		encrypted_data = [[NSData alloc] initWithBase64EncodedString:encrypted_string options:0];
		if (!encrypted_data)
		{
			NSString *errMsg = @"dict[data] has bad encrypted value: non-base64-string";
			
			[cloudRcrd appendError:[self errorWithDescription:errMsg]];
			break;
		}
		
		if (encrypted_data.length == 0)
		{
			cloudRcrd.data = [NSDictionary dictionary];
		}
		else if (cloudRcrd.encryptionKey)
		{
			NSError *error = nil;
			
			decrypted_data = [encrypted_data decryptedDataWithSymmetricKey:cloudRcrd.encryptionKey error:&error];
			if (error)
			{
				[cloudRcrd appendError:error];
				break;
			}
		
			NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:decrypted_data options:0 error:&error];
			if (error)
			{
				[cloudRcrd appendError:error];
				break;
			}
		
			if (![dict isKindOfClass:[NSDictionary class]])
			{
				NSString *errMsg = @"dict[data] has bad decrypted value: non-dictionary";
				
				[cloudRcrd appendError:[self errorWithDescription:errMsg]];
				break;
			}
		
			// Since JSON doesn't support NSData (binary), we may have converted from NSData to NSString.
			// Undo that here (if needed).
			//
			NSMutableDictionary *dict_sanitized = [dict mutableCopy];
			[dict_sanitized normalizeFromJSON];
		
			cloudRcrd.data = dict_sanitized;
		}
	} while (NO);
	
	
	return cloudRcrd;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark KeyGen
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (nullable ZDCPublicKey *)createPrivateKeyFromJSON:(NSString *)keyJSON
										  accessKey:(NSData *)accessKey
								encryptionAlgorithm:(Cipher_Algorithm)encryptionAlgorithm
										localUserID:(NSString *)localUserID
											  error:(NSError *_Nullable *_Nullable)errorOut
{

	NSError *			error = nil;
	S4Err         		err = kS4Err_NoErr;

	ZDCPublicKey* 		privKey = nil;
	size_t           	cipherSizeInBits = 0;

	S4KeyContextRef 	accessKeyKeyCtx = kInvalidS4KeyContextRef;
	S4KeyContextRef     *importCtx = NULL;
	S4KeyContextRef     privKeyCtx =  kInvalidS4KeyContextRef;
	size_t              keyCount = 0;

	uint8_t*   		 	privKeyData = NULL;
	uint8_t*    		pubKeyData = NULL;
	size_t     		 	keyDataLen = 0;

	NSString*           privKeyStr = nil;
	NSString*           pubKeyStr = nil;

	// parameter checking
	if (keyJSON == nil)
	{
		error = [self errorWithDescription:@"Missing keyJSON."];
		goto done;
	}

	if (localUserID == nil)
	{
		error = [self errorWithDescription:@"Missing localUserID."];
		goto done;
	}

	if (accessKey == nil)
	{
		error = [self errorWithDescription:@"Missing accessKey."];
		goto done;
	}


	if(!zdc || !S4KeyContextRefIsValid(zdc.storageKey))
	{
		error = [self errorWithDescription:@"unlocking key not available."];
		goto done;
	}

 	err = Cipher_GetKeySize(encryptionAlgorithm, &cipherSizeInBits); CKERR;
	ASSERTERR(accessKey.length == (cipherSizeInBits / 8), kS4Err_CorruptData );

	// Create a S4 Symmetric key to unlock the pub/priv key with
	err = S4Key_NewSymmetric(encryptionAlgorithm, accessKey.bytes, &accessKeyKeyCtx); CKERR;

	// use the cloud key to unlock the priv key
	err = S4Key_DeserializeKeys((uint8_t*)keyJSON.UTF8String, keyJSON.length, &keyCount, &importCtx ); CKERR;
	ASSERTERR(keyCount == 1,  kS4Err_SelfTestFailed);
	err = S4Key_DecryptFromS4Key(importCtx[0], accessKeyKeyCtx, &privKeyCtx); CKERR;

	// check that it is a private key
	ASSERTERR(privKeyCtx->type == kS4KeyType_PublicKey ,  kS4Err_BadParams);
	ASSERTERR(privKeyCtx->pub.isPrivate,  kS4Err_SelfTestFailed);

	// reserialize it encoded to our storage key
 	err = S4Key_SerializeToS4Key(privKeyCtx, zdc.storageKey, &privKeyData, &keyDataLen); CKERR;
 	privKeyStr = [[NSString alloc]initWithBytesNoCopy:privKeyData
											   length:keyDataLen
											 encoding:NSUTF8StringEncoding
										 freeWhenDone:YES];

	err = S4Key_SerializePubKey(privKeyCtx, &pubKeyData, &keyDataLen); CKERR;
	pubKeyStr = [[NSString alloc]initWithBytesNoCopy:pubKeyData
											  length:keyDataLen
											encoding:NSUTF8StringEncoding
										freeWhenDone:YES];

	privKey =  [[ZDCPublicKey alloc] initWithUserID:localUserID
									   pubKeyJSON:pubKeyStr
									  privKeyJSON:privKeyStr];

done:

	
	if (S4KeyContextRefIsValid(accessKeyKeyCtx))
		S4Key_Free(accessKeyKeyCtx);

	if(S4KeyContextRefIsValid(privKeyCtx))
		S4Key_Free(privKeyCtx);


	if (IsS4Err(err)) {
		error = [NSError errorWithS4Error:err];
	}


	if (errorOut) *errorOut = error;

	return privKey;
}

- (nullable ZDCSymmetricKey *)createSymmetricKey:(NSData*)keyData
								 		encryptionAlgorithm:(Cipher_Algorithm)encryptionAlgorithm
											  error:(NSError *_Nullable *_Nullable)errorOut
{
	NSError *			error = nil;
	S4Err         		err = kS4Err_NoErr;
	ZDCSymmetricKey* 	symKey = nil;

	S4KeyContextRef 	symKeyCtx = kInvalidS4KeyContextRef;

	size_t           	cipherSizeInBits = 0;

	// parameter checking
	if (keyData == nil)
	{
		error = [self errorWithDescription:@"Missing keyData."];
		goto done;
	}


	if(!zdc || !S4KeyContextRefIsValid(zdc.storageKey))
	{
		error = [self errorWithDescription:@"unlocking key not available."];
		goto done;
	}


	err = Cipher_GetKeySize(encryptionAlgorithm, &cipherSizeInBits); CKERR;
	ASSERTERR(keyData.length == (cipherSizeInBits / 8), kS4Err_CorruptData );

	// Create a S4 Symmetric key to unlock the pub/priv key with
	err = S4Key_NewSymmetric(encryptionAlgorithm, keyData.bytes, &symKeyCtx); CKERR;

	symKey = [ZDCSymmetricKey keyWithS4Key:symKeyCtx
								storageKey:zdc.storageKey];


done:

	if (S4KeyContextRefIsValid(symKeyCtx))
		S4Key_Free(symKeyCtx);

 	if (IsS4Err(err))
		error = [NSError errorWithS4Error:err];


	if (errorOut) *errorOut = error;

	return symKey;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Key Management
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Write some doocumentation here
 *
 */

- (NSData *)exportPublicKey:(ZDCPublicKey *)privKey
					  error:(NSError *_Nullable *_Nullable)errorOut
{
	NSError *          error = nil;
	S4Err              err = kS4Err_NoErr;

	S4KeyContextRef *  importCtx = NULL;
	S4KeyContextRef    privKeyCtx =  kInvalidS4KeyContextRef;

	NSString *         privKeyJSON = nil;
	size_t             keyCount = 0;

	uint8_t *          keyData = NULL;
	size_t             keyDataLen = 0;

	NSData *           data = NULL;

	if (privKey == nil)
	{
		error = [self errorWithDescription:@"Bad parameter: privKey is nil"];
		goto done;
	}

	ASSERTERR(privKey.isPrivateKey, kS4Err_BadParams);

	privKeyJSON = privKey.privKeyJSON;
	err = S4Key_DeserializeKeys((uint8_t *)privKeyJSON.UTF8String,
								privKeyJSON.UTF8LengthInBytes, &keyCount, &importCtx); CKERR;
	ASSERTERR(keyCount == 1, kS4Err_SelfTestFailed);

	err = S4Key_DecryptFromS4Key(importCtx[0], zdc.storageKey, &privKeyCtx); CKERR;

	err = S4Key_SerializePubKey(privKeyCtx, &keyData, &keyDataLen); CKERR;

	data = [[NSData alloc] initWithBytesNoCopy:keyData length:keyDataLen freeWhenDone:YES];

done:

	if (S4KeyContextRefIsValid(privKeyCtx))
		S4Key_Free(privKeyCtx);

	if (importCtx)
	{
		if(S4KeyContextRefIsValid(importCtx[0]))
		{
			S4Key_Free(importCtx[0]);
		}
		XFREE(importCtx);
	}

	if (IsS4Err(err))
		error = [NSError errorWithS4Error:err];

	if(errorOut)
		*errorOut = error;

	return data;
}

/**
 * Write some doocumentation here
 *
 */

- (NSData *)exportPrivateKey:(ZDCPublicKey *)privKey
				 encryptedTo:(ZDCSymmetricKey *)cloudKey
					   error:(NSError *_Nullable *_Nullable)errorOut
{
	NSError             *error = NULL;
	S4Err               err = kS4Err_NoErr;

	S4KeyContextRef     *importCtx = NULL;
	S4KeyContextRef     *symKeyCtx = NULL;

	S4KeyContextRef     privKeyCtx =  kInvalidS4KeyContextRef;
	S4KeyContextRef     cloudKeyCtx = kInvalidS4KeyContextRef;

	NSData*             data = NULL;

	uint8_t*    keyData = NULL;
	size_t      keyDataLen = 0;
	size_t          keyCount = 0;


	ASSERTERR(privKey.isPrivateKey,  kS4Err_BadParams);

	err = S4Key_DeserializeKeys((uint8_t*)cloudKey.keyJSON.UTF8String, cloudKey.keyJSON.length, &keyCount, &symKeyCtx ); CKERR;
	ASSERTERR(keyCount == 1,  kS4Err_SelfTestFailed);
	err = S4Key_DecryptFromS4Key(symKeyCtx[0], zdc.storageKey , &cloudKeyCtx); CKERR;

	err = S4Key_DeserializeKeys((uint8_t*)privKey.privKeyJSON.UTF8String, privKey.privKeyJSON.length, &keyCount, &importCtx ); CKERR;
	ASSERTERR(keyCount == 1,  kS4Err_SelfTestFailed);
	err = S4Key_DecryptFromS4Key(importCtx[0], zdc.storageKey , &privKeyCtx); CKERR;

	err = S4Key_SerializeToS4Key(privKeyCtx, cloudKeyCtx, &keyData, &keyDataLen); CKERR;
	data = [[NSData alloc] initWithBytesNoCopy:keyData length:keyDataLen freeWhenDone:YES];

done:

	if(S4KeyContextRefIsValid(cloudKeyCtx))
		S4Key_Free(cloudKeyCtx);

	if(S4KeyContextRefIsValid(privKeyCtx))
		S4Key_Free(privKeyCtx);

	if(symKeyCtx)
	{
		if(S4KeyContextRefIsValid(symKeyCtx[0]))
		{
			S4Key_Free(symKeyCtx[0]);
		}
		XFREE(symKeyCtx);
	}

	if(importCtx)
	{
		if(S4KeyContextRefIsValid(importCtx[0]))
		{
			S4Key_Free(importCtx[0]);
		}
		XFREE(importCtx);
	}

	if(IsS4Err(err))
		error = [NSError errorWithS4Error:err];

	if(errorOut)
		*errorOut = error;

	return data;
}

/**
 * Write some doocumentation here
 *
 */

-(BOOL) checkPublicKeySelfSig:(ZDCPublicKey *)pubKey
						error:(NSError *_Nullable *_Nullable)errorOut
{

	NSError *          error = nil;
	S4Err              err = kS4Err_NoErr;

	S4KeyContextRef *  importCtx = NULL;
	size_t             keyCount = 0;

	NSString *         pubKeyJSON = nil;

	uint8_t             selfkeyID[kS4Key_KeyIDBytes]  = {0};


	S4KeyContextRef     *sigListCtx = NULL;
	size_t              sigCount = 0;

	BOOL                selfSigFound = NO;

	if (pubKey == nil)
	{
		error = [self errorWithDescription:@"Bad parameter: privKey is nil"];
		goto done;
	}

	if (![pubKey checkKeyValidityWithError:nil])
	{
		error = [self errorWithDescription:@"Unreadable pubKey for user"];
		goto done;
	}


	pubKeyJSON = pubKey.pubKeyJSON;
	err = S4Key_DeserializeKeys((uint8_t *)pubKeyJSON.UTF8String,
								pubKeyJSON.UTF8LengthInBytes, &keyCount, &importCtx); CKERR;
	ASSERTERR(keyCount == 1, kS4Err_PubPrivKeyNotFound);


	err = S4Key_GetProperty(importCtx[0], kS4KeyProp_KeyID, NULL, &selfkeyID, sizeof(selfkeyID), NULL ); CKERR;


	// check sigs
	err =  S4Key_GetKeySignatures(importCtx[0],&sigCount, &sigListCtx); CKERR;

	for(int i = 0; i <sigCount; i++)
	{
		S4KeyContextRef sigCtx = sigListCtx[i];
		if(sigCtx)
		{
			if(sigCtx->type == kS4KeyType_Signature)
			{
				// check self sig
				if(S4Key_CompareKeyID(sigCtx->sig.issuerID, selfkeyID))
				{
					err = S4Key_VerfiyKeySig(importCtx[0], importCtx[0], sigCtx);
					selfSigFound = YES;
					break;
				}

			}
		}
	}

done:
	if (importCtx)
	{

		for(int i = 0; i < keyCount; i++)
			if(S4KeyContextRefIsValid(importCtx[i]))
			{
				S4Key_Free(importCtx[i]);
			}
		XFREE(importCtx);
	}

	if (IsS4Err(err))
		error = [NSError errorWithS4Error:err];

	if(errorOut)
		*errorOut = error;

	return selfSigFound;
}

/**
 * Write some doocumentation here
 *
 */

-(NSString*) keyIDforPrivateKeyData:(NSData*)dataIn
							  error:(NSError *_Nullable *_Nullable)errorOut
{
	S4KeyContextRef     *importCtx = NULL;
	S4KeyContextRef     privKeyCtx =  kInvalidS4KeyContextRef;

	NSError             *error = NULL;
	S4Err               err = kS4Err_NoErr;

	size_t              keyCount = 0;

	NSString*           locator = nil;
	char*               keyIDStr = NULL;

	ASSERTERR(dataIn,  kS4Err_BadParams);

	// use the cloud key to unlock the priv key
	err = S4Key_DeserializeKeys((uint8_t*)dataIn.bytes, dataIn.length, &keyCount, &importCtx ); CKERR;
	ASSERTERR(keyCount == 1,  kS4Err_SelfTestFailed);

	privKeyCtx = importCtx[0];

	// check that it is a private key
	ASSERTERR(privKeyCtx->type == kS4KeyType_SymmetricEncrypted ,  kS4Err_BadParams);
	ASSERTERR(privKeyCtx->pub.isPrivate,  kS4Err_SelfTestFailed);

	// save the keyID
	err = S4Key_GetAllocatedProperty(privKeyCtx, kS4KeyProp_KeyIDString, NULL, (void**)&keyIDStr, NULL); CKERR;
	locator = [NSString stringWithUTF8String:keyIDStr];

done:

	if(S4KeyContextRefIsValid(privKeyCtx))
		S4Key_Free(privKeyCtx);

	if(IsS4Err(err))
		error = [NSError errorWithS4Error:err];

	if(errorOut)
		*errorOut = error;


	return locator;

}

- (BOOL)updateKeyProperty:(NSString*)propertyID
					value:(NSData*)value
		  withPublicKeyID:(NSString *)publicKeyID
			  transaction:(YapDatabaseReadWriteTransaction *)transaction
					error:(NSError **)errorOut
{
	NSError             *error = NULL;
	BOOL success = NO;

	ZDCPublicKey* pubKey = [transaction objectForKey:publicKeyID
										inCollection:kZDCCollection_PublicKeys];

	if(!pubKey)
	{
		error = [NSError errorWithS4Error:kS4Err_PubPrivKeyNotFound];
	}
	else
	{
		pubKey = pubKey.copy;

		success = [pubKey updateKeyProperty:propertyID
									  value:value
								 storageKey:zdc.storageKey
									  error:&error];

		if(success && !error)
		{
			[transaction setObject:pubKey
							forKey:publicKeyID
					  inCollection:kZDCCollection_PublicKeys];
		}
	}

	if(errorOut)
		*errorOut = error;


	return  success;
}


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark DirSalt
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)setDirSaltForTrunkNode:(ZDCTrunkNode *)trunkNode
                 withLocalUser:(ZDCLocalUser *)localUser
                     accessKey:(ZDCSymmetricKey *)accessKey
{
	NSParameterAssert(trunkNode != nil);
	NSParameterAssert(trunkNode.isImmutable == NO);
	
	NSParameterAssert(localUser != nil);
	NSParameterAssert(accessKey != nil);
	
	NSParameterAssert([trunkNode.localUserID isEqualToString:localUser.uuid]);
	NSParameterAssert([localUser.accessKeyID isEqualToString:accessKey.uuid]);
	
	if (trunkNode.trunk == ZDCTreesystemTrunk_Inbox)
	{
		// The 'Inbox' trunk is writable by other users.
		// And other users won't know our accessKey (obviously),
		// so we're going to use a simple hash instead.
		//
		// Important:
		//   We are not doing this for security.
		//   This is NOT a security thing.
		//   This has nothing to do with security.
		//   The entire world knows the salt value for these directories.
		//   We just want a quick-n-easy way to get 160 bits.
		//   SHA1 is the quick-n-easy solution.
		
		NSData *input = [trunkNode.dirPrefix dataUsingEncoding:NSUTF8StringEncoding];
		
		HASH_Algorithm algo = kHASH_Algorithm_SHA1; // This isn't a security thing. Read the comments above.
		
		size_t outputSizeInBits = 0;
		HASH_GetBits(algo, &outputSizeInBits);
		
		size_t outputSizeInBytes = outputSizeInBits / 8;
		NSAssert(outputSizeInBytes == kZDCNode_DirSaltKeySizeInBytes, @"Size mismatch");
		
		uint8_t output[outputSizeInBytes];
		
		S4Err err = HASH_DO(kHASH_Algorithm_SHA1, input.bytes, input.length, &output, outputSizeInBytes);
		if (err == kS4Err_NoErr)
		{
			trunkNode.dirSalt = [NSData dataWithBytes:output length:outputSizeInBytes];
		}
	}
	else
	{
		NSError *error = nil;
		trunkNode.dirSalt =
		  [self kdfWithSymmetricKey: accessKey
		                     length: kZDCNode_DirSaltKeySizeInBytes
		                      label: @"storm4-directory-salt"
		                       salt: [trunkNode.dirPrefix dataUsingEncoding:NSUTF8StringEncoding]
		                      error: &error];
	}
	
	return (trunkNode.dirSalt != nil);
}

- (nullable NSData *)kdfWithSymmetricKey:(ZDCSymmetricKey *)inSymKey
                                  length:(NSUInteger)length
                                   label:(NSString *)label
                                    salt:(NSData *)salt
                                   error:(NSError *_Nullable *_Nullable)errorOut
{
	S4Err err = kS4Err_NoErr;
	NSError *error = nil;
	
	NSData          * dataOut = nil;
	
	S4KeyContextRef * wtfKeyCtx = NULL;
	S4KeyContextRef   symKeyCtx = kInvalidS4KeyContextRef;
	size_t            keyCount = 0;
	
	void   * keyData = NULL;
	size_t   keyDataLen = 0;
	
	uint8_t *hash = malloc(length);
	
	ASSERTERR(inSymKey != nil,  kS4Err_BadParams);
	ASSERTERR(length > 0,       kS4Err_BadParams);
	ASSERTERR(label.length > 0, kS4Err_BadParams);
	ASSERTERR(salt.length > 0,  kS4Err_BadParams);
	
	// decode the cloneKey
	err = S4Key_DeserializeKeys((uint8_t *)inSymKey.keyJSON.UTF8String,
	                               (size_t)inSymKey.keyJSON.UTF8LengthInBytes,
	                                       &keyCount,
	                                       &wtfKeyCtx); CKERR;
	
	ASSERTERR(keyCount == 1, kS4Err_SelfTestFailed);
	
	err = S4Key_DecryptFromS4Key(wtfKeyCtx[0], zdc.storageKey, &symKeyCtx); CKERR;
	
	// get the keydata
	err = S4Key_GetAllocatedProperty(symKeyCtx, kS4KeyProp_KeyData, NULL, &keyData, &keyDataLen); CKERR;
	
	err = MAC_KDF(kMAC_Algorithm_SKEIN,
	              kHASH_Algorithm_SKEIN256,
	              keyData, keyDataLen,
	              label.UTF8String,
	   (uint8_t *)salt.bytes, salt.length,
	    (uint32_t)length * 8, length, hash); CKERR;
	
	dataOut = [NSData dataWithBytes:hash length:length];
	
done:
	
	if (hash) {
		free(hash); // always due to due to possibility that error causes goto done prematurely
	}
	
	if (S4KeyContextRefIsValid(symKeyCtx)) {
		S4Key_Free(symKeyCtx);
	}
	
	if (wtfKeyCtx)
	{
		if (S4KeyContextRefIsValid(wtfKeyCtx[0])) {
			S4Key_Free(wtfKeyCtx[0]);
		}
		XFREE(wtfKeyCtx);
	}
	
	if (keyData)
	{
		ZERO(keyData, keyDataLen);
		XFREE(keyData);
	}
	
	if (IsS4Err(err)) {
		error = [NSError errorWithS4Error:err];
	}
	
	if (errorOut) *errorOut = error;
	return dataOut;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Errors
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSError *)errorWithDescription:(nullable NSString *)description
{
	return [self errorWithCode:0 description:description];
}

- (NSError *)errorWithCode:(NSInteger)code description:(nullable NSString *)description
{
	return [NSError errorWithClass:[self class] code:code description:description];
}

@end
