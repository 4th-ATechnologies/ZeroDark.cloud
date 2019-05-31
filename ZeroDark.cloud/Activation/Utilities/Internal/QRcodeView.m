//
//  QRcodeView.m
//  storm4
//
//  Created by vincent Moscaritolo on 2/8/16.
//  Copyright © 2016 4th-A Technologies, LLC. All rights reserved.
//

#import "QRcodeView.h"

@implementation QRcodeView
{
    CGRect _portalRect;
}


- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
    }
    return self;
}
//
- (void)setPortalRect:(CGRect)rectIn
{
    _portalRect = rectIn;
}



- (void)drawRect:(CGRect)rect
{
 
#if TARGET_OS_IPHONE

    UIBezierPath* outerfill =   [UIBezierPath bezierPathWithRect:rect];

    [[[OSColor blackColor] colorWithAlphaComponent:0.5] setFill];
    
    UIBezierPath* transparentPath = [UIBezierPath bezierPathWithRoundedRect:_portalRect cornerRadius:20.];
    [outerfill appendPath:transparentPath];
    outerfill.usesEvenOddFillRule  = YES;
    [outerfill fill];
    
    UIBezierPath *path = [UIBezierPath bezierPath];
   [path moveToPoint: CGPointMake( CGRectGetMaxX(_portalRect) - 40, CGRectGetMaxY(_portalRect) - 20)];
    [path addLineToPoint: CGPointMake( CGRectGetMaxX(_portalRect) -20 , CGRectGetMaxY(_portalRect) -20)];
    [path addLineToPoint: CGPointMake( CGRectGetMaxX(_portalRect) -20 , CGRectGetMaxY(_portalRect) -40)];
    
    [path moveToPoint: CGPointMake( CGRectGetMinX(_portalRect) + 40, CGRectGetMinY(_portalRect) + 20)];
    [path addLineToPoint: CGPointMake( CGRectGetMinX(_portalRect) +20 , CGRectGetMinY(_portalRect) +20)];
    [path addLineToPoint: CGPointMake( CGRectGetMinX(_portalRect) +20 , CGRectGetMinY(_portalRect) +40)];

    [path moveToPoint: CGPointMake( CGRectGetMaxX(_portalRect) - 40, CGRectGetMinY(_portalRect) + 20)];
    [path addLineToPoint: CGPointMake( CGRectGetMaxX(_portalRect) -20 , CGRectGetMinY(_portalRect) +20)];
    [path addLineToPoint: CGPointMake( CGRectGetMaxX(_portalRect) -20 , CGRectGetMinY(_portalRect)+ 40)];

    [path moveToPoint: CGPointMake( CGRectGetMinX(_portalRect) + 40, CGRectGetMaxY(_portalRect) - 20)];
    [path addLineToPoint: CGPointMake( CGRectGetMinX(_portalRect) +20 , CGRectGetMaxY(_portalRect) -20)];
    [path addLineToPoint: CGPointMake( CGRectGetMinX(_portalRect) +20 , CGRectGetMaxY(_portalRect) -40)];


    [[[OSColor whiteColor] colorWithAlphaComponent:0.8] setStroke];
    path.lineWidth = 4.;
    [path stroke];
    
#else
   
  
//    NSBezierPath* outerfill =   [NSBezierPath bezierPathWithRect:rect];
//    
//    [[[OSColor blackColor] colorWithAlphaComponent:0.5] setFill];
//    
//    NSBezierPath* transparentPath = [NSBezierPath bezierPathWithRoundedRect:_portalRect xRadius:20 yRadius:20];
//    [outerfill appendBezierPath:transparentPath];
//    
// //   outerfill.usesEvenOddFillRule  = YES;
//    [outerfill fill];
    
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path moveToPoint: CGPointMake( CGRectGetMaxX(_portalRect) - 40, CGRectGetMaxY(_portalRect) - 20)];
    [path lineToPoint: CGPointMake( CGRectGetMaxX(_portalRect) -20 , CGRectGetMaxY(_portalRect) -20)];
    [path lineToPoint: CGPointMake( CGRectGetMaxX(_portalRect) -20 , CGRectGetMaxY(_portalRect) -40)];
    
    [path moveToPoint: CGPointMake( CGRectGetMinX(_portalRect) + 40, CGRectGetMinY(_portalRect) + 20)];
    [path lineToPoint: CGPointMake( CGRectGetMinX(_portalRect) +20 , CGRectGetMinY(_portalRect) +20)];
    [path lineToPoint: CGPointMake( CGRectGetMinX(_portalRect) +20 , CGRectGetMinY(_portalRect) +40)];
    
    [path moveToPoint: CGPointMake( CGRectGetMaxX(_portalRect) - 40, CGRectGetMinY(_portalRect) + 20)];
    [path lineToPoint: CGPointMake( CGRectGetMaxX(_portalRect) -20 , CGRectGetMinY(_portalRect) +20)];
    [path lineToPoint: CGPointMake( CGRectGetMaxX(_portalRect) -20 , CGRectGetMinY(_portalRect)+ 40)];
    
    [path moveToPoint: CGPointMake( CGRectGetMinX(_portalRect) + 40, CGRectGetMaxY(_portalRect) - 20)];
    [path lineToPoint: CGPointMake( CGRectGetMinX(_portalRect) +20 , CGRectGetMaxY(_portalRect) -20)];
    [path lineToPoint: CGPointMake( CGRectGetMinX(_portalRect) +20 , CGRectGetMaxY(_portalRect) -40)];
    
    
    [[[OSColor whiteColor] colorWithAlphaComponent:0.8] setStroke];
    path.lineWidth = 4.;
    [path stroke];

    
#endif
 };

#ifdef TARGET_OS_MAC

+ (NSString *) qrStringFromSampleBuffer:(CMSampleBufferRef)sampleBuffer withContext:(CIContext*)ciContext
{
    NSString* qrString = NULL;
    
    // Get a CMSampleBuffer's Core Video image buffer for the media data
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    // Lock the base address of the pixel buffer
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    
    // Get the number of bytes per row for the pixel buffer
    void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
    
    // Get the number of bytes per row for the pixel buffer
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    // Get the pixel buffer width and height
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    
    // Create a device-dependent RGB color space
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
    // Create a bitmap graphics context with the sample buffer data
    CGContextRef context = CGBitmapContextCreate(baseAddress, width, height, 8,
                                                 bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    // Create a Quartz image from the pixel data in the bitmap graphics context
    CGImageRef quartzImage = CGBitmapContextCreateImage(context);
    // Unlock the pixel buffer
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
    
    // Free up the context and color space
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    
    CIImage*        ciImage = [[CIImage alloc] initWithCGImage:quartzImage];
    NSDictionary*   options =
    //                                 @{ CIDetectorAccuracy : CIDetectorAccuracyHigh }; // Slow but thorough
    @{ CIDetectorAccuracy : CIDetectorAccuracyLow}; // Fast but superficial
    
    CIDetector* qrDetector = [CIDetector detectorOfType:CIDetectorTypeQRCode
                                                context:ciContext
                                                options:options];
    
    if ([[ciImage properties] valueForKey:(NSString*) kCGImagePropertyOrientation] == nil) {
        options = @{ CIDetectorImageOrientation : @1};
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
    
    // Release the Quartz image
    CGImageRelease(quartzImage);
    
    return (qrString);
}
#endif
@end
