#import "OSPlatform.h"

NS_ASSUME_NONNULL_BEGIN

@interface OSImage (QRCode)

+ (OSImage *_Nullable )QRImageWithString:(NSString *)dataString
								withSize:(CGSize)requestedSize;

- (NSString *)QRCodeString;

+ (void) QRImageWithString:(NSString*) dataString
				scaledSize:(CGSize)requestedSize
		   completionQueue:(dispatch_queue_t _Nullable)completionQueue
		   completionBlock:(void (^)(OSImage * _Nullable image))completionBlock;

@end

NS_ASSUME_NONNULL_END
