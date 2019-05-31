#import "AWSSignature.h"

#import "AWSDate.h"
#import "AWSPayload.h"
#import "NSData+AWSUtilities.h"

#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonHMAC.h>
#import <stdatomic.h>

#if DEBUG
#define USE_UNSECURE_HTTP 0 // for debugging via packet analyzer
#endif

@implementation AWSSignature

static atomic_bool setContentTypeHeaderAutomatically = 1;

+ (NSData *)SHA256Hash:(NSString *)string
{
	NSData *dataToHash = [string dataUsingEncoding:NSUTF8StringEncoding];
	
	CC_SHA256_CTX ctx;
	CC_SHA256_Init(&ctx);
	
	CC_SHA256_Update(&ctx, dataToHash.bytes, (CC_LONG)dataToHash.length);
	
	int hashLength = CC_SHA256_DIGEST_LENGTH;
	uint8_t hashBytes[hashLength];
	
	CC_SHA256_Final(hashBytes, &ctx);
	
	return [NSData dataWithBytes:(void *)hashBytes length:hashLength];
}

+ (NSData *)HMACSHA256Hash:(NSString *)string withKey:(NSData *)key
{
	NSData *dataToHash = [string dataUsingEncoding:NSUTF8StringEncoding];
	
	CCHmacContext context;
	
	CCHmacInit(&context, kCCHmacAlgSHA256, key.bytes, key.length);
	CCHmacUpdate(&context, dataToHash.bytes, dataToHash.length);
	
	int hmacHashLength = CC_SHA256_DIGEST_LENGTH;
	uint8_t hmacHash[hmacHashLength];
	
	CCHmacFinal(&context, hmacHash);
	
	return [NSData dataWithBytes:(void *)hmacHash length:hmacHashLength];
}

+ (NSString *)uriEncoded:(NSString *)unencodedString isCanonicalURI:(BOOL)isCanonicalURI
{
	// Check for nil or empty string.
	// Always return an empty string in this case.
	
	if (unencodedString.length == 0) return @"";
	
	// From Amazon's docs:
	//
	// URI encode every byte. UriEncode() must enforce the following rules:
	//
	// - URI encode every byte except the unreserved characters: 'A'-'Z', 'a'-'z', '0'-'9', '-', '.', '_', and '~'.
	// - The space character is a reserved character and must be encoded as "%20" (and not as "+").
	// - Each URI encoded byte is formed by a '%' and the two-digit hexadecimal value of the byte.
	// - Letters in the hexadecimal value must be uppercase, for example "%1A".
	// - Encode the forward slash character, '/', everywhere except in the object key name.
	//   For example, if the object key name is photos/Jan/sample.jpg, the forward slash in the key name is not encoded.
	
	NSString *allowedChars = nil;
	
	if (isCanonicalURI)
		allowedChars = @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/";
	else
		allowedChars = @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~";
	
	NSCharacterSet *charset = [NSCharacterSet characterSetWithCharactersInString:allowedChars];
	
	NSString *encodedString = [unencodedString stringByAddingPercentEncodingWithAllowedCharacters:charset];
	return encodedString;
}

+ (NSString *)credentialWithAccessKeyID:(NSString *)accessKeyID
                                   date:(NSDate *)date
                                 region:(AWSRegion)region
                                service:(AWSService)service
{
	// From the docs:
	//
	// Your access key ID and the scope information,
	// which includes the date, region, and service that were used to calculate the signature.
	//
	// This string has the following form:
	//
	// <your-access-key-id>/<date>/<aws-region>/<aws-service>/aws4_request
	//
	// Where:
	// <date> value is specified using YYYYMMDD format.
	// <aws-service> value is s3 when sending request to Amazon S3.
	
	NSString *timestamp = [AWSDate shortTimestampFromDate:date];
	NSString *aws_region = [AWSRegions shortNameForRegion:region];
	NSString *aws_service = [AWSServices shortNameForService:service];
	
	return [NSString stringWithFormat:@"%@/%@/%@/%@/aws4_request", accessKeyID, timestamp, aws_region, aws_service];
}

/**
 * See header file for description.
 */
+ (BOOL)signRequest:(NSMutableURLRequest *)request
         withRegion:(AWSRegion)region
            service:(AWSService)service
        accessKeyID:(NSString *)accessKeyID
             secret:(NSString *)secret
            session:(nullable NSString *)session
{
	NSString *payloadSig = nil;
	
	NSData *body = request.HTTPBody;
	if (body) {
		payloadSig = [AWSPayload signatureForPayload:body];
	}
	
	return [self signRequest:request
	              withRegion:region
	                 service:service
	             accessKeyID:accessKeyID
	                  secret:secret
	                 session:session
	              payloadSig:payloadSig];
}

/**
 * See header file for description.
 */
+ (BOOL)signRequest:(NSMutableURLRequest *)request
         withRegion:(AWSRegion)region
            service:(AWSService)service
        accessKeyID:(NSString *)accessKeyID
             secret:(NSString *)secret
            session:(nullable NSString *)session
         payloadSig:(nullable NSString *)sha256HashInHex // <- MUST be in lowercase hex
{
	if (request == nil) return NO;
	if (region == AWSRegion_Invalid) return NO;
	if (service == AWSService_Invalid) return NO;
	if (accessKeyID == nil) return NO;
	if (secret == nil) return NO;
	
	NSString *aws_region = [AWSRegions shortNameForRegion:region];
	NSString *aws_service = [AWSServices shortNameForService:service];
	
	// Set the required 'x-amz-content-sha256' header value.
	// This header value needs to be included in the signature (calculated below).
	
	if (sha256HashInHex == nil)
	{
		// If there is no payload in the request, you compute a hash of the empty string as follows:
		// Hex(SHA256Hash(""))
		//
		// The hash returns the following value:
		// e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
		
		sha256HashInHex = @"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
	}
	
	if ([request valueForHTTPHeaderField:@"x-amz-content-sha256"] == nil)
	{
		[request setValue:sha256HashInHex forHTTPHeaderField:@"x-amz-content-sha256"];
	}
	
	// If using temporary credentials, set the 'x-amz-security-token' header value.
	// This header value needs to be included in the signature (calculated below).
	
	if (session)
	{
		[request setValue:session forHTTPHeaderField:@"x-amz-security-token"];
	}
	
	// Set the 'Content-Type' header (if not explicitly set already).
	//
	// This actually appears to be required on macOS.
	// Here's the situation:
	//
	// There are some queries that are particularly problematic.
	// In particular, if a query parameter contains a '+', then we run into trouble.
 	// The easiest way to test this is to perform a LIST BUCKET operation with a continuation-token parameter.
	//
	// Note: Not all continuation-tokens have a '+' character. So if you're testing this, be sure to ensure it does.
	//
	// Here's what seems to happen:
	// (Again, only on macOS. For some reason it doesn't seem to affect iOS.)
	//
	//   If URL has a query parameter with a '+', then NSURLSession (on macOS) will automatically
	//   percent-encode it to a '%20' before sending it out on the network. I used tcpdump to confirm this.
	//
	//   And this, in turn, breaks our signature. Because AWS will calculate the signature using the percent-encoded URL
	//   (with '%20' in the string). And will then give us an InvalidSignature error.
	//
	//   We can get around this problem by percent-encoding the '+' to '%20' ourself here.
	//   This fixes the InvalidSignature problem, but doesn't help because then S3 gives us
	//   a "Continuation-Token not found" error.
	//
	//   The solution appears to be setting the 'Content-Type' header to 'application/x-www-form-urlencoded'.
	//   Why does this work exactly ?
	//   This StackOverflow post seems to have the answer:
	//   https://stackoverflow.com/a/40292260/43522
	//
	//   "Space characters may only be encoded as "+" in one context: application/x-www-form-urlencoded key-value pairs."
	//
	//   So it would seem that NSURLSession is just adhering strictly to the spec.
	//   And we have to explicitly tell it that plus signs in the query string are OK.
	
	if (atomic_load(&setContentTypeHeaderAutomatically) != 0)
	{
		if ([request valueForHTTPHeaderField:@"Content-Type"] == nil)
		{
			[request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
		}
	}
	
	// Figure out the request's date
	//
	// From the docs:
 	// http://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-auth-using-authorization-header.html
	//
	//   Upon receiving the request, Amazon S3 re-creates the string to sign using information
	//   in the Authorization header and the date header. It then verifies with authentication
	//   service the signatures match. The request date can be specified by using either the
	//   HTTP Date or the x-amz-date header. If both headers are present, x-amz-date takes precedence.
	//
	// Important:
	//
	//   In practice, Amazon only seems to accept dates in ISO 8601 format.
	
	NSDate *date = nil;
	
	NSString *timestamp = [request valueForHTTPHeaderField:@"x-amz-date"];
	if (timestamp == nil)
		timestamp = [request valueForHTTPHeaderField:@"Date"];
	
	if (timestamp)
	{
		date = [AWSDate parseTimestamp:timestamp];
		
		if (date == nil)
		{
			// We require the date in order to calculate the signature.
			// But the specified value seems to be bad.
			// So we're going to be forced to override it.
			
			[request setValue:nil forHTTPHeaderField:@"x-amz-date"];
			[request setValue:nil forHTTPHeaderField:@"Date"];
		}
	}
	
	if (date == nil)
	{
		// Date wasn't specified, so we get to take the easy route, and add it ourself.
		
		date = [NSDate date];
		[request setValue:[AWSDate ISO8601TimestampFromDate:date] forHTTPHeaderField:@"x-amz-date"];
	}
	
	// Edge case:
	//
	// URL = https://s3-us-west-2.amazonaws.com/com.4th-a.user.robbie/?delete
	//
	// URL.path           = "/com.4th-a.robbie"  : Incorrect: Missing trailing slash
	// URLComponents.path = "/com.4th-a.robbie/" : Correct
	
	NSURLComponents *urlComponents = [NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
	
	NSString *httpMethod = [request HTTPMethod];
	
	NSString *canonicalURI = nil;
	if (service == AWSService_S3)
	{
		// From S3, the URL's path should be decoded first (percent encoding removed) and then URI encoded.
		//
		// I.e. "/foo%3Abar" -> "/foo:bar" -> "foo%3Abar"
		//       original        decoded       canonical
		
		NSString *path = urlComponents.path; // <- decodes for us
		canonicalURI = [self uriEncoded:path isCanonicalURI:YES];
	}
	else
	{
		// For every other service, the URL's path should be double URI encoded.
		//
		// I.e. "/foo%3Abar" -> "foo%253Abar"
		//       original        canonical
		
		NSString *path = urlComponents.percentEncodedPath; // <- leaves encoding
		canonicalURI = [self uriEncoded:path isCanonicalURI:YES];
	}
	
	// CanonicalQueryString specifies the URI-encoded query string parameters.
	// You URI-encode name and values individually. You must also sort the parameters in the canonical
	// query string alphabetically by key name. The sorting occurs after encoding.
	
	NSString *canonicalQueryString = @"";
	if (urlComponents.query.length > 0)
	{
		NSArray<NSURLQueryItem *> *queryItems = urlComponents.queryItems;
		
		NSMutableDictionary *encodedQueryItems = [NSMutableDictionary dictionaryWithCapacity:queryItems.count];
		NSMutableArray *encodedQueryItemKeys = [NSMutableArray arrayWithCapacity:queryItems.count];
		
		NSUInteger strCapacity = 0;
		
		for (NSURLQueryItem *queryItem in queryItems)
		{
			NSString *key = [self uriEncoded:queryItem.name isCanonicalURI:NO];
			NSString *value = [self uriEncoded:queryItem.value isCanonicalURI:NO];
			
			encodedQueryItems[key] = value;
			[encodedQueryItemKeys addObject:key];
			
			strCapacity += (key.length + 1 + value.length + 1);
		}
		
		[encodedQueryItemKeys sortUsingSelector:@selector(compare:)];
		
		NSMutableString *str = [NSMutableString stringWithCapacity:strCapacity];
		for (NSString *key in encodedQueryItemKeys)
		{
			NSString *value = encodedQueryItems[key];
			
			if (str.length > 0)
				[str appendFormat:@"&%@=%@", key, value];
			else
				[str appendFormat:@"%@=%@", key, value];
		}
		
		canonicalQueryString = str;
	}
	
	// CanonicalHeaders is a list of request headers with their values.
	// Individual header name and value pairs are separated by the newline character ("\n").
	// Header names must be in lowercase. You must sort the header names alphabetically to construct the string.
	//
	// SignedHeaders is an alphabetically sorted, semicolon-separated list of lowercase request header names.
	// The request headers in the list are the same headers that you included in the CanonicalHeaders string.
	
	NSString *canonicalHeaders = @"";
	NSString *signedHeaders = @"";
	
	NSMutableDictionary <NSString *,NSString *> *headers = [request.allHTTPHeaderFields mutableCopy];
	
	if ([request valueForHTTPHeaderField:@"Host"] == nil)
	{
		headers[@"Host"] = ([request.URL host] ?: @"");
	}
	
	if (headers.count > 0)
	{
		NSCharacterSet *whitespace = [NSCharacterSet whitespaceCharacterSet];
		
		NSMutableDictionary *encodedHeaders = [NSMutableDictionary dictionaryWithCapacity:headers.count];
		NSMutableArray *encodedHeaderKeys = [NSMutableArray arrayWithCapacity:headers.count];
		
		__block NSUInteger str_canonicalHeaders_capacity = 0;
		__block NSUInteger str_signedHeaders_capacity = 0;
		
		[headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
			
			NSString *encodedKey = [key lowercaseString];
			NSString *encodedValue = [value stringByTrimmingCharactersInSet:whitespace];
			
			encodedHeaders[encodedKey] = encodedValue;
			[encodedHeaderKeys addObject:encodedKey];
			
			str_canonicalHeaders_capacity += (encodedKey.length + 1 + encodedValue.length + 1);
			str_signedHeaders_capacity += (encodedKey.length + 1);
		}];
		
		[encodedHeaderKeys sortUsingSelector:@selector(compare:)];
		
		NSMutableString *str_canonicalHeaders = [NSMutableString stringWithCapacity:str_canonicalHeaders_capacity];
		NSMutableString *str_signedHeaders = [NSMutableString stringWithCapacity:str_signedHeaders_capacity];
		
		for (NSString *key in encodedHeaderKeys)
		{
			NSString *value = headers[key];
			
			[str_canonicalHeaders appendFormat:@"%@:%@\n", key, value];
			
			if (str_signedHeaders.length > 0)
				[str_signedHeaders appendFormat:@";%@", key];
			else
				[str_signedHeaders appendString:key];
		}
		
		canonicalHeaders = str_canonicalHeaders;
		signedHeaders = str_signedHeaders;
	}
	
	// HashedPayload is the hexadecimal value of the SHA256 hash of the request payload.
	//
	// Hex(SHA256Hash(<payload>)
	//
	// If there is no payload in the request, you compute a hash of the empty string as follows:
	// Hex(SHA256Hash(""))
	//
	// The hash returns the following value:
	// e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
	
	NSString *hashedPayload = nil;
	
	if (sha256HashInHex)
		hashedPayload = sha256HashInHex;
	else
		hashedPayload = @"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
	
	// The canonical request format:
	//
	// <HTTPMethod>\n
	// <CanonicalURI>\n
	// <CanonicalQueryString>\n
	// <CanonicalHeaders>\n
	// <SignedHeaders>\n
	// <HashedPayload>
	
	NSString *canonicalRequest =
	  [NSString stringWithFormat:@"%@\n%@\n%@\n%@\n%@\n%@",
	    httpMethod,
	    canonicalURI,
	    canonicalQueryString,
	    canonicalHeaders,
	    signedHeaders,
	    hashedPayload];
	
	// Scope binds the resulting signature to a specific date, an AWS region, and a service.
	// Thus, your resulting signature will work only in the specific region and for a specific service.
	// The signature is valid for seven days after the specified date.
	//
	// date.Format(<YYYYMMDD>) + "/" + <region> + "/" + <service> + "/aws4_request"
	
	NSString *shortTimestamp = [AWSDate shortTimestampFromDate:date];
	
	NSString *scope = [NSString stringWithFormat:@"%@/%@/%@/aws4_request", shortTimestamp, aws_region, aws_service];
	
	// Create a String to Sign
	//
	// The string to sign is a concatenation of the following strings:
	//
	// "AWS4-HMAC-SHA256" + "\n" +
	// timeStampISO8601Format + "\n" +
	// <Scope> + "\n" +
	// Hex(SHA256Hash(<CanonicalRequest>))
	
	NSString *iso8601Timestamp = [AWSDate ISO8601TimestampFromDate:date];
	
	NSData *canonicalRequestHash = [self SHA256Hash:canonicalRequest];
	NSString *canonicalRequestHashHex = [canonicalRequestHash lowercaseHexString];
	
	NSString *stringToSign =
	  [NSString stringWithFormat:@"AWS4-HMAC-SHA256\n%@\n%@\n%@",
	    iso8601Timestamp,
	    scope,
	    canonicalRequestHashHex];
	
	// Derive the signing key.
	//
	// To do this, use your secret access key to create a series of hash-based message authentication codes (HMACs).
	// This is shown in the following pseudocode, where HMAC(key, data) represents an HMAC-SHA256 function that
	// returns output in binary format. The result of each hash function becomes input for the next one.
	//
	// Pseudocode for deriving a signing key
	//
	// kSecret = "AWS4" + <Your AWS Secret Access Key>
	// kDate = HMAC(kSecret, Date)
	// kRegion = HMAC(kDate, Region)
	// kService = HMAC(kRegion, Service)
	// kSigning = HMAC(kService, "aws4_request")
	
	NSData *kSecret = [[@"AWS4" stringByAppendingString:secret] dataUsingEncoding:NSUTF8StringEncoding];
	
	NSData *kDate = [self HMACSHA256Hash:shortTimestamp withKey:kSecret];
	NSData *kRegion = [self HMACSHA256Hash:aws_region withKey:kDate];
	NSData *kService = [self HMACSHA256Hash:aws_service withKey:kRegion];
	NSData *kSigning = [self HMACSHA256Hash:@"aws4_request" withKey:kService];
	
	// The final signature is the HMAC-SHA256 hash of the string to sign, using the signing key as the key.
	
	NSData *signatureData = [self HMACSHA256Hash:stringToSign withKey:kSigning];
	NSString *signature = [signatureData lowercaseHexString];
	
	// The following is an example of the Authorization header value.
	// Line breaks are added to this example for readability:
	//
	// Authorization: AWS4-HMAC-SHA256
	// Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request,
	// SignedHeaders=host;range;x-amz-date,
	// Signature=fe5f80f77d5fa3beca038a248ff027d0445342fe2855ddc963176630326f1024
	
	NSString *credential = [self credentialWithAccessKeyID:accessKeyID date:date region:region service:service];
	
	NSString *authorization =
	  [NSString stringWithFormat:@"AWS4-HMAC-SHA256 Credential=%@,SignedHeaders=%@,Signature=%@",
	    credential,
	    signedHeaders,
	    signature];
	
	[request setValue:authorization forHTTPHeaderField:@"Authorization"];
	
	return YES;
}

/**
 * See header file for description.
 */
+ (void)setContentTypeHeaderAutomatically:(BOOL)flag
{
	atomic_store(&setContentTypeHeaderAutomatically, (flag ? 1 : 0));
}

@end
