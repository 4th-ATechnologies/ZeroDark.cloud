#import "OSImage+ZeroDark.h"

#if TARGET_OS_IPHONE
//#import "UIColor+Crayola.h"
#endif

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h> 
#import <AVFoundation/AVFoundation.h>

@implementation OSImage (ZeroDark)

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Shared
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * See header file for documentation.
 */
- (NSData *)dataWithPNG
{
#if TARGET_OS_IPHONE
	
	return UIImagePNGRepresentation(self);
	
#else // macOS
	
	NSRect rect = (NSRect){
		.origin = NSMakePoint(0, 0),
		.size = self.size
	};
	
	NSBitmapImageRep *bitmapRep = nil;
	[self lockFocus];
	{
		bitmapRep = [[NSBitmapImageRep alloc] initWithFocusedViewRect:rect];
	}
	[self unlockFocus];
	
	return [bitmapRep representationUsingType:NSPNGFileType properties:@{}];
	
#endif
}

/**
 * See header file for documentation.
 */
- (NSData *)dataWithJPEG
{
	return [self dataWithJPEGCompression:1.0];
}

/**
 * See header file for documentation.
 */
- (NSData *)dataWithJPEGCompression:(float)factor
{
#if TARGET_OS_IPHONE
	
	return UIImageJPEGRepresentation(self, factor);
	
#else // macOS

	NSRect rect = (NSRect){
		.origin = NSMakePoint(0, 0),
		.size = self.size
	};
	
	NSBitmapImageRep *bitmapRep = nil;
	[self lockFocus];
	{
		bitmapRep = [[NSBitmapImageRep alloc] initWithFocusedViewRect:rect];
	}
	[self unlockFocus];
	
	NSDictionary *props = @{ NSImageCompressionFactor: @(factor) };
	
	return [bitmapRep representationUsingType:NSBitmapImageFileTypeJPEG properties:props];
	
#endif
}

/**
 * See header file for documentation.
 */
- (OSImage *)scaledToWidth:(float)requestedWidth
{
	const CGFloat scaleFactor = requestedWidth / self.size.width;
	
	const CGFloat newHeight = self.size.height * scaleFactor;
	const CGFloat newWidth = self.size.width * scaleFactor;
	
	CGSize newSize = (CGSize){
		.width = newWidth,
		.height = newHeight
	};
	
	if (CGSizeEqualToSize(self.size, newSize))
	{
		// No changes required
		return self;
	}
	
#if TARGET_OS_IPHONE
	
	float screenScale = [[UIScreen mainScreen] scale];
	
	UIImage *newImage = nil;
	UIGraphicsBeginImageContextWithOptions(newSize, NO, screenScale);
	{
		[self drawInRect:CGRectMake(0, 0, newWidth, newHeight)];
		newImage = UIGraphicsGetImageFromCurrentImageContext();
	}
	UIGraphicsEndImageContext();
	
	return newImage;

#else
	
	return [self imageByScalingProportionallyToSize:newSize];
	
#endif
}

/**
 * See header file for documentation.
 */
- (OSImage *)scaledToHeight:(float)requestedHeight
{
	const CGFloat scaleFactor = requestedHeight / self.size.height;
	
	const CGFloat newWidth = self.size.width * scaleFactor;
	const CGFloat newHeight = self.size.height * scaleFactor;
	
	CGSize newSize = (CGSize){
		.width = newWidth,
		.height = newHeight
	};
	
	if (CGSizeEqualToSize(self.size, newSize))
	{
		// No changes required
		return self;
	}
	
#if TARGET_OS_IPHONE
	
	float screenScale = [[UIScreen mainScreen] scale];
	
	UIImage *newImage = nil;
	UIGraphicsBeginImageContextWithOptions(newSize, NO, screenScale);
	{
		[self drawInRect:CGRectMake(0, 0, newWidth, newHeight)];
		newImage = UIGraphicsGetImageFromCurrentImageContext();
	}
	UIGraphicsEndImageContext();
	
	return newImage;
	
#else
	
	return [self imageByScalingProportionallyToSize:newSize];
	
#endif
}

/**
 * See header file for documentation.
 */
- (OSImage *)zdc_scaledToSize:(CGSize)targetSize scalingMode:(ScalingMode)mode
{
	CGSize selfSize = self.size;
	
	if (CGSizeEqualToSize(selfSize, targetSize)) {
		// No scaling needed
		return self;
	}
	
	CGFloat aspectWidth = targetSize.width / selfSize.width;
	CGFloat aspectHeight = targetSize.height / selfSize.height;

	CGFloat aspectRatio;
	if (mode == ScalingMode_AspectFit) {
		aspectRatio = MIN(aspectWidth, aspectHeight);
	} else {
		aspectRatio = MAX(aspectWidth, aspectHeight);
	}
	
	CGSize newSize = (CGSize){
		.width = selfSize.width * aspectRatio,
		.height = selfSize.height * aspectRatio
	};
	
	CGRect targetRect = (CGRect){
		.origin.x = (targetSize.width - newSize.width) / 2.0,
		.origin.y = (targetSize.height - newSize.height) / 2.0,
		.size = newSize
	};
	
	OSImage *newImage = nil;
	
#if TARGET_OS_IPHONE
	
	float screenScale = [[UIScreen mainScreen] scale];
	
	UIGraphicsBeginImageContextWithOptions(targetRect.size, NO, screenScale);
	{
		[self drawInRect:targetRect];
		newImage = UIGraphicsGetImageFromCurrentImageContext();
	}
	UIGraphicsEndImageContext();

#else
	
	if (![self isValid]) {
		return self;
	}
	
	newImage = [[NSImage alloc] initWithSize:targetRect.size];
	[newImage lockFocus];
	{
		[self drawInRect: targetRect
		        fromRect: NSZeroRect
		       operation: NSCompositingOperationSourceOver
		        fraction: 1.0];
	}
	[newImage unlockFocus];
	
#endif
	
	return newImage;
}

/**
 * See header file for documentation.
 */
- (OSImage *)imageByScalingProportionallyToSize:(CGSize)requestedSize
{
	OSImage *newImage = nil;
	
	CGRect targetRect =
	  AVMakeRectWithAspectRatioInsideRect(self.size, CGRectMake(0, 0, requestedSize.width, requestedSize.height));
	targetRect.origin = CGPointMake(0,0);
	
	if (CGSizeEqualToSize(self.size, targetRect.size))
	{
		// No changes required
		return self;
	}
	
#if TARGET_OS_IPHONE
	
	float screenScale = [[UIScreen mainScreen] scale];
	
	UIGraphicsBeginImageContextWithOptions(targetRect.size, NO, screenScale);
	{
		[self drawInRect:targetRect];
		newImage = UIGraphicsGetImageFromCurrentImageContext();
	}
	UIGraphicsEndImageContext();

#else
	
	if (![self isValid]) {
		return self;
	}
	
	// When the methods of this class were simplified,
	// we found 3 different implementations for scaling images on macOS.
	//
	// However, the original author left ZERO documentation!
	// Shame, shame, shame !!
	//
	// And so we were left to our own devices.
	// And we made a decision.
	
	if (YES)
	{
		newImage = [[NSImage alloc] initWithSize:targetRect.size];
		[newImage lockFocus];
		{
			[self drawInRect: targetRect
			        fromRect: NSZeroRect
			       operation: NSCompositingOperationSourceOver
			        fraction: 1.0];
		}
		[newImage unlockFocus];
	}
	else if (/* DISABLES CODE */ (NO))
	{
		// Why was this implementation discontinued ?
	
		NSImageRep *sourceImageRep =
		  [self bestRepresentationForRect: targetRect
		                          context: nil
		                            hints: @{ NSImageHintInterpolation: @(NSImageInterpolationHigh) }];
	
		newImage = [[NSImage alloc] initWithSize:targetRect.size];
		[newImage lockFocus];
		{
			[sourceImageRep drawInRect:targetRect];
		}
		[newImage unlockFocus];
	}
	else
	{
		// This implementation was what was used previously.
		// However, it was removed because it was believed that this implementation is
		// pixel-based, as opposed to points-based.
		//
		// In other words, would create images too small on retina screens.
		//
		// This may or may not be correct.
		// However, the original author didn't document their code, so...
	
		CGImageRef imageRef =
		  [self CGImageForProposedRect: &targetRect
		                       context: [NSGraphicsContext currentContext]
		                         hints :@{ NSImageHintInterpolation: @(NSImageInterpolationHigh) }];
	
		newImage = [[NSImage alloc] initWithCGImage:imageRef size:targetRect.size];
	}

#endif
	
	return newImage;
}

/**
 * See header file for documentation.
 */
- (OSImage *)imageWithMaxSize:(CGSize)maxSize
{
	CGSize currentSize = self.size;
	
	if ((currentSize.width > maxSize.width) || (currentSize.height > maxSize.height))
	{
		return [self imageByScalingProportionallyToSize:maxSize];
	}
	else
	{
		return self;
	}
	
#if 0
	
	// Old scaling code for macOS
		
	OSImage *smallImage = [[OSImage alloc] initWithSize:maxSize];
	NSSize originalSize = [existingImage size];
	
	NSRect fromRect = (NSRect){
		.origin = NSMakePoint(0, 0),
		.size = originalSize
	};
	NSRect toRect = (NSRect){
		.origin = NSMakePoint(0, 0),
		.size = maxSize
	};
	
	[smallImage lockFocus];
	{
		[existingImage drawInRect: toRect
							  fromRect: fromRect
							 operation: NSCompositingOperationCopy
							  fraction: 1.0f];
	}
	[smallImage unlockFocus];
	
	return smallImage;
	
#endif
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - iOS Only
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#if TARGET_OS_IPHONE

- (UIImage *)maskWithColor:(UIColor *)color
{
    CGImageRef maskImage = self.CGImage;
    CGFloat width = self.scale * self.size.width;
    CGFloat height = self.scale * self.size.height;
    CGRect bounds = CGRectMake(0,0,width,height);
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef bitmapContext =
    CGBitmapContextCreate(NULL, width, height, 8, 0, colorSpace, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    
    CGContextClipToMask(bitmapContext, bounds, maskImage);
    CGContextSetFillColorWithColor(bitmapContext, color.CGColor);
    CGContextFillRect(bitmapContext, bounds);
    
    CGImageRef cImage = CGBitmapContextCreateImage(bitmapContext);
    UIImage *coloredImage =
    [UIImage imageWithCGImage:cImage scale:self.scale orientation:UIImageOrientationUp];
    
    CGContextRelease(bitmapContext);
    CGColorSpaceRelease(colorSpace);
    CGImageRelease(cImage);
    
    return coloredImage;
}

- (UIImage *)grayscaleImage
{
    typedef enum {
        ALPHA = 0,
        BLUE = 1,
        GREEN = 2,
        RED = 3
    } PIXELS;

    CGFloat scale = [[UIScreen mainScreen] scale];
    
    CGSize size = [self size];
    int width = size.width *scale;
    int height = size.height *scale;
    
    // the pixels will be painted to this array
    uint32_t *pixels = (uint32_t *) malloc(width * height * sizeof(uint32_t));
    
    // clear the pixels so any transparency is preserved
    memset(pixels, 0, width * height * sizeof(uint32_t));
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
    // create a context with RGBA pixels
    CGContextRef context = CGBitmapContextCreate(pixels, width, height, 8, width * sizeof(uint32_t), colorSpace,
                                                 kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedLast);
    
    // paint the bitmap to our context which will fill in the pixels array
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), [self CGImage]);
    
    for(int y = 0; y < height; y++) {
        for(int x = 0; x < width; x++) {
            uint8_t *rgbaPixel = (uint8_t *) &pixels[y * width + x];
            
            // convert to grayscale using recommended method: http://en.wikipedia.org/wiki/Grayscale#Converting_color_to_grayscale
            uint32_t gray = 0.3 * rgbaPixel[RED] + 0.59 * rgbaPixel[GREEN] + 0.11 * rgbaPixel[BLUE];
            
            // set the pixels to gray
            rgbaPixel[RED] = gray;
            rgbaPixel[GREEN] = gray;
            rgbaPixel[BLUE] = gray;
        }
    }
    
    // create a new CGImageRef from our context with the modified pixels
    CGImageRef image = CGBitmapContextCreateImage(context);
    
    // we're done with the context, color space, and pixels
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    free(pixels);
    
    // make a new UIImage to return
    UIImage *resultUIImage = [UIImage imageWithCGImage:image scale:scale orientation:UIImageOrientationUp];
    
    // we're done with image now too
    CGImageRelease(image);
    
    return resultUIImage;
}

- (UIImage *)addUpperRightTabImage:(UIImage*)tabImage maxSize:(CGFloat)maxSize
{
	UIImage *imageOut = nil;
	CGFloat tabSize;
	
	float screenScale = [[UIScreen mainScreen] scale];
	
	UIGraphicsBeginImageContextWithOptions(self.size, NO, screenScale);
	{
		[self drawInRect:CGRectMake(0, 0, self.size.width, self.size.height)];
		
		if (self.size.width > self.size.height)
		{
			tabSize = self.size.width / 2;
			
			if(tabSize > self.size.width * maxSize)
				tabSize = self.size.width * maxSize;
		}
		else
		{
			tabSize = self.size.height / 2;
			
			if(tabSize > self.size.height * maxSize)
				tabSize = self.size.height * maxSize;
			
		}
		
		[tabImage drawInRect: CGRectMake(self.size.width - tabSize,  0, tabSize, tabSize)
		           blendMode: kCGBlendModeSourceAtop
		               alpha: 0.9];
		
		imageOut = UIGraphicsGetImageFromCurrentImageContext();
	}
	UIGraphicsEndImageContext();
	
	return imageOut;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - macOS Only
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#else

/**
 * See header file for documentation.
 */
- (CGImageRef)CGImage
{
	NSData *imageData = self.TIFFRepresentation;
	CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)imageData, NULL);
	CGImageRef maskRef = CGImageSourceCreateImageAtIndex(source, 0, NULL);
	
	CFRelease(source);
	CFAutorelease(maskRef);
	return maskRef;
}

/**
 * See header file for documentation.
 */
+ (OSImage *)imageWithData:(NSData *)data
{
	return [[NSImage alloc] initWithData:data];
}

- (OSImage *)imageTintedWithColor:(OSColor *)tint
{
	NSSize size = [self size];
	NSRect imageBounds = (NSRect){
		.origin.x = 0,
		.origin.y = 0,
		.size = size
	};
	
	NSImage *copiedImage = [self copy];
	
	if (tint != nil)
	{
		[copiedImage lockFocus];
		{
			[tint set];
			NSRectFillUsingOperation(imageBounds, NSCompositingOperationSourceAtop);
		}
		[copiedImage unlockFocus];
	}
	
	return copiedImage;
}

- (NSImage *)roundedImageWithCornerRadius:(float)radius
{
	NSSize size = self.size;
	NSRect rect = (NSRect){
		.origin.x = 0,
		.origin.y = 0,
		.size = size
	};
	
	NSImage *composedImage = [[NSImage alloc] initWithSize:size];
	[composedImage lockFocus];
	{
		[[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationHigh];
		
		NSRect imageFrame = NSRectFromCGRect(rect);
		NSBezierPath *clipPath = [NSBezierPath bezierPathWithRoundedRect:imageFrame xRadius:radius yRadius:radius];
		
		[clipPath setWindingRule:NSEvenOddWindingRule];
		[clipPath addClip];
		
		[self drawAtPoint: NSZeroPoint
		         fromRect: rect
		        operation: NSCompositingOperationSourceOver
		         fraction: 1];
	}
	[composedImage unlockFocus];
	
	return composedImage;
}

+ (CGImageRef)createMaskWithImage:(CGImageRef)image
{
	long maskWidth               = CGImageGetWidth(image);
	long maskHeight              = CGImageGetHeight(image);
	// round bytesPerRow to the nearest 16 bytes, for performance's sake
	long bytesPerRow             = (maskWidth + 15) & 0xfffffff0;
	long bufferSize              = bytesPerRow * maskHeight;
	
	// allocate memory for the bits
	CFMutableDataRef dataBuffer = CFDataCreateMutable(kCFAllocatorDefault, 0);
	CFDataSetLength(dataBuffer, bufferSize);
	
	// the data will be 8 bits per pixel, no alpha
	CGColorSpaceRef colourSpace = CGColorSpaceCreateDeviceGray();
	CGContextRef ctx            = CGBitmapContextCreate(CFDataGetMutableBytePtr(dataBuffer),
	                                                    maskWidth, maskHeight,
	                                                    8, bytesPerRow, colourSpace, 0);
	
	// drawing into this context will draw into the dataBuffer.
	CGContextDrawImage(ctx, CGRectMake(0, 0, maskWidth, maskHeight), image);
	CGContextRelease(ctx);
	
	// now make a mask from the data.
	CGDataProviderRef dataProvider  = CGDataProviderCreateWithCFData(dataBuffer);
	CGImageRef mask                 = CGImageMaskCreate(maskWidth, maskHeight, 8, 8, bytesPerRow,
	                                                    dataProvider, NULL, FALSE);
    
	CGDataProviderRelease(dataProvider);
	CGColorSpaceRelease(colourSpace);
	CFRelease(dataBuffer);
	
	CFAutorelease(mask);
	return mask;
}

/**
 * See header file for documentation.
 */
- (OSImage *)animatedGifWithTint:(OSColor *)tintColor slowdown:(float)slowdown
{
	// Credit:
	// https://gist.github.com/keefo/5344890
	
	NSMutableData *dataDestination = [NSMutableData data];
	OSImage *result = nil;
	
	NSArray *reps = [self representations];
	for (NSImageRep * rep in reps)
	{
		if ([rep isKindOfClass:[NSBitmapImageRep class]] == YES)
		{
			NSBitmapImageRep * bitmapRep = (NSBitmapImageRep *)rep;
			int numFrame = [[bitmapRep valueForProperty:NSImageFrameCount] intValue];
			if (numFrame > 0)
			{
				// set the place to save the GIF to
				
				CGImageDestinationRef animatedGIF =
				  CGImageDestinationCreateWithData((__bridge CFMutableDataRef)dataDestination,
				                                   kUTTypeGIF,
				                                   numFrame,
				                                   NULL);
				
				CGBitmapInfo bitmapInfo =
				  kCGBitmapByteOrderDefault |
				  kCGImageAlphaPremultipliedLast; // | kCGImageAlphaNoneSkipFirst
				
				CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
				int bitsPerComponent = 8;
				
				for (int i = 0; i < numFrame; ++i)
				{
					[bitmapRep setProperty:NSImageCurrentFrame withValue:@(i)];
					
					CGDataProviderRef frameProvider =
					  CGDataProviderCreateWithData(NULL,
					                               [bitmapRep bitmapData],
					                               [bitmapRep bytesPerRow] * [bitmapRep pixelsHigh],
					                               NULL);
					
					CGImageRef cgFrame_original =
					  CGImageCreate ([bitmapRep pixelsWide],
					                 [bitmapRep pixelsHigh],
					                 bitsPerComponent,
					                 [bitmapRep bitsPerPixel],
					                 [bitmapRep bytesPerRow],
					                 colorSpace,
					                 bitmapInfo,
					                 frameProvider,
					                 NULL,
					                 NO,
					                 kCGRenderingIntentDefault);
					
					if (cgFrame_original)
					{
						float duration = [[bitmapRep valueForProperty:NSImageCurrentFrameDuration] floatValue] * slowdown;
						
						NSDictionary *frameProperties = @{
							(NSString *)kCGImagePropertyGIFDictionary: @{
								(NSString *)kCGImagePropertyGIFDelayTime : @(duration)
							}
						};
						
						if (tintColor)
						{
							CGContextRef bitmapContext =
							  CGBitmapContextCreate(NULL,
							                        [bitmapRep pixelsWide],
							                        [bitmapRep pixelsHigh],
							                        bitsPerComponent,
							                        [bitmapRep bytesPerRow],
					 		                        colorSpace,
							                        bitmapInfo);
						
							CGRect bounds = CGRectMake(0, 0, [bitmapRep pixelsWide], [bitmapRep pixelsHigh]);
							CGContextClipToMask(bitmapContext, bounds, cgFrame_original);
							CGContextSetFillColorWithColor(bitmapContext, tintColor.CGColor);
							CGContextFillRect(bitmapContext, bounds);
						
							CGImageRef cgFrame_tinted = CGBitmapContextCreateImage(bitmapContext);
						
							CGImageDestinationAddImage(animatedGIF,
							                           cgFrame_tinted,
							 (__bridge CFDictionaryRef)frameProperties);
							
							CGContextRelease(bitmapContext);
							CGImageRelease(cgFrame_tinted);
						}
						else
						{
							CGImageDestinationAddImage(animatedGIF,
							                           cgFrame_original,
							 (__bridge CFDictionaryRef)frameProperties);
						}
						
						CGImageRelease(cgFrame_original);
					}
					
					CGDataProviderRelease(frameProvider);
				}
				
				CGColorSpaceRelease(colorSpace);
				
				NSDictionary *gifProperties = @{
					(NSString *)kCGImagePropertyGIFDictionary: @{
						(NSString *)kCGImagePropertyGIFLoopCount : @0
					}
				};
				
				CGImageDestinationSetProperties(animatedGIF, (__bridge CFDictionaryRef) gifProperties);
				
				CGImageDestinationFinalize(animatedGIF);
				result = [NSImage imageWithData:dataDestination];
				
				CFRelease(animatedGIF);
			}
		}
	}
	
	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Archive
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*
- (NSImage *)roundCorners
{
	NSSize size = [self size];
	NSRect rect = (NSRect){
		.origin.x = 0,
		.origin.y = 0,
		.size = size
	};
	
	NSImage *composedImage = [[NSImage alloc] initWithSize:size];
	[composedImage lockFocus];
	{
		[[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationHigh];
		
		NSRect imageFrame = NSRectFromCGRect(CGRectMake(0, 0, 1024, 1024));
		NSBezierPath *clipPath = [NSBezierPath bezierPathWithRoundedRect:imageFrame xRadius:200 yRadius:200];
		
		[clipPath setWindingRule:NSEvenOddWindingRule];
		[clipPath addClip];
		
		[self drawAtPoint: NSZeroPoint
		         fromRect: rect
		        operation: NSCompositingOperationSourceOver
		         fraction: 1];
	}
	[composedImage unlockFocus];
	
	return composedImage;
}
*/

#endif
@end
