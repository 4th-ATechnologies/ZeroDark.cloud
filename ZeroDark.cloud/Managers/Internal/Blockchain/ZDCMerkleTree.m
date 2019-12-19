/**
 * ZeroDark.cloud
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "ZDCMerkleTree.h"

#import "NSData+AWSUtilities.h"
#import "NSError+ZeroDark.h"
#import "NSString+S4.h"

#import <S4Crypto/S4Crypto.h>

// Example merkleTree file:
//
// {
//   merkle = {
//     174d1a20dd791e36cba6e4c5ce3933e4bfeeb894c0d77673c2dab6405332b468 = {
//       left = 4a6ceaf3f814800451dd3b907bc1a0a27503552615be3ed5b5f040df7f4e0c98;
//       level = 1;
//       parent = cd59b7bda6dc1dd82cb173d0cdfa408db30e9a747d4366eb5b60597899eb69c1;
//       right = 724b0761a18362ead9b48ae1da67a5f6e1580db546871f6e6527d5294adb1d91;
//       type = node;
//     };
//     21ac12d16f555b37276a2a8ec6c504fb302101102a89858286c77491d665ffc8 =         {
//       left = data;
//       level = 0;
//       parent = 71c4a93b3fd4898a2eb8794cd7f854a95360eedba29fc3986d0bb819448a42a8;
//       right = data;
//       type = leaf;
//     };
//     4a6ceaf3f814800451dd3b907bc1a0a27503552615be3ed5b5f040df7f4e0c98 =         {
//       left = data;
//       level = 0;
//       parent = 174d1a20dd791e36cba6e4c5ce3933e4bfeeb894c0d77673c2dab6405332b468;
//       right = data;
//       type = leaf;
//     };
//     71c4a93b3fd4898a2eb8794cd7f854a95360eedba29fc3986d0bb819448a42a8 =         {
//       left = 21ac12d16f555b37276a2a8ec6c504fb302101102a89858286c77491d665ffc8;
//       level = 1;
//       parent = cd59b7bda6dc1dd82cb173d0cdfa408db30e9a747d4366eb5b60597899eb69c1;
//       right = 21ac12d16f555b37276a2a8ec6c504fb302101102a89858286c77491d665ffc8;
//       type = node;
//     };
//     724b0761a18362ead9b48ae1da67a5f6e1580db546871f6e6527d5294adb1d91 =         {
//       left = data;
//       level = 0;
//       parent = 174d1a20dd791e36cba6e4c5ce3933e4bfeeb894c0d77673c2dab6405332b468;
//       right = data;
//       type = leaf;
//     };
//     cd59b7bda6dc1dd82cb173d0cdfa408db30e9a747d4366eb5b60597899eb69c1 =         {
//       left = 174d1a20dd791e36cba6e4c5ce3933e4bfeeb894c0d77673c2dab6405332b468;
//       level = 2;
//       parent = root;
//       right = 71c4a93b3fd4898a2eb8794cd7f854a95360eedba29fc3986d0bb819448a42a8;
//       type = root;
//     };
//     hashalgo = sha256;
//     leaves = 3;
//     levels = 3;
//     root = cd59b7bda6dc1dd82cb173d0cdfa408db30e9a747d4366eb5b60597899eb69c1;
//   };
//   values = (
//     "{\"userID\":\"dpb6rdqdmiw5q9fawycrokrwrqfiq5kp\",\"pubKey\":\"BBOWJpL+t9ya8AVIV6mpymv8pXSvy2JC9aWutYPPrDoo7+YtF+LpKyYCAQb13DsfeGQ6aVodlAiZ4XZPHlSoFiuzjcBcT23sNEh4vsTfjLu2Si1qGnsY+2qhlJH5ffakm380tvKKBsgA\",\"keyID\":\"loKQlyqSK8rQq7RYhvuh1Q==\"}",
//     "{\"userID\":\"ir9y16sbj94euj7yeaxrknuzwehyomgn\",\"pubKey\":\"BDN5xU9xKeXKIGaKSwL2bxx2i58KEaDtj0ibNe8/MIkYoAhlXHfa93gKA52cv/LjDkmU+S4lrC3CuYk3ltAFByMaBqBRVOiaKQ2THOGxXb9CWny3WzbI+bzYVxTugdOCkZp7UOQx+sJA\",\"keyID\":\"heHiHlMWHg/j1t/i4Ewo+w==\"}",
//     "{\"userID\":\"x7axsid774yzttdxj5ugig1ughfg33is\",\"pubKey\":\"BCzJZc1QkGaOeRF5+yCgk3A6mvHj1e2A8OPNzO0ofUHsax5wIZAhVev48vdMSr86v8QUeDcZlS6vmI8ITNNhajP751qm/ODXmGuMkaRSs6tdviO+7YRYkspnS4T3izt5+UeEl6LQ+oey\",\"keyID\":\"8BCIJdaUuMzbfAdhxpsloA==\"}"
//   );
//   lookup = {
//     dpb6rdqdmiw5q9fawycrokrwrqfiq5kp = 0;
//     ir9y16sbj94euj7yeaxrknuzwehyomgn = 1;
//     x7axsid774yzttdxj5ugig1ughfg33is = 2;
//   };
// }

@implementation ZDCMerkleTree {
	NSDictionary *file;
}

/**
 * See header file for description.
 */
+ (nullable instancetype)parseFile:(NSDictionary *)file error:(NSError *_Nullable *_Nullable)outError
{
	NSError *error = nil;
	ZDCMerkleTree *result = nil;
	
	NSString *errMsg = nil;
	id value = nil;
	
	if (![file isKindOfClass:[NSDictionary class]]) {
		errMsg = @"File doesn't appear to be a JSON dictionary";
		goto done;
	}
	
	value = file[@"merkle"];
	if (![value isKindOfClass:[NSDictionary class]]) {
		errMsg = @"Invalid JSON: missing/invalid key: 'merkle'";
		goto done;
	}
	
	value = file[@"values"];
	if ([value isKindOfClass:[NSArray class]])
	{
		// Every value should be a string
		//
		for (NSString *str in (NSArray *)value)
		{
			if (![str isKindOfClass:[NSString class]])
			{
				errMsg = @"Invalid JSON: 'values' array has non-string entry";
				goto done;
			}
		}
	}
	else
	{
		errMsg = @"Invalid JSON: missing/invalie key: 'values'";
		goto done;
	}
	
	value = file[@"lookup"];
	if ([value isKindOfClass:[NSDictionary class]])
	{
		// Every value should be a string/number pair
		//
		NSDictionary *lookup = (NSDictionary *)value;
		
		for (NSString *userID in lookup)
		{
			NSNumber *index = lookup[userID];
			
			if (![userID isKindOfClass:[NSString class]])
			{
				errMsg = @"Invalid JSON: 'lookup' map has non-string key";
				goto done;
			}
			if (![index isKindOfClass:[NSNumber class]])
			{
				errMsg = @"Invalid JSON: 'lookup' map has non-number value";
				goto done;
			}
		}
	}
	else
	{
		errMsg = @"Invalid JSON: missing/invalie key: 'lookup'";
		goto done;
	}
	
done:
	
	if (errMsg)
	{
		error = [NSError errorWithClass:[self class] code:0 description:errMsg];
	}
	else
	{
		result = [[ZDCMerkleTree alloc] init];
		result->file = [file copy];
	}
	
	if (outError) *outError = error;
	return result;
}

/**
 * See header file for description.
 */
- (BOOL)hashAndVerify:(NSError **)outError
{
	NSError *error = nil;
	NSString *errMsg = nil;
	BOOL result = NO;
	
	NSDictionary *merkle = file[@"merkle"];
	NSString *hashName = merkle[@"hashalgo"];
	
	HASH_Algorithm hashAlgo = kHASH_Algorithm_Invalid;
	NSArray<NSString *> *values = nil;
	NSMutableArray<NSString *> *queue;
	NSMutableArray<NSString *> *nextLevel;
	
	if ([hashName isKindOfClass:[NSString class]])
	{
		if([hashName isEqualToString:@"sha256"])
		{
			hashAlgo = kHASH_Algorithm_SHA256;
		}
		else if ([hashName isEqualToString:@"sha512"])
		{
			hashAlgo = kHASH_Algorithm_SHA512;
		}
	}

	if (hashAlgo == kHASH_Algorithm_Invalid)
	{
		errMsg = @"Unsupported hash algorithm";
		goto done;
	}
	
	values = file[@"values"];
	queue = [NSMutableArray arrayWithCapacity:values.count];
	
	for (NSString *value in values)
	{
		NSData *hash = [value hashWithAlgorithm:hashAlgo error:&error];
		if (error) goto done;

		[queue addObject:[hash lowercaseHexString]];
	}
	
	nextLevel = [NSMutableArray arrayWithCapacity:queue.count];
	
	while (queue.count > 1)
	{
		NSString *left = [queue firstObject];
		[queue removeObjectAtIndex:0];
		
		NSString *right = [queue firstObject];
		if (right) {
			[queue removeObjectAtIndex:0];
		} else {
			// If there are an odd number of leaves (only one left),
			// concatenate it with itself, and hash that.
			right = left;
		}
		
		NSData *hash = [[left stringByAppendingString:right] hashWithAlgorithm:hashAlgo error:&error];
		if (error) goto done;

		[nextLevel insertObject:[hash lowercaseHexString] atIndex:0];
		
		// Maybe go to the next level of the tree.
		//
		if ((queue.count == 0) && (nextLevel.count >= 2))
		{
			NSMutableArray *temp = queue;
			[temp removeAllObjects];
			
			queue = nextLevel;
			nextLevel = temp;
		}
	}
	
	{ // scoping
		
		NSString *calculatedRoot = [nextLevel firstObject];
		NSString *reportedRoot = [self rootHash];
		
		if (![calculatedRoot isEqual:reportedRoot])
		{
			errMsg = [NSString stringWithFormat:
				@"Calculated root (%@) doesn't match file root (%@)", calculatedRoot, reportedRoot];
		}
	}
	
done:
	
	if (errMsg)
	{
		error = [NSError errorWithClass:[self class] code:0 description:errMsg];
	}
	
	if (outError) *outError = error;
	return result;
}

/**
 * See header file for description.
 */
- (NSString *)rootHash
{
	NSDictionary *merkle = file[@"merkle"]; // we already know this is a valid dictionary
	NSString *root = merkle[@"root"];
	
	if ([root isKindOfClass:[NSString class]]) {
		return root;
	} else {
		return @"";
	}
}

/**
 * See header file for description.
 */
- (NSSet<NSString *> *)userIDs
{
	NSDictionary *lookup = file[@"lookup"];
	NSMutableSet<NSString *> *userIDs = [NSMutableSet setWithCapacity:lookup.count];
	
	for (NSString *userID in lookup)
	{
		[userIDs addObject:userID];
	}
	
	return [userIDs copy];
}

/**
 * See header file for description.
 */
- (BOOL)getPubKey:(NSString **)outPubKey
            keyID:(NSString **)outKeyID
        forUserID:(NSString *)inUserID
{
	NSString *pubKey = nil;
	NSString *keyID = nil;
	
	NSDictionary *lookup = file[@"lookup"];
	NSNumber *idxNum = lookup[inUserID];
	
	if (idxNum != nil)
	{
		NSUInteger idx = [idxNum unsignedIntegerValue];
		NSArray<NSString *> *values = file[@"values"];
		
		if (idx < values.count)
		{
			NSString *jsonStr = values[idx];
			NSData *jsonData = [jsonStr dataUsingEncoding:NSUTF8StringEncoding];
			
			id jsonDict = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
			if ([jsonDict isKindOfClass:[NSDictionary class]])
			{
				NSString *userID = jsonDict[@"userID"];
				
				if ([userID isEqual:inUserID])
				{
					id value;
					
					value = jsonDict[@"pubKey"];
					if ([value isKindOfClass:[NSString class]]) {
						pubKey = (NSString *)value;
					}
					
					value = jsonDict[@"keyID"];
					if ([value isKindOfClass:[NSString class]]) {
						keyID = (NSString *)value;
					}
				}
			}
		}
	}
	
	if (outPubKey) *outPubKey = pubKey;
	if (outKeyID) *outKeyID = keyID;
	
	return (pubKey != nil) && (keyID != nil);
}

@end
