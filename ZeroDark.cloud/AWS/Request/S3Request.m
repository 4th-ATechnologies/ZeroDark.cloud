#import "S3Request.h"
#import "AWSPayload.h"
#import "AWSURL.h"


@implementation S3Request

/**
 * Combines a baseURL with a relative path in a way that doesn't result in double-slashes (//) in the path.
**/
+ (NSURLComponents *)componentsWithRegion:(AWSRegion)region
                                   bucket:(NSString *)bucket
                                     path:(NSString *)path
                               queryItems:(NSArray<NSURLQueryItem *> *)queryItems
{
	NSURLComponents *urlComponents = [[NSURLComponents alloc] init];
	urlComponents.scheme = @"https";
	
#if 1
	// The dual stack solution is recommneded on macOS & iOS.
	// It supports both IPv4 & IPv6.
	//
	// http://docs.aws.amazon.com/AmazonS3/latest/dev/dual-stack-endpoints.html
	//
	urlComponents.host = [AWSRegions dualStackHostForRegion:region service:AWSService_S3];
#else
	urlComponents.host = [AWSRegions IPv4HostForRegion:region service:AWSService_S3];
#endif
	
	NSMutableString *fullPath = [NSMutableString stringWithCapacity:(1 + bucket.length + 1 + path.length)];
	[fullPath appendString:@"/"];
	[fullPath appendString:bucket];
	
	if (path.length > 0)
	{
		if (![path hasPrefix:@"/"])
			[fullPath appendString:@"/"];
		
		[fullPath appendString:path];
	}
	
	// The key & bucket values are required to be properly escaped.
	// Thus we don't perform additional escaping here.
	
	urlComponents.percentEncodedPath = fullPath;
	
	if (queryItems)
	{
		// This doesn't work :(
		//
		// Specifically, it doesn't appear to work when a query key/value contains a '+'.
		// We struggled with this when testing LIST BUCKET operations that have a continuation-token.
		//
		// Note: We experienced problems on macOS (but not iOS for some reason).
		//
	//	urlComponents.queryItems = queryItems;
		
		NSMutableString *queryString = [NSMutableString string];
		
		for (NSURLQueryItem *queryItem in queryItems)
		{
			NSString *name = [AWSURL urlEncodeQueryKeyOrValue:queryItem.name];
			NSString *value = [AWSURL urlEncodeQueryKeyOrValue:queryItem.value];
			
			if (queryString.length > 0)
				[queryString appendString:@"&"];
			
			[queryString appendString:name];
			if (value.length > 0) {
				[queryString appendString:@"="];
				[queryString appendString:value];
			}
		}
		
		urlComponents.percentEncodedQuery = queryString;
	}
	
	return urlComponents;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Bucket Requests
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

+ (NSMutableURLRequest *)bucketRequestWithRegion:(AWSRegion)region
                                          bucket:(NSString *)bucket
                                          method:(NSString *)method
                                      queryItems:(NSArray<NSURLQueryItem *> *)queryItems
                                outUrlComponents:(NSURLComponents **)outUrlComponents
{
	if (bucket == nil) return nil;
	
	NSURLComponents *components = [self componentsWithRegion:region bucket:bucket path:nil queryItems:queryItems];
	
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[components URL]];
	[request setHTTPMethod:method];
	
	if (outUrlComponents) *outUrlComponents = components;
	return request;
}

+ (NSMutableURLRequest *)getBucket:(NSString *)bucket
                          inRegion:(AWSRegion)region
                    withQueryItems:(NSArray<NSURLQueryItem *> *)queryItems
                  outUrlComponents:(NSURLComponents **)outUrlComponents
{
	return [self bucketRequestWithRegion:region
	                              bucket:bucket
	                              method:@"GET"
	                          queryItems:queryItems
	                    outUrlComponents:outUrlComponents];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Objects Requests
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

+ (NSMutableURLRequest *)objectRequestWithRegion:(AWSRegion)region
                                          bucket:(NSString *)bucket
                                          method:(NSString *)method
                                            path:(NSString *)path
                                      queryItems:(NSArray<NSURLQueryItem *> *)queryItems
                                outUrlComponents:(NSURLComponents **)outUrlComponents
{
	if (bucket == nil) return nil;
	if (path == nil) return nil;
	
	NSURLComponents *components = [self componentsWithRegion:region bucket:bucket path:path queryItems:queryItems];
	
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[components URL]];
	[request setHTTPMethod:method];
	
	if (outUrlComponents) *outUrlComponents = components;
	return request;
}

+ (NSMutableURLRequest *)headObject:(NSString *)path
                           inBucket:(NSString *)bucket
                             region:(AWSRegion)region
                   outUrlComponents:(NSURLComponents **)outUrlComponents
{
	return [self objectRequestWithRegion:region
	                              bucket:bucket
	                              method:@"HEAD"
	                                path:path
	                          queryItems:nil
	                    outUrlComponents:outUrlComponents];
}

+ (NSMutableURLRequest *)getObject:(NSString *)path
                          inBucket:(NSString *)bucket
                            region:(AWSRegion)region
                  outUrlComponents:(NSURLComponents **)outUrlComponents
{
	return [self objectRequestWithRegion:region
	                              bucket:bucket
	                              method:@"GET"
	                                path:path
	                          queryItems:nil
	                    outUrlComponents:outUrlComponents];
}

+ (NSMutableURLRequest *)putObject:(NSString *)path
                          inBucket:(NSString *)bucket
                            region:(AWSRegion)region
                  outUrlComponents:(NSURLComponents **)outUrlComponents
{
	return [self objectRequestWithRegion:region
	                              bucket:bucket
	                              method:@"PUT"
	                                path:path
	                          queryItems:nil
	                    outUrlComponents:outUrlComponents];
}

+ (NSMutableURLRequest *)deleteObject:(NSString *)path
                             inBucket:(NSString *)bucket
                               region:(AWSRegion)region
                     outUrlComponents:(NSURLComponents **)outUrlComponents
{
	return [self objectRequestWithRegion:region
	                              bucket:bucket
	                              method:@"DELETE"
	                                path:path
	                          queryItems:nil
	                    outUrlComponents:outUrlComponents];
}

+ (NSMutableURLRequest *)multiDeleteObjects:(NSArray<NSString *> *)keys
                                   inBucket:(NSString *)bucket
                                     region:(AWSRegion)region
                           outUrlComponents:(NSURLComponents **)outUrlComponents
{
	NSArray<NSURLQueryItem *> *queryItems = @[[NSURLQueryItem queryItemWithName:@"delete" value:nil]];
	
	NSMutableURLRequest *request =
	  [self objectRequestWithRegion:region
	                         bucket:bucket
	                         method:@"POST"
	                           path:@"/"
	                     queryItems:queryItems
	               outUrlComponents:outUrlComponents];
	
	NSMutableString *body = [NSMutableString string];
	
	[body appendString:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"];
	[body appendString:@"<DELETE>\n"];
	
	for (NSString *key in keys)
	{
		[body appendFormat:@" <Object><Key>%@</Key></Object>\n", key];
	}
	
	[body appendString:@"</DELETE>"];
	
	request.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];
	
	// Oddly, the Content-MD5 header is required for this request (even though sha-256 hash is provided via signature)
	
	NSString *md5Hash = [AWSPayload md5HashForPayload:request.HTTPBody];
	[request setValue:md5Hash forHTTPHeaderField:@"Content-MD5"];
	
	// macOS will automatically add the following incorrect HTTP header:
	// Content-Type: application/x-www-form-urlencoded
	//
	// So we explicitly set it here.
	
	[request setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];
	
	return request;
}

+ (NSMutableURLRequest *)copyObject:(NSString *)srcPath
                      toDestination:(NSString *)dstPath
                           inBucket:(NSString *)bucket
                             region:(AWSRegion)region
                   outUrlComponents:(NSURLComponents **)outUrlComponents
{
	NSMutableURLRequest *request =
	  [self objectRequestWithRegion:region
	                         bucket:bucket
	                         method:@"PUT"
	                           path:dstPath
	                     queryItems:nil
	               outUrlComponents:outUrlComponents];
	
	NSString *src = [[@"/" stringByAppendingString:bucket] stringByAppendingPathComponent:srcPath];
	[request setValue:src forHTTPHeaderField:@"x-amz-copy-source"];
	
	return request;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Multipart Uploads
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

+ (NSMutableURLRequest *)multipartInitiate:(NSString *)key
                                  inBucket:(NSString *)bucket
                                    region:(AWSRegion)region
                          outUrlComponents:(NSURLComponents **)outUrlComponents
{
	NSArray<NSURLQueryItem *> *queryItems = @[[NSURLQueryItem queryItemWithName:@"uploads" value:nil]];
	
	return [self objectRequestWithRegion:region
	                              bucket:bucket
	                              method:@"POST"
	                                path:key
	                          queryItems:queryItems
	                    outUrlComponents:outUrlComponents];
}

+ (NSMutableURLRequest *)multipartUpload:(NSString *)key
                            withUploadID:(NSString *)uploadID
                                    part:(NSUInteger)partNumber
                                inBucket:(NSString *)bucket
                                  region:(AWSRegion)region
                        outUrlComponents:(NSURLComponents **)outUrlComponents
{
	NSString *part = [NSString stringWithFormat:@"%llu", (unsigned long long)partNumber];
	
	NSArray<NSURLQueryItem *> *queryItems = @[
		[NSURLQueryItem queryItemWithName:@"partNumber" value:part],
		[NSURLQueryItem queryItemWithName:@"uploadId" value:uploadID]
	];
	
	return [self objectRequestWithRegion:region
	                              bucket:bucket
	                              method:@"PUT"
	                                path:key
	                          queryItems:queryItems
	                    outUrlComponents:outUrlComponents];
}

+ (NSMutableURLRequest *)multipartComplete:(NSString *)key
                              withUploadID:(NSString *)uploadID
                                     eTags:(NSArray<NSString*> *)eTags
                                  inBucket:(NSString *)bucket
                                    region:(AWSRegion)region
                          outUrlComponents:(NSURLComponents **)outUrlComponents
{
	NSArray<NSURLQueryItem *> *queryItems = @[[NSURLQueryItem queryItemWithName:@"uploadId" value:uploadID]];
	
	NSMutableURLRequest *request =
	  [self objectRequestWithRegion:region
	                         bucket:bucket
	                         method:@"POST"
	                           path:key
	                     queryItems:queryItems
	               outUrlComponents:outUrlComponents];
	
	NSMutableString *body = [NSMutableString string];
	
	[body appendString:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"];
	[body appendString:@"<CompleteMultipartUpload>\n"];
	
	NSUInteger part = 1; // multipart uses 1-based indexes
	for (NSString *eTag in eTags)
	{
		[body appendFormat:@" <Part><PartNumber>%llu</PartNumber><ETag>%@</ETag></Part>\n",
		                        (unsigned long long)part, eTag];
		
		part++;
	}
	
	[body appendString:@"</CompleteMultipartUpload>"];
	
	request.HTTPBody = [body dataUsingEncoding:NSUTF8StringEncoding];
	
	// macOS will automatically add the following incorrect HTTP header:
	// Content-Type: application/x-www-form-urlencoded
	//
	// So we explicitly set it here.
	
	[request setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];
	
	return request;
}

+ (NSMutableURLRequest *)multipartAbort:(NSString *)key
                           withUploadID:(NSString *)uploadID
                               inBucket:(NSString *)bucket
                                 region:(AWSRegion)region
                       outUrlComponents:(NSURLComponents **)outUrlComponents
{
	NSArray<NSURLQueryItem *> *queryItems = @[[NSURLQueryItem queryItemWithName:@"uploadId" value:uploadID]];
	
	return [self objectRequestWithRegion:region
	                              bucket:bucket
	                              method:@"DELETE"
	                                path:key
	                          queryItems:queryItems
	                    outUrlComponents:outUrlComponents];
}

@end
