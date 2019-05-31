/**
 * Storm4
 * https://www.storm4.cloud
**/

#import <Foundation/Foundation.h>

typedef NS_OPTIONS(NSUInteger, S4DeepCopyOptions) {
	S4DeepCopy_MutableContainers = 1 << 0,
	S4DeepCopy_MutableLeaves     = 1 << 1,
};

/**
 * The deep copy methods currently only work with JSON compatible objects:
 * 
 * - The top level object is an NSArray or NSDictionary.
 * - All objects are instances of NSString, NSNumber, NSArray, NSDictionary, or NSNull.
 * - All dictionary keys are instances of NSString.
**/

@interface NSDictionary (S4DeepCopy)

- (id)deepCopyWithOptions:(S4DeepCopyOptions)options;

@end

@interface NSArray (S4DeepCopy)

- (id)deepCopyWithOptions:(S4DeepCopyOptions)options;

@end
