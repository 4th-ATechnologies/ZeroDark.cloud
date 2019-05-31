#import "OSImage+QRCode.h"
#import "OSImage+ZeroDark.h"

@import QuartzCore;
@import CoreImage;
@import ImageIO;


@implementation OSImage (QRCode)

+ (OSImage * _Nullable)QRImageWithString:(NSString *)dataString
								withSize:(CGSize)requestedSize
{
	OSImage *image = nil;

	NSData *data = [dataString dataUsingEncoding:NSUTF8StringEncoding];
	CIFilter *filter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
	[filter setDefaults];
	[filter setValue:data forKey:@"InputMessage"];
	[filter setValue:@"M" forKey:@"inputCorrectionLevel"];

	CIImage *ciImage = [filter outputImage];

	if (!ciImage)
		return nil;

#if TARGET_OS_IPHONE
	UIGraphicsBeginImageContextWithOptions(requestedSize, false, 0);
	CGContextRef graphicsContext=UIGraphicsGetCurrentContext();
	CGContextSetInterpolationQuality(graphicsContext, kCGInterpolationNone);

	CGImageRef filterOutputCGImageRef=[ [CIContext contextWithOptions:@{ kCIContextUseSoftwareRenderer: @(YES) }]
									   createCGImage:ciImage
									   fromRect: ciImage.extent];

	CGContextDrawImage(graphicsContext, CGContextGetClipBoundingBox(graphicsContext), filterOutputCGImageRef);
	CGImageRelease(filterOutputCGImageRef);

	image =UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
#else

	NSCIImageRep *rep = [NSCIImageRep imageRepWithCIImage: ciImage];
	NSImage* tinyImage = [[NSImage alloc] init];
	[tinyImage addRepresentation: rep];
	if (requestedSize.width <= rep.size.width)
		return tinyImage;

	// Scale image up:
	image = [[NSImage alloc] initWithSize: requestedSize];
	[image lockFocus];
	[NSGraphicsContext currentContext].imageInterpolation = NSImageInterpolationNone;
	[tinyImage drawInRect: (NSRect) {	.origin.x = 0,
										.origin.y = 0,
										.size = requestedSize}];

	[image unlockFocus];
#endif

	return image;
}

+ (void) QRImageWithString:(NSString*) dataString
			scaledSize:(CGSize)requestedSize
		   completionQueue:(dispatch_queue_t _Nullable)inCompletionQueue
		   completionBlock:(void (^)(OSImage * _Nullable image))completionBlock
{

	__block dispatch_queue_t completionQueue = inCompletionQueue;
	if (!completionQueue)
		completionQueue = dispatch_get_main_queue();


	void (^invokeCompletionBlock)(OSImage * _Nullable img )
	= ^(OSImage * _Nullable img){

		if (completionBlock == nil) return;

		dispatch_async(completionQueue, ^{ @autoreleasepool {
			completionBlock(img);
		}});

	};

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{ @autoreleasepool {

		OSImage *image = [self QRImageWithString:dataString
											withSize:requestedSize];
		invokeCompletionBlock(image);
	}});

}

-(NSString*) QRCodeString
{
    NSString* qrString = NULL;
    
    @autoreleasepool {
        CIImage*        ciImage = [[CIImage alloc] initWithCGImage:self.CGImage];
        CIContext*      context = [CIContext context];
        NSDictionary*   options =
        @{ CIDetectorAccuracy : CIDetectorAccuracyHigh }; // Slow but thorough
        //                              @{ CIDetectorAccuracy : CIDetectorAccuracyLow}; // Fast but superficial
        
        CIDetector* qrDetector = [CIDetector detectorOfType:CIDetectorTypeQRCode
                                                    context:context
                                                    options:options];
        
        if ([[ciImage properties] valueForKey:(NSString*) kCGImagePropertyOrientation] == nil) {
            options = @{ CIDetectorImageOrientation : @(1)};
        } else {
            options = @{ CIDetectorImageOrientation : [[ciImage properties] valueForKey:(NSString*) kCGImagePropertyOrientation]};
        }
        
        NSArray * features = [qrDetector featuresInImage:ciImage
                                                 options:options];
        
        
        if (features != nil && features.count > 0) {
            for (CIQRCodeFeature* qrFeature in features)
            {
                qrString =   qrFeature.messageString;
                break;
            }
        }
    };
    
    return qrString;
}


@end
