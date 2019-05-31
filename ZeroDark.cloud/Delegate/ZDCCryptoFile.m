/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import "ZDCCryptoFile.h"

@implementation ZDCCryptoFile

@synthesize fileURL = _fileURL;
@synthesize fileFormat = _fileFormat;
@synthesize encryptionKey = _encryptionKey;
@synthesize retainToken = _retainToken;

- (instancetype)initWithFileURL:(NSURL *)fileURL
                     fileFormat:(ZDCCryptoFileFormat)fileFormat
                  encryptionKey:(NSData *)encryptionKey
                    retainToken:(nullable id)retainToken
{
	if ((self = [super init]))
	{
		_fileURL = fileURL;
		_fileFormat = fileFormat;
		_encryptionKey = [encryptionKey copy]; // mutable data protection
		_retainToken = retainToken;
	}
	return self;
}

@end
