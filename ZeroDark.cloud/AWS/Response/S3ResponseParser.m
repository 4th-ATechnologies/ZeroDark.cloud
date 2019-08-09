#import "S3ResponseParser.h"

#import "AWSDate.h"
#import "AWSNumber.h"
#import "S3ResponsePrivate.h"

#import <XMLDictionary/XMLDictionary.h>


@implementation S3ResponseParser

/**
 * Parses the given XML response from Amazon S3 (as raw NSData).
**/
+ (S3Response *)parseXMLData:(NSData *)data
{
	if (data == nil) return nil;
	
	S3Response *result = nil;
	
	XMLDictionaryParser *xmlParser = [[XMLDictionaryParser alloc] init];
	NSDictionary *dict = [xmlParser dictionaryWithData:data];
	if (dict)
	{
		NSString *type = [dict nodeName];
		
		if ([type isEqualToString:@"ListBucketResult"])
		{
			result = [self parseDict_ListBucketResult:dict];
		}
		else if ([type isEqualToString:@"InitiateMultipartUploadResult"])
		{
			result = [self parseDict_InitiateMultipartUploadResult:dict];
		}
	}
	
	return result;
}

+ (S3Response *)parseJSONData:(NSData *)data withType:(S3ResponseType)type
{
	id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
	if ([obj isKindOfClass:[NSDictionary class]])
	{
		return [self parseJSONDict:(NSDictionary *)obj withType:type];
	}
	else
	{
		return nil;
	}
}

+ (S3Response *)parseJSONDict:(NSDictionary *)dict withType:(S3ResponseType)type
{
	if (dict == nil) return nil;
	
	S3Response *result = nil;
	
	if (type == S3ResponseType_ListBucket)
	{
		result = [self parseDict_ListBucketResult:dict];
	}
	else if (type == S3ResponseType_InitiateMultipartUpload)
	{
		result = [self parseDict_InitiateMultipartUploadResult:dict];
	}
	
	return result;
}

// EXAMPLE RESPONSES:

// GET /?prefix=folder1
//
//   <?xml version="1.0" encoding="UTF-8"?>
//   <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
//     <Name>com.4th-a.testing</Name>
//     <Prefix>folder1</Prefix>
//     <Marker></Marker>
//     <MaxKeys>1000</MaxKeys>
//     <IsTruncated>false</IsTruncated>
//     <Contents>
//       <Key>folder1/</Key>
//       <LastModified>2016-03-27T16:02:45.000Z</LastModified>
//       <ETag>&quot;d41d8cd98f00b204e9800998ecf8427e&quot;</ETag>
//       <Size>0</Size>
//       <Owner>
//         <ID>e5a4b49b307ef350b1b01e91d0f890b263cce0890e4eec69d5003b51b29931c0</ID>
//         <DisplayName>vinnie</DisplayName>
//       </Owner>
//       <StorageClass>STANDARD</StorageClass>
//     </Contents>
//     <Contents>
//       <Key>folder1/IMG_6863.JPG</Key>
//       <LastModified>2016-03-27T16:05:06.000Z</LastModified>
//       <ETag>&quot;7dfa95b6a2ebc64c2fb4cf2a1f1ca726&quot;</ETag>
//       <Size>3646849</Size>
//       <Owner>
//         <ID>e5a4b49b307ef350b1b01e91d0f890b263cce0890e4eec69d5003b51b29931c0</ID>
//         <DisplayName>vinnie</DisplayName>
//       </Owner>
//       <StorageClass>STANDARD</StorageClass>
//     </Contents>
//   </ListBucketResult>

+ (S3Response *)parseDict_ListBucketResult:(NSDictionary *)dict
{
	S3Response_ListBucket *result = [[S3Response_ListBucket alloc] init];
	NSMutableArray<S3ObjectInfo *> *objectList = [[NSMutableArray alloc] init];
	
	// dict: {
	//   IsTruncated = false;
	//   MaxKeys = 1000;
	//   Name = "com.4th-a.robbie";
	//   Prefix = 00000000000000000000000000000000;
	//   "__name" = ListBucketResult;
	//   "_xmlns" = "http://s3.amazonaws.com/doc/2006-03-01/";
	// }
	
	id value;
	
	value = dict[@"MaxKeys"];
	if (value)
	{
		if ([value isKindOfClass:[NSNumber class]])
			result.maxKeys = [(NSNumber *)value unsignedIntegerValue];
		else if ([value isKindOfClass:[NSString class]])
			result.maxKeys = (NSUInteger)[(NSString *)value longLongValue];
	}
	
	value = dict[@"IsTruncated"];
	if (value)
	{
		if ([value isKindOfClass:[NSNumber class]])
			result.isTruncated = [(NSNumber *)value boolValue];
		else if ([value isKindOfClass:[NSString class]])
			result.isTruncated = [(NSString *)value boolValue];
	}
	
	value = dict[@"Prefix"];
	if (value && [value isKindOfClass:[NSString class]])
	{
		result.prefix = (NSString *)value;
	}
	
	value = dict[@"ContinuationToken"];
	if (value && [value isKindOfClass:[NSString class]])
	{
		result.prevContinuationToken = (NSString *)value;
	}
	
	value = dict[@"NextContinuationToken"];
	if (value && [value isKindOfClass:[NSString class]])
	{
		result.nextContinuationToken = (NSString *)value;
	}
	
	value = dict[@"Contents"];
	if (value)
	{
		if ([value isKindOfClass:[NSDictionary class]])
		{
			value = @[ value ];
		}
		
		if ([value isKindOfClass:[NSArray class]])
		{
			NSArray *contents = (NSArray *)value;
			for (value in contents)
			{
				if (![value isKindOfClass:[NSDictionary class]])
				{
					continue;
				}
				
				NSDictionary *objDict = (NSDictionary *)value;
				
				S3ObjectInfo *objInfo = [self parseObjectInfo:objDict];
				if (objInfo) {
					[objectList addObject:objInfo];
				}
			}
		}
	}
	
	result.objectList  = [objectList copy];
	
	S3Response *response = [[S3Response alloc] init];
	response.type = S3ResponseType_ListBucket;
	response.listBucket = result;
	
	return response;
}

+ (S3Response *)parseDict_InitiateMultipartUploadResult:(NSDictionary *)dict
{
	S3Response_InitiateMultipartUpload *result = [[S3Response_InitiateMultipartUpload alloc] init];
	
	// dict: {
	//   Bucket = "com.4th-a.users.abc123-def",
	//   Key = "staging/1/foo/bar",
	//   UploadId = "big long randome string"
	// }
	
	id value;
	
	value = dict[@"Bucket"];
	if (value && [value isKindOfClass:[NSString class]])
	{
		result.bucket = (NSString *)value;
	}
	
	value = dict[@"Key"];
	if (value && [value isKindOfClass:[NSString class]])
	{
		result.key = (NSString *)value;
	}
	
	value = dict[@"UploadId"];
	if (value && [value isKindOfClass:[NSString class]])
	{
		result.uploadID = (NSString *)value;
	}
	
	S3Response *response = [[S3Response alloc] init];
	response.type = S3ResponseType_InitiateMultipartUpload;
	response.initiateMultipartUpload = result;
	
	return response;
}

+ (nullable S3ObjectInfo *)parseObjectInfo:(NSDictionary *)dict
{
	id value = nil;
	
	NSString *key = nil;
	NSString *eTag = nil;
	NSDate *lastModified = nil;
	uint64_t size = 0;
	S3StorageClass storageClass = S3StorageClass_Standard;

	value = dict[@"Key"];
	if (value && [value isKindOfClass:[NSString class]])
	{
		key = (NSString *)value;
	}

	value = dict[@"ETag"];
	if (value && [value isKindOfClass:[NSString class]])
	{
		eTag = (NSString *)value;
		
		eTag = [eTag stringByRemovingPercentEncoding];
		
		NSCharacterSet *quotes = [NSCharacterSet characterSetWithCharactersInString:@"\""];
		eTag = [eTag stringByTrimmingCharactersInSet:quotes];
	}

	value = dict[@"LastModified"];
	if (value && [value isKindOfClass:[NSString class]])
	{
		lastModified = [AWSDate parseISO8601Timestamp:(NSString *)value];
	}

	value = dict[@"Size"];
	if (value)
	{
		if ([value isKindOfClass:[NSNumber class]]) {
			size = [(NSNumber *)value unsignedLongLongValue];
		}
		else if ([value isKindOfClass:[NSString class]]) {
			[AWSNumber parseUInt64:&size fromString:(NSString *)value];
		}
	}

	value = dict[@"StorageClass"];
	if (value && [value isKindOfClass:[NSString class]])
	{
		if ([(NSString *)value isEqualToString:@"STANDARD"])
		{
			storageClass = S3StorageClass_Standard;
		}
		else if ([(NSString *)value isEqualToString:@"STANDARD_IA"])
		{
			storageClass = S3StorageClass_InfrequentAccess;
		}
		else if ([(NSString *)value isEqualToString:@"REDUCED_REDUNDANCY"])
		{
			storageClass = S3StorageClass_ReducedRedundancy;
		}
		else if ([(NSString *)value isEqualToString:@"GLACIER"])
		{
			storageClass = S3StorageClass_Glacier;
		}
	}

	if (key && eTag && lastModified)
	{
		S3ObjectInfo *objInfo = [[S3ObjectInfo alloc] init];
		objInfo.key = key;
		objInfo.eTag = eTag;
		objInfo.lastModified = lastModified;
		objInfo.size = size;
		objInfo.storageClass = storageClass;
		
		return objInfo;
	}
	else
	{
		return nil;
	}
}

@end
