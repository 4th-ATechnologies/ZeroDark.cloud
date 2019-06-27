/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
 **/

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class FixSettingsViewController_IOS;

@protocol FixSettingsViewControllerDelegate <NSObject>
@optional
- (void)fixSettingsViewController:(FixSettingsViewController_IOS *)sender dismissViewControllerAnimated:(BOOL) animated;

- (void)fixSettingsViewController:(FixSettingsViewController_IOS *)sender showSettingsHit:(UIButton *)btn;

@end

@interface FixSettingsViewController_IOS : UIViewController

@property (nonatomic, weak, readonly, nullable) id <FixSettingsViewControllerDelegate> delegate;

- (instancetype)initWithDelegate:(nullable id <FixSettingsViewControllerDelegate>)inDelegate
                           title:(NSString*)inTitle
                   informational:(NSString*)inInformational
                           steps:(NSArray*)inSteps;

@end

NS_ASSUME_NONNULL_END
