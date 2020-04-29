/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "JWTUtilities.h"

#import "NSError+ZeroDark.h"

@implementation JWTUtilities

+ (nullable NSDictionary *)payloadFromJWT:(NSString *)jwt error:(NSError *_Nullable *_Nullable)errorOut
{
	NSArray<NSString *> *comps = [jwt componentsSeparatedByString:@"."];
	
	if (comps.count != 3)
	{
		NSString *msg = @"The given string is not a JWT.";
		NSError *error = [NSError errorWithClass:[self class] code:400 description:msg];
		
		if (errorOut) *errorOut = error;
		return nil;
	}
	
	// comps[0] => header
	// comps[1] => payload
	// comps[2] => signature
	
	NSString *base64String = comps[1];
	
	// Convert from URL-safe base64 to normal base64
	base64String = [base64String stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
	base64String = [base64String stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
	
	// Add trailing =, or Apple's API's won't accept it
	NSUInteger padding = (base64String.length % 4);
	if (padding != 0)
	{
		base64String = [base64String stringByPaddingToLength: (base64String.length + padding)
		                                          withString: @"="
		                                     startingAtIndex: 0];
	}
	
	
	NSData *jsonData =
	  [[NSData alloc] initWithBase64EncodedString: base64String
	                                      options: NSDataBase64DecodingIgnoreUnknownCharacters];
	
	if (jsonData == nil)
	{
		NSString *msg = @"The given string doesn't contain base64.";
		NSError *error = [NSError errorWithClass:[self class] code:400 description:msg];
		
		if (errorOut) *errorOut = error;
		return nil;
	}
	
	id obj = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
	if (![obj isKindOfClass:[NSDictionary class]])
	{
		NSString *msg = @"The given string doesn't contain valid JSON.";
		NSError *error = [NSError errorWithClass:[self class] code:400 description:msg];
		
		if (errorOut) *errorOut = error;
		return nil;
	}
	
	NSDictionary *payload = (NSDictionary *)obj;
	
	if (errorOut) *errorOut = nil;
	return payload;
}

/**
 * See header file for description.
 */
+ (nullable NSDate *)expireDateFromJWT:(NSString *)jwt error:(NSError *_Nullable *_Nullable)errorOut
{
	NSDictionary *payload = [self payloadFromJWT:jwt error:errorOut];
	if (payload == nil) {
		return nil;
	}
	
	id timestamp = payload[@"exp"];
	if (![timestamp isKindOfClass:[NSNumber class]])
	{
		NSString *msg = @"The JSON doesn't contain a valid 'exp' value.";
		NSError *error = [NSError errorWithClass:[self class] code:400 description:msg];
		
		if (errorOut) *errorOut = error;
		return nil;
	}
	
	NSDate *result = [NSDate dateWithTimeIntervalSince1970:[(NSNumber *)timestamp doubleValue]];
	
	if (errorOut) *errorOut = nil;
	return result;
}

/**
 * See header file for description.
 */
+ (nullable NSString *)issuerFromJWT:(NSString *)jwt error:(NSError *_Nullable *_Nullable)errorOut
{
	NSDictionary *payload = [self payloadFromJWT:jwt error:errorOut];
	if (payload == nil) {
		return nil;
	}
	
	id issuer = payload[@"iss"];
	if (![issuer isKindOfClass:[NSString class]])
	{
		NSString *msg = @"The JSON doesn't contain a valid 'iss' value.";
		NSError *error = [NSError errorWithClass:[self class] code:400 description:msg];
		
		if (errorOut) *errorOut = error;
		return nil;
	}
	
	NSString *result = (NSString *)issuer;
	
	if (errorOut) *errorOut = nil;
	return result;
}

@end
