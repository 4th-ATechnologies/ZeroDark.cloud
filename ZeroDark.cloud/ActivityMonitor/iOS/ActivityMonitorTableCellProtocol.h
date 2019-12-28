/**
 * ZeroDark.cloud Framework
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol ActivityMonitorTableCellProtocol <NSObject>
@required

@property (nonatomic, strong) IBOutlet UIProgressView *horizontalProgress;

@property (nonatomic, strong) IBOutlet UILabel *networkThroughput;
@property (nonatomic, strong) IBOutlet UILabel *timeRemaining;

@end

NS_ASSUME_NONNULL_END
