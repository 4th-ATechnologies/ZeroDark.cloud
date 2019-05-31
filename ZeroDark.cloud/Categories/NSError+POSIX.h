//
//  NSError+PosixError.h
//  storm4
//
//  Created by vincent Moscaritolo on 5/2/16.
//  Copyright © 2016 4th-A Technologies, LLC. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSError (POSIX)

+ (NSError *)errorWithPOSIXCode:(int)code;

@end
