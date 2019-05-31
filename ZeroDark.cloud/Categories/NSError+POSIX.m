//
//  NSError+PosixError.m
//  storm4
//
//  Created by vincent Moscaritolo on 5/2/16.
//  Copyright © 2016 4th-A Technologies, LLC. All rights reserved.
//

#import "NSError+POSIX.h"

@implementation NSError (POSIX)

+ (NSError *)errorWithPOSIXCode:(int) code
{
	return [NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:nil];
}

@end
