/**
 * ZeroDark.cloud Framework
 *
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import <UIKit/UIKit.h>
#import "ActivityMonitorTableCellProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@interface ActivityMonitorTableViewCellRaw : UITableViewCell <ActivityMonitorTableCellProtocol>

@property (nonatomic, strong) IBOutlet UIProgressView *horizontalProgress;
@property (nonatomic, strong) IBOutlet UIActivityIndicatorView *circularProgress;

@property (nonatomic, strong) IBOutlet UILabel *opType;
@property (nonatomic, strong) IBOutlet UILabel *opUUID;
@property (nonatomic, strong) IBOutlet UILabel *snapshot;
@property (nonatomic, strong) IBOutlet UILabel *dependenciesRemaining;

@property (nonatomic, strong) IBOutlet UILabel *networkThroughput;
@property (nonatomic, strong) IBOutlet UILabel *timeRemaining;

@property (nonatomic, strong) IBOutlet UILabel *dirPrefix;
@property (nonatomic, strong) IBOutlet UILabel *filename;

@property (nonatomic, strong) IBOutlet UILabel *priority;

@end

NS_ASSUME_NONNULL_END
