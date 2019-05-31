//
//  NSArray+S4.m
//  markletest
//
//  Created by vinnie on 1/28/18.
//  Copyright © 2018 4th-a. All rights reserved.
//

#import "NSArray+S4.h"
#import "NSData+S4.h"
#import "NSError+S4.h"
#import "NSString+S4.h"


@interface NSMutableArray (Queue)
- (id) dequeue;
- (void)queue: (id)item;
@end

@implementation NSMutableArray (Queue)

- (id) dequeue {
    id item = nil;
    if ([self count] != 0) {
        item =  [self firstObject];
        [self removeObjectAtIndex:0];
    }
    return item;
}

- (void) queue: (id)item
{
    [self insertObject:item atIndex:0];

}
@end

@implementation NSArray (S4)

- (NSData*) hashWithAlgorithm:(HASH_Algorithm)hashAlgor error:(NSError **)errorOut;
{
    NSError* error = nil;
    NSData *hashData = nil;

    S4Err           err         = kS4Err_NoErr;
    uint8_t         hashBuf [512/8];   //SHA512
    HASH_ContextRef hashCtx =  kInvalidHASH_ContextRef;
    size_t          hashSize = 0;

    err = HASH_Init(hashAlgor, &hashCtx); CKERR;
    err = HASH_GetSize(hashCtx, &hashSize);CKERR;

    for(id obj in self)
    {
        if([obj isKindOfClass:[NSData class]])
        {
            NSData* data = (NSData*)obj;
            err = HASH_Update(hashCtx, data.bytes, data.length); CKERR;

        }
        else
        {
            err = kS4Err_BadParams; CKERR;

        }
    }

    err = HASH_Final(hashCtx, hashBuf); CKERR;

    hashData = [NSData dataWithBytes:hashBuf length:hashSize];

done:

    if(hashCtx)
        HASH_Free(hashCtx);

    if(IsS4Err(err))
        error = [NSError errorWithS4Error:err];


    if(errorOut)
        *errorOut = error;

    return hashData;

}


- (NSString*) merkleHashWithAlgorithm:(HASH_Algorithm)hashAlgor error:(NSError **)errorOut
{
    NSError* error = nil;
    NSString *root = nil;

    NSMutableArray* deque1 = [NSMutableArray arrayWithArray:self];
    NSMutableArray* deque2 = [NSMutableArray array];

    NSString* left = nil;
    NSString* right = nil;
    NSData* cHash = nil;

    // While the main queue has more than one value left (the root)
    while (deque1.count > 1) {

    // Get the two first-pushed values off of the queue and hash them
        left = deque1.dequeue;
        right = deque1.dequeue;

        cHash = [[left stringByAppendingString:right] hashWithAlgorithm:hashAlgor error:&error];
        if(error) goto done;

        [deque2 queue: cHash.hexString];

        // If there are an odd number of leaves (only one hash left),
        // pop the last value, concatenate it with itself, and hash that

        if (deque1.count == 1)
        {
            right = deque1.dequeue;
            cHash = [[right stringByAppendingString:right] hashWithAlgorithm:hashAlgor error:&error];
            if(error) goto done;

            [deque2 queue: cHash.hexString];
      }

        // If everything is off of the main queue (deque1) but the copy
        // queue (deque2) is not empty, there is another level in the tree
        // and more values to hash. Pop them and push them back to the main
        // queue.
        if ((deque1.count == 0) && (deque2.count != 0))
        {

           NSUInteger len2 = deque2.count;

            for (NSUInteger j = 0; j < len2; j++)
            {
                [deque1 queue: deque2.dequeue];
            }
        }

    }

    if(deque1.count == 1)
    {
         root = deque1.dequeue;
    }

done:

    if(errorOut)
        *errorOut = error;

    return root;

}

+(NSArray <NSNumber *> *)arc4RandomArrayWithCount:(NSUInteger)count
{
	NSMutableArray *randArray = [NSMutableArray arrayWithCapacity:count];
	
	for (int i = 0; i < count; ) {
		
		NSNumber* num = [NSNumber numberWithInt: arc4random() % count];
		if([randArray containsObject:num]) continue;
		
		[randArray addObject:num];
		i++;
	}
	return randArray;
	
}

@end
