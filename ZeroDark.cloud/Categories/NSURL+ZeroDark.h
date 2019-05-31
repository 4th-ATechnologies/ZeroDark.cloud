//
//  NSURL+ZeroDark.h
//  ZeroDarkCloud
//
//  Created by vinnie on 3/6/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSURL (ZeroDark)

-(BOOL) decompressToDirectory:(NSURL*) outputUrl error:(NSError **)errorOut;

@end

NS_ASSUME_NONNULL_END
