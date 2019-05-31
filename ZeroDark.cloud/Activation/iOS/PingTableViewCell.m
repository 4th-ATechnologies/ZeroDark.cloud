//
//  PingTableViewCell.m
//  storm4
//
//  Created by vinnie on 7/13/16.
//  Copyright © 2016 4th-A Technologies, LLC. All rights reserved.
//

#import "PingTableViewCell.h"

@implementation PingTableViewCell

NSString *const kPingTableCellIdentifier = @"PingTableViewCell";

@synthesize _lblHostName;
@synthesize _lblPingTime;
@synthesize _imgDot;
@synthesize _actBusy;

+(void) registerViewsforTable:(UITableView*)tableView bundle:(nullable NSBundle *)bundle
{
	UINib *buttonCellNib = [UINib nibWithNibName:@"PingTableViewCell" bundle:bundle];
	[tableView registerNib:buttonCellNib forCellReuseIdentifier:kPingTableCellIdentifier];
}

@end
