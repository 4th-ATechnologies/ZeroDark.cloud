 /**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
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

@interface ZDCPasswordStrengthCalculator : NSObject

+ (ZDCPasswordStrength *)strengthForPassword:(NSString *)password;

@end

NS_ASSUME_NONNULL_END
