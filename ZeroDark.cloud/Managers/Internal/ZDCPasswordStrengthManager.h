 /**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
 **/
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZDCPasswordStrength : NSObject

- (double)entropy;
- (double)crackTime;
- (NSString *)password;
- (NSArray *)matchSequence;
- (NSString *)crackTimeDisplay;
- (NSUInteger)score;
- (NSString *)scoreLabel;

@end

@interface ZDCPasswordStrengthManager : NSObject

-(ZDCPasswordStrength*)strengthForPassword:(NSString*)password;

@end

NS_ASSUME_NONNULL_END
