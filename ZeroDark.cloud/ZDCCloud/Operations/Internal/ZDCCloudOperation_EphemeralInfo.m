/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
**/

#import "ZDCCloudOperation_EphemeralInfo.h"

#import "ZDCPollContext.h"
#import "ZDCTouchContext.h"


@implementation ZDCCloudOperation_EphemeralInfo {
@private
	
	dispatch_queue_t queue;
	
	NSUInteger s3_successiveFailCount;
	NSNumber *s3_successiveFail_statusCode;
	
	NSInteger polling_successiveFailCount;
	
	NSUInteger s4_successiveFailCount;
	NSNumber *s4_successivFail_extStatusCode;
}

@synthesize asyncData;

@synthesize pollContext;
@synthesize multipollContext;
@synthesize touchContext;

@synthesize abortRequested;
@synthesize resolveByPulling;

@synthesize lastChangeToken;
@synthesize postResolveUUID;

@synthesize continuation_rcrd;
@synthesize continuation_data;

@dynamic s3_successiveFailCount;
@dynamic s3_successiveFail_statusCode;

@dynamic polling_successiveFailCount;

@dynamic s4_successiveFailCount;
@dynamic s4_successiveFail_extStatusCode;

- (instancetype)init
{
	if ((self = [super init]))
	{
		queue = dispatch_queue_create(NULL, DISPATCH_QUEUE_SERIAL);
	}
	return self;
}

static BOOL numbersAreEqual(NSNumber *num1, NSNumber *num2)
{
	if (num1 == nil)
	{
		if (num2 == nil)
			return YES;
		else
			return NO;
	}
	else
	{
		if (num2 == nil)
			return NO;
		else
			return (num1.integerValue == num2.integerValue);
	}
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Operation monitoring - S3
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSUInteger)s3_didFailWithStatusCode:(NSNumber *)statusCode
{
	__block NSUInteger result = 0;
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		if (numbersAreEqual(statusCode, s3_successiveFail_statusCode))
		{
			if (s3_successiveFailCount < NSUIntegerMax)
				s3_successiveFailCount++;
		}
		else
		{
			s3_successiveFailCount = 1;
			s3_successiveFail_statusCode = statusCode;
		}
		
		result = s3_successiveFailCount;
		
	#pragma clang diagnostic pop
	}});
	
	return result;
}

- (void)s3_didSucceed
{
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		s3_successiveFailCount = 0;
		s3_successiveFail_statusCode = nil;
		
	#pragma clang diagnostic pop
	}});
}

- (NSUInteger)s3_successiveFailCount
{
	__block NSUInteger result = 0;
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		result = s3_successiveFailCount;
		
	#pragma clang diagnostic pop
	}});
	
	return result;
}

- (NSNumber *)s3_successiveFail_statusCode
{
	__block NSNumber *result = nil;
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		result = s3_successiveFail_statusCode;
		
	#pragma clang diagnostic pop
	}});
	
	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Operation monitoring - Polling
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSUInteger)polling_didFail
{
	__block NSUInteger result = 0;
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		if (polling_successiveFailCount < NSUIntegerMax)
			polling_successiveFailCount++;
		
		result = polling_successiveFailCount;
		
	#pragma clang diagnostic pop
	}});
	
	return result;
}

- (void)polling_didSucceed
{
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		polling_successiveFailCount = 0;
		
	#pragma clang diagnostic pop
	}});
}

- (NSUInteger)polling_successiveFailCount
{
	__block NSUInteger result = 0;
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		result = polling_successiveFailCount;
		
	#pragma clang diagnostic pop
	}});
	
	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Operation monitoring - S4
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSUInteger)s4_didFailWithExtStatusCode:(NSNumber *)extStatusCode
{
	__block NSUInteger result = 0;
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		if (numbersAreEqual(extStatusCode, s4_successivFail_extStatusCode))
		{
			if (s4_successiveFailCount < NSUIntegerMax)
				s4_successiveFailCount++;
		}
		else
		{
			s4_successiveFailCount = 1;
			s4_successivFail_extStatusCode = extStatusCode;
		}
		
		result = s4_successiveFailCount;
		
	#pragma clang diagnostic pop
	}});
	
	return result;
}

- (void)s4_didSucceed
{
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		s4_successiveFailCount = 0;
		s4_successivFail_extStatusCode = nil;
		
	#pragma clang diagnostic pop
	}});
}

- (NSUInteger)s4_successiveFailCount
{
	__block NSUInteger result = 0;
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		result = s4_successiveFailCount;
		
	#pragma clang diagnostic pop
	}});
	
	return result;
}

- (NSNumber *)s4_successiveFail_extStatusCode
{
	__block NSNumber *result = nil;
	dispatch_sync(queue, ^{ @autoreleasepool {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		result = s4_successivFail_extStatusCode;
		
	#pragma clang diagnostic pop
	}});
	
	return result;
}

@end
