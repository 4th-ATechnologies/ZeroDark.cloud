//
//  NSArray+S4.h
//  markletest
//
//  Created by vinnie on 1/28/18.
//  Copyright © 2018 4th-a. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <S4Crypto/S4Crypto.h>

@interface NSArray (S4)

- (NSData*) hashWithAlgorithm:(HASH_Algorithm)hashAlgor error:(NSError **)errorOut;

- (NSString*) merkleHashWithAlgorithm:(HASH_Algorithm)hashAlgor error:(NSError **)errorOut;

+(NSArray <NSNumber *> *) arc4RandomArrayWithCount:(NSUInteger)count;

@end
