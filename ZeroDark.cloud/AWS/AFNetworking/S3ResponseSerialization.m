#import "S3ResponseSerialization.h"
#import "S3ResponseParser.h"


@implementation S3ResponseSerialization

/**
 * S3 returns 2 different types of reponses:
 * - XML responses, which should be serialized via S3XMLResponseSerialization
 * - JSON response, which should be serialized via AFJSONResponseSerializer
 *
 * This method returns a compound serializer that supports both.
**/
+ (AFCompoundResponseSerializer *)serializer
{
	S3XMLResponseSerialization *xmlSerializer = [[S3XMLResponseSerialization alloc] init];
	S3BinaryResponseSerialization *binarySerializer = [[S3BinaryResponseSerialization alloc] init];
	AFJSONResponseSerializer *jsonSerializer = [[AFJSONResponseSerializer alloc] init];
	
	NSArray *serializers = @[ xmlSerializer, binarySerializer, jsonSerializer ];
	
	return [AFCompoundResponseSerializer compoundSerializerWithResponseSerializers:serializers];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation S3XMLResponseSerialization

- (instancetype)init
{
	if ((self = [super init]))
	{
		self.acceptableContentTypes = [[NSSet alloc] initWithObjects:@"application/xml", @"text/xml", nil];
	}
	return self;
}

- (id)responseObjectForResponse:(NSHTTPURLResponse *)response
                           data:(NSData *)data
                          error:(NSError *__autoreleasing *)error
{
	if (![self validateResponse:(NSHTTPURLResponse *)response data:data error:error]) {
		return nil;
	}
	
	return [S3ResponseParser parseXMLData:data];
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation S3BinaryResponseSerialization

- (instancetype)init
{
	if ((self = [super init]))
	{
		self.acceptableContentTypes = [[NSSet alloc] initWithObjects:@"application/octet-stream", nil];
	}
	return self;
}

- (id)responseObjectForResponse:(NSHTTPURLResponse *)response
                           data:(NSData *)data
                          error:(NSError *__autoreleasing *)error
{
	if (![self validateResponse:(NSHTTPURLResponse *)response data:data error:error]) {
		return nil;
	}
	
	return data;
}

@end
