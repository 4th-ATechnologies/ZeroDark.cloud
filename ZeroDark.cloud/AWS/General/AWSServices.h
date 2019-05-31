#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * List of AWS services.
 *
 * This obviously isn't the full list. But this is open source.
 * So go ahead and add what you need. Then feel free to submit a pull request.
**/
typedef NS_ENUM(NSInteger, AWSService) {
	
	/** S3 */
	AWSService_S3,
	
	/** API Gateway */
	AWSService_APIGateway,
	
	/** Represents an invalid service. Kinda like a nil value. */
	AWSService_Invalid = NSIntegerMax
};

/**
 * Common utility methods related to AWS services.
 */
@interface AWSServices : NSObject

/**
 * Returns the short name of the service.
 * This is the value typically used internally by amazon (e.g. in authentication steps).
 */
+ (NSString *)shortNameForService:(AWSService)service;

@end

NS_ASSUME_NONNULL_END
