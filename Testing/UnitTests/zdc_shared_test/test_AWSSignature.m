/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

#import <XCTest/XCTest.h>
#import <ZeroDarkCloud/ZeroDarkCloud.h>

@interface test_AWSSignature : XCTestCase

@end

@implementation test_AWSSignature

- (void)printURLRequest:(NSURLRequest *)request
{
	NSMutableString *dsc = [NSMutableString string];
	
	[dsc appendFormat:@"%@ %@ HTTP/X.Y\n", request.HTTPMethod, [request.URL path]];
	[dsc appendFormat:@"Host: %@\n", [request.URL host]];
	
	NSDictionary <NSString *,NSString *> *headers = request.allHTTPHeaderFields;
	[headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
		
		[dsc appendFormat:@"%@: %@\n", key, value];
	}];
	
	NSLog(@"\n%@\n ", dsc);
}

- (void)testExample1
{
	// This is an example from Amazon's documentation:
	// http://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-header-based-auth.html
	
	NSString *accessKeyID = @"AKIAIOSFODNN7EXAMPLE";
	NSString *secret = @"wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY";
	
	NSURL *url = [NSURL URLWithString:@"https://examplebucket.s3.amazonaws.com/test.txt"];
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
	request.HTTPMethod = @"GET";
	
	[request setValue:@"20130524T000000Z" forHTTPHeaderField:@"x-amz-date"];
	[request setValue:@"bytes=0-9" forHTTPHeaderField:@"Range"];
	
	[AWSSignature setContentTypeHeaderAutomatically:NO];
	[AWSSignature signRequest:request
	               withRegion:AWSRegion_US_East_1
	                  service:AWSService_S3
	              accessKeyID:accessKeyID
	                   secret:secret
	                  session:nil
	               payloadSig:nil];
	
	[self printURLRequest:request];
	
	NSString *authorization = [request valueForHTTPHeaderField:@"Authorization"];
	
	NSString *expected =
	  @"AWS4-HMAC-SHA256 "
	  @"Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request,"
	  @"SignedHeaders=host;range;x-amz-content-sha256;x-amz-date,"
     @"Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41";
	
	XCTAssert([authorization isEqualToString:expected]);
}

- (void)testExample2
{
	// This is an example from Amazon's documentation:
	// http://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-header-based-auth.html
	
	NSString *accessKeyID = @"AKIAIOSFODNN7EXAMPLE";
	NSString *secret = @"wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY";
	
	NSURL *url = [NSURL URLWithString:@"https://examplebucket.s3.amazonaws.com/test$file.text"];
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
	request.HTTPMethod = @"PUT";
	
	[request setValue:@"Fri, 24 May 2013 00:00:00 GMT" forHTTPHeaderField:@"Date"];
	[request setValue:@"20130524T000000Z" forHTTPHeaderField:@"x-amz-date"];
	[request setValue:@"REDUCED_REDUNDANCY" forHTTPHeaderField:@"x-amz-storage-class"];
	
	[AWSSignature setContentTypeHeaderAutomatically:NO];
	[AWSSignature signRequest:request
	               withRegion:AWSRegion_US_East_1
	                  service:AWSService_S3
	              accessKeyID:accessKeyID
	                   secret:secret
	                  session:nil
	               payloadSig:@"44ce7dd67c959e0d3524ffac1771dfbba87d2b6b4b4e99e42034a8b803f8b072"];
	
	[self printURLRequest:request];
	
	NSString *authorization = [request valueForHTTPHeaderField:@"Authorization"];
	
	NSString *expected =
	  @"AWS4-HMAC-SHA256 "
	  @"Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request,"
	  @"SignedHeaders=date;host;x-amz-content-sha256;x-amz-date;x-amz-storage-class,"
	  @"Signature=98ad721746da40c64f1a55b78f14c238d841ea1380cd77a1b5971af0ece108bd";
	
	XCTAssert([authorization isEqualToString:expected]);
}

- (void)testExample3
{
	// This is an example from Amazon's documentation:
	// http://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-header-based-auth.html
	
	NSString *accessKeyID = @"AKIAIOSFODNN7EXAMPLE";
	NSString *secret = @"wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY";
	
	NSURL *url = [NSURL URLWithString:@"https://examplebucket.s3.amazonaws.com/?lifecycle"];
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
	request.HTTPMethod = @"GET";
	
	[request setValue:@"20130524T000000Z" forHTTPHeaderField:@"x-amz-date"];
	
	[AWSSignature setContentTypeHeaderAutomatically:NO];
	[AWSSignature signRequest:request
	               withRegion:AWSRegion_US_East_1
	                  service:AWSService_S3
	              accessKeyID:accessKeyID
	                   secret:secret
	                  session:nil
	               payloadSig:nil];
	
	[self printURLRequest:request];
	
	NSString *authorization = [request valueForHTTPHeaderField:@"Authorization"];
	
	NSString *expected =
	  @"AWS4-HMAC-SHA256 "
	  @"Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request,"
	  @"SignedHeaders=host;x-amz-content-sha256;x-amz-date,"
	  @"Signature=fea454ca298b7da1c68078a5d1bdbfbbe0d65c699e0f91ac7a200a0136783543";
	
	XCTAssert([authorization isEqualToString:expected]);
}

- (void)testExample4
{
	// This is an example from Amazon's documentation:
	// http://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-header-based-auth.html
	
	NSString *accessKeyID = @"AKIAIOSFODNN7EXAMPLE";
	NSString *secret = @"wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY";
	
	NSURL *url = [NSURL URLWithString:@"https://examplebucket.s3.amazonaws.com/?max-keys=2&prefix=J"];
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
	request.HTTPMethod = @"GET";
	
	[request setValue:@"20130524T000000Z" forHTTPHeaderField:@"x-amz-date"];
	
	[AWSSignature setContentTypeHeaderAutomatically:NO];
	[AWSSignature signRequest:request
	               withRegion:AWSRegion_US_East_1
	                  service:AWSService_S3
	              accessKeyID:accessKeyID
	                   secret:secret
	                  session:nil
	               payloadSig:nil];
	
	[self printURLRequest:request];
	
	NSString *authorization = [request valueForHTTPHeaderField:@"Authorization"];
	
	NSString *expected =
	  @"AWS4-HMAC-SHA256 "
	  @"Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request,"
	  @"SignedHeaders=host;x-amz-content-sha256;x-amz-date,"
	  @"Signature=34b48302e7b5fa45bde8084f4b7868a86f0a534bc59db6670ed5711ef69dc6f7";
	
	XCTAssert([authorization isEqualToString:expected]);
}

@end
