/**
* ZeroDark.cloud Framework
* 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCUserAccessKeyManager.h"

#import "ZeroDarkCloudPrivate.h"
#import "ZDCSymmetricKeyPrivate.h"

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

- (ZDCAccessKeyBlob *)blobFromData:(NSData *)blobData
                       localUserID:(NSString *)localUserID
                             error:(NSError *_Nullable *_Nullable)errorOut
{
	
	S4Err              err = kS4Err_NoErr;

	Cipher_Algorithm   algorithm = kCipher_Algorithm_2FISH256;
	size_t             cipherSizeInBits = 0;

	S4KeyContextRef    cloneKeyCtx = kInvalidS4KeyContextRef;
	ZDCSymmetricKey  * symKey = nil;
	
	ZDCAccessKeyBlob * blob = nil;
	NSError          * error = nil;
	
	err = Cipher_GetKeySize(algorithm, &cipherSizeInBits); CKERR;
	ASSERTERR(blobData.length == (cipherSizeInBits / 8), kS4Err_BadParams);

	err = S4Key_NewSymmetric(algorithm, blobData.bytes, &cloneKeyCtx); CKERR;

	symKey = [ZDCSymmetricKey createWithS4Key:cloneKeyCtx storageKey:zdc.storageKey error:&error];
	if (error) {
		goto done;
	}

	blob = [[ZDCAccessKeyBlob alloc] initWithLocalUserID:localUserID accessKey:symKey];

done:

	if (IsS4Err(err)) {
		error = [NSError errorWithS4Error:err];
	}

	if (S4KeyContextRefIsValid(cloneKeyCtx)) {
		S4Key_Free(cloneKeyCtx);
	}

	if (errorOut) *errorOut = error;
	return blob;
}


@end



