/**
* ZeroDark.cloud Framework
* <GitHub link goes here>
**/

#import "ZDCUserAccessKeyManagerPrivate.h"
#import "ZeroDarkCloudPrivate.h"

#import "ZDCSymmetricKey.h"

// Categories
#import "NSError+S4.h"

 
@implementation ZDCAccessKeyBlob

@synthesize localUserID = localUserID;
@synthesize accessKey = accessKey;

- (id)initWithLocalUserID:(NSString *)inLocalUserID
			accessKey:(ZDCSymmetricKey *)inAccessKey;
{
	if ((self = [super init]))
	{
		localUserID = [inLocalUserID copy];
		accessKey = [inAccessKey copy];
	}
	return self;
}



@end
@implementation ZDCUserAccessKeyManager{
@private

	__weak ZeroDarkCloud *owner;
}

- (instancetype)initWithOwner:(ZeroDarkCloud *)inOwner
{
	if ((self = [super init]))
	{
		owner = inOwner;
	}
	return self;
}

- (ZDCAccessKeyBlob *)blobFromData:(NSData *)blobData
					   localUserID:(NSString *)localUserID
							 error:(NSError *_Nullable *_Nullable)errorOut
{
	ZDCAccessKeyBlob * blob = nil;
	NSError     * error = nil;
	S4Err         err = kS4Err_NoErr;

	Cipher_Algorithm algorithm = kCipher_Algorithm_2FISH256;
	size_t           cipherSizeInBits = 0;

	S4KeyContextRef newcloneKeyCtx = kInvalidS4KeyContextRef;
	ZDCSymmetricKey * symKey = nil;

	err = Cipher_GetKeySize(algorithm, &cipherSizeInBits); CKERR;
	ASSERTERR(blobData.length == (cipherSizeInBits / 8), kS4Err_CorruptData );

	err = S4Key_NewSymmetric(algorithm, blobData.bytes, &newcloneKeyCtx); CKERR;

	symKey = [ZDCSymmetricKey keyWithS4Key:newcloneKeyCtx
								storageKey:owner.storageKey];

	// create the blob
	blob = [[ZDCAccessKeyBlob alloc] initWithLocalUserID:localUserID
												accessKey:symKey];

done:

	if (IsS4Err(err)) {
		error = [NSError errorWithS4Error:err];
	}

	if (S4KeyContextRefIsValid(newcloneKeyCtx)) {
		S4Key_Free(newcloneKeyCtx);
	}

	if (errorOut) *errorOut = error;
	return blob;
}


@end



