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

@interface ActivityMonitorTableViewCell : UITableViewCell <ActivityMonitorTableCellProtocol>

@property (nonatomic, copy, readwrite) NSString *nodeID;

@property (nonatomic, strong) IBOutlet UIImageView *opTypeImageView;

@property (nonatomic, strong) IBOutlet UIProgressView *horizontalProgress;
@property (nonatomic, strong) IBOutlet UIActivityIndicatorView *circularProgress;

@property (nonatomic, strong) IBOutlet UILabel *nodeInfo;
@property (nonatomic, strong) IBOutlet UILabel *opsInfo;

@property (nonatomic, strong) IBOutlet UILabel *priority;
@property (nonatomic, strong) IBOutlet UILabel *networkThroughput;
@property (nonatomic, strong) IBOutlet UILabel *timeRemaining;

@end

NS_ASSUME_NONNULL_END
