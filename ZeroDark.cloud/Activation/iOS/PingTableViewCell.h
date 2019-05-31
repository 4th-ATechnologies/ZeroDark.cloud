//
//  PingTableViewCell.h
//  storm4
//
//  Created by vinnie on 7/13/16.
//  Copyright © 2016 4th-A Technologies, LLC. All rights reserved.
//

#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN

extern NSString *const kPingTableCellIdentifier;


@interface PingTableViewCell : UITableViewCell


@property (nonatomic, weak)     IBOutlet UILabel*               _lblHostName;
@property (nonatomic, weak)     IBOutlet UILabel*               _lblPingTime;

@property (nonatomic, weak)     IBOutlet UIImageView*               _imgDot;
@property (nonatomic, weak)     IBOutlet UIActivityIndicatorView* _actBusy;

+(void) registerViewsforTable:(UITableView*)tableView bundle:(nullable NSBundle *)bundle;

@end

NS_ASSUME_NONNULL_END


