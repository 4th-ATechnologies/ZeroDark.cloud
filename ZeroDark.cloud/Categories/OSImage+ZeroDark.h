/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "OSPlatform.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Rules for scaling an image.
 */
typedef NS_ENUM(NSInteger, ScalingMode) {
	
	/**
	 * AspectFit:
	 * - the width will not exceed size.width
	 * - the height will not exceed size.height
	 * - the width or height may be less than the given size
	 */
	ScalingMode_AspectFit,
	
	/**
	 * AspectFill:
	 * - the width will not be less than size.width
	 * - the height will not be less than size.height
	 * - the width or height may be greater than the given size
	 */
	ScalingMode_AspectFill
};

/**
 * OSImage is defined as either NSImage or UIImage, depending on which platform we're compiling for.
 */
@interface OSImage (ZeroDark)

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Shared
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Cross platform method of extracting PNG data from a NSImage/UIImage.
 */
- (nullable NSData *)dataWithPNG;

/**
 * Cross platform method of extracting JPEG data from a NSImage/UIImage.
 *
 * This method invokes `dataWithJPEGCompression:` and passes 1.0 as the parameter.
 * This results in the least compression (or best quality).
 */
- (nullable NSData *)dataWithJPEG;

/**
 * Cross platform method of extracting JPEG data from a NSImage/UIImage.
 *
 * @param compressionQuality
 *   The quality of the resulting JPEG image, expressed as a value from 0.0 to 1.0.
 *   The value 0.0 represents the maximum compression (or lowest quality) while the
 *   value 1.0 represents the least compression (or best quality).
 */
- (nullable NSData *)dataWithJPEGCompression:(float)compressionQuality;

/**
 * Scales the image UP or DOWN (proportionally) to match given width.
 *
 * @note The original image is not modified, but rather a new (scaled) image is returned.
 */
- (OSImage *)scaledToWidth:(float)requestedWidth;

/**
 * Scales the image UP or DOWN (proportionally) to match given height.
 *
 * @note The original image is not modified, but rather a new (scaled) image is returned.
 */
- (OSImage *)scaledToHeight:(float)requestedHeight;

/**
 * Scales the image UP or DOWN (proportionally) to the given size, using the given scaling mode:
 *
 * AspectFit:
 * - the width will not exceed size.width
 * - the height will not exceed size.height
 * - the width or height may be less than the given size
 *
 * AspectFill:
 * - the width will not be less than size.width
 * - the height will not be less than size.height
 * - the width or height may be greater than the given size
 */
- (OSImage *)zdc_scaledToSize:(CGSize)size scalingMode:(ScalingMode)mode;

/**
 * Scales the image UP or DOWN (proportionally) to fit within the given target size.
 *
 * - the image will be scaled as big as possible (while still fitting within the target size)
 * - the width will not exceed targetSize.width
 * - the height will not exceed targetSize.height
 *
 * @note The original image is not modified, but rather a new (scaled) image is returned.
 */
- (OSImage *)imageByScalingProportionallyToSize:(CGSize)targetSize;

/**
 * If the image is BIGGER than EITHER the given width or height,
 * then it will be scaled down proportionally to fit within the given max size constraints.
 *
 * If the image is SMALLER than BOTH the given max width and height,
 * then it is returned as is (without modification).
 *
 * @note The original image is not modified, but rather a new (scaled) image is returned.
 */
- (OSImage *)imageWithMaxSize:(CGSize)size;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark iOS Only
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#if TARGET_OS_IPHONE

- (OSImage *)maskWithColor:(UIColor *)color;
- (OSImage *)grayscaleImage;

- (OSImage *)addUpperRightTabImage:(UIImage*)tabImage maxSize:(CGFloat)maxSize;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark macOS Only
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#else

/**
 * On iOS, UIImage has a CFImage property.
 * But no such property exists on macOS.
 *
 * This category method simply fills in the gap.
 */
- (CGImageRef)CGImage;

/**
 * On iOS, UIImage has both `initWithData:` & `imageWithData:`.
 * But on macOS, NSImage has only `initWithData:`.
 *
 * This category method simply fills in the gap.
 */
+ (OSImage *)imageWithData:(NSData *)data;

/**
 * On iOS it's easy to round an image via: UIImageView.layer.cornerRadius.
 * But on macOS, it's considerably more difficult.
 *
 * This category method provides a workaround.
 */
- (OSImage *)roundedImageWithCornerRadius:(float)radius;

- (OSImage *)imageTintedWithColor:(OSColor *)tint;

/**
 * Returns a new animated image, with optional tinting & speed changes.
 *
 * @param tint
 *   Allows you to optionally tint each frame of the animated gif.
 *   Pass nil to skip the tinting step, and leave each image frame as-is.
 *
 * @param slowdown
 *   This value is applied to the duration of each frame within the animated gif as follows:
 *   `newFrameDuration = originalFrameDuration * slowdown`
 *   Therefore, a value of 1.0 causes no changes, a value of 2.0 causes the animation to take twice as long,
 *   and a value of 0.5 causes the image to be faster.
 */
- (OSImage *)animatedGifWithTint:(nullable OSColor *)tint slowdown:(float)slowdown;

#endif

@end

NS_ASSUME_NONNULL_END
