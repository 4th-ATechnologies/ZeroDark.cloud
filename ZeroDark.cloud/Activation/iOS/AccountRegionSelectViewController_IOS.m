/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
 **/

#import "AccountRegionSelectViewController_IOS.h"
#import "ZeroDarkCloud.h"
#import "ZeroDarkCloudPrivate.h"
#import "ZDCConstantsPrivate.h"
#import "ZDCLogging.h"
#import "GBPing.h"

#import "PingTableViewCell.h"

#import "UIButton+Activation.h"


// Libraries
#import <stdatomic.h>

// Log Levels: off, error, warn, info, verbose
// Log Flags : trace
#if DEBUG
static const int zdcLogLevel = ZDCLogLevelWarning;
#else
static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)


@implementation AccountRegionSelectViewController_IOS
{
	IBOutlet __weak UILabel*       _lblTitle;
	IBOutlet __weak UILabel*       _lblDescription;
	IBOutlet __weak UITableView        *_tblRegions;
	IBOutlet __weak NSLayoutConstraint *_cnstTblHeight;
	IBOutlet __weak UIButton*    _btnSelect;
	IBOutlet __weak UIButton*    _btnAgain;

	NSMutableDictionary*        regionDict;
	// key - nsnumber
	// hostName
	// displayName
	// ping time

	dispatch_queue_t            regionDictQueue;
	void *                      IsOnRegionQueueKey;

	NSArray*                    regionsTable;
	// kHeaderTitle 	NSString
	// kRegions		NSArray <NSNumber*>*

	NSTimer *                   pingTimer;


	dispatch_queue_t            internetQueue;
	void  *                     IsOnInternetQueueKey;

	BOOL                        hasInternet;

	OSImage*                    okImage;
	OSImage*                    failImage;
	OSImage*                    maybeImage;

	NSNumber*                   preferedRegion;

	YapDatabaseConnection        * databaseConnection;
	AFNetworkReachabilityManager * reachability;
	ZDCRestManager               * restManager;
}


static NSString *const kRegionNameKey      = @"regionName";
static NSString *const kDisplayNameKey     	= @"displayname";
static NSString *const kPingObjectKey      	= @"pingObject";
static NSString *const kIsAvalable        	= @"isAvalable";

static NSString *const kPingTimeKey        = @"pingTime";
static NSString *const kPingStatus         = @"pingStatus";

static NSString *const kHeaderTitle      	= @"title";
static NSString *const kRegions	      		= @"regions";

@synthesize accountSetupVC = accountSetupVC;
@synthesize standAlone = standAlone;

- (void)viewDidLoad {
	[super viewDidLoad];

	regionDictQueue     = dispatch_queue_create("PingViewController.regionDictQueue", DISPATCH_QUEUE_SERIAL);
	IsOnRegionQueueKey = &IsOnRegionQueueKey;
	dispatch_queue_set_specific(regionDictQueue, IsOnRegionQueueKey, IsOnRegionQueueKey, NULL);

	internetQueue = dispatch_queue_create("PingViewController.internetQueue", DISPATCH_QUEUE_SERIAL);
	IsOnInternetQueueKey = &IsOnInternetQueueKey;
	dispatch_queue_set_specific(internetQueue, IsOnInternetQueueKey, IsOnInternetQueueKey, NULL);

	okImage = [UIImage imageNamed:@"ball-green"
						 inBundle:[ZeroDarkCloud frameworkBundle]
	compatibleWithTraitCollection:nil];

	failImage = [UIImage imageNamed:@"ball-red"
						   inBundle:[ZeroDarkCloud frameworkBundle]
	  compatibleWithTraitCollection:nil];

	maybeImage = [UIImage imageNamed:@"ball-orange"
							inBundle:[ZeroDarkCloud frameworkBundle]
	   compatibleWithTraitCollection:nil];

	[PingTableViewCell registerViewsforTable:_tblRegions
									  bundle:[ZeroDarkCloud frameworkBundle]];

	_tblRegions.separatorInset = UIEdgeInsetsMake(0, 20, 0, 0); // top, left, bottom, right

	[[NSNotificationCenter defaultCenter] addObserver: self
											 selector: @selector(reachabilityChanged:)
												 name: AFNetworkingReachabilityDidChangeNotification
											   object: nil /* notification doesn't assign object ! */];


	void (^PrepContainer)(UIView *) = ^(UIView *container){
		container.layer.cornerRadius   = 16;
		container.layer.masksToBounds  = YES;
		container.layer.borderColor    = [UIColor whiteColor].CGColor;
		container.layer.borderWidth    = 1.0f;
	};
	PrepContainer(_tblRegions);

	[_btnSelect setup];
	[_btnAgain setup];

}

-(void)viewWillAppear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	if(standAlone)
	{
		_lblTitle.text = NSLocalizedString(@"Region Ping Test", @"Region Ping Test");
		_lblDescription.text = @"";
	}
	else
	{
		_lblTitle.text = NSLocalizedString(@"Select Region", @"Select Region");
		_lblDescription.text =  NSLocalizedString(@"Please pick a region to store your data.",
																@"Please pick a region to store your data.");
	}
	[_lblDescription sizeToFit];
	
 }

-(void)viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];

	databaseConnection = accountSetupVC.owner.databaseManager.uiDatabaseConnection;
	reachability = accountSetupVC.owner.reachability;
	restManager = accountSetupVC.owner.restManager;

	hasInternet = reachability.isReachable;

	[accountSetupVC setHelpButtonHidden:NO];
	accountSetupVC.btnBack.hidden = standAlone || self.navigationController.viewControllers.count == 1;

	_tblRegions.allowsSelection = !standAlone;

	_btnAgain.enabled = NO;
	_btnSelect.enabled = NO;
	_btnSelect.hidden = standAlone;

	if( hasInternet)
	{
		[_btnAgain setTitle:@"Try Again" forState:UIControlStateNormal];
		[_btnAgain setTitle:@"Try Again" forState:UIControlStateDisabled];

		[self againButtonTapped:self];

	}
	else
	{
		[_btnAgain setTitle:@"No Internet" forState:UIControlStateNormal];
		[_btnAgain setTitle:@"No Internet" forState:UIControlStateDisabled];
	}
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void) viewDidDisappear:(BOOL)animated
{
	[super viewDidDisappear:animated];
	[self stopPing:self];
}



-(void)viewWillLayoutSubviews
{
	_cnstTblHeight.constant = _tblRegions.contentSize.height;
}


- (BOOL)canPopViewControllerViaPanGesture:(AccountSetupViewController_IOS *)sender
{
	return !standAlone;
}

#pragma mark - notifications


/**
 * Invoked when the reachability changes.
 * That is, when the circumstances of our Internet access has changed.
 **/
- (void)reachabilityChanged:(NSNotification *)notification
{
	ZDCLogAutoTrace();
	__weak typeof(self) weakSelf = self;

	BOOL newHasInternet = reachability.isReachable;

	// Note: the 'hasInternet' variable is only safe to access/modify within the 'queue'.
	dispatch_block_t block = ^{ @autoreleasepool {

		__strong typeof(self) strongSelf = weakSelf;
		if(!strongSelf) return;

		BOOL updateUI = NO;

		if (!strongSelf->hasInternet && newHasInternet)
		{
			strongSelf->hasInternet = YES;
			updateUI = YES;
 		}
		else if (strongSelf->hasInternet && !newHasInternet)
		{
			strongSelf->hasInternet = NO;
			updateUI = YES;

 		}

		if(updateUI)
		{
			dispatch_async(dispatch_get_main_queue(), ^{ @autoreleasepool {

				__strong typeof(self) strongSelf = weakSelf;
				if(!strongSelf) return;

				if(newHasInternet)
				{
					strongSelf->_btnAgain.enabled = YES;
					[strongSelf->_btnAgain setTitle:@"Try Again" forState:UIControlStateNormal];
					[strongSelf->_btnAgain setTitle:@"Try Again" forState:UIControlStateDisabled];
				}
				else
				{
					[self stopPing:nil];

					strongSelf->_btnAgain.enabled = NO;
					strongSelf->_btnSelect.enabled = NO;

					[strongSelf->_btnAgain setTitle:@"No Internet" forState:UIControlStateNormal];
					[strongSelf->_btnAgain setTitle:@"No Internet" forState:UIControlStateDisabled];

				}
			}});
		}
	}};

	if (dispatch_get_specific(IsOnInternetQueueKey))
		block();
	else
		dispatch_async(internetQueue, block);
}

#pragma mark - actions

- (IBAction)againButtonTapped:(id)sender
{
	__weak typeof(self) weakSelf = self;

	_btnAgain.enabled = NO;
	_btnSelect.enabled = NO;

	[self createRegionTableWithCompletionBlock:^(NSError *error) {

		__strong typeof(self) strongSelf = weakSelf;
		if(!strongSelf) return;

		if(!error)
		{
			[strongSelf startPing];
		}
		else
		{
			[strongSelf->accountSetupVC showError:@"Could Not Access Server"
							  message:error.localizedFailureReason?:error.localizedDescription
					  completionBlock:^{

						  __strong typeof(self) strongSelf = weakSelf;
						  if(!strongSelf) return;

						  [strongSelf->accountSetupVC popFromCurrentView   ];

					  }];


			//           error complain
		}
	}];

}



- (IBAction)selectButtonTapped:(id)sender
{
	if(standAlone)
		return;

	if(!accountSetupVC.user)
		return;

	NSIndexPath *indexPath = [_tblRegions indexPathForSelectedRow];
	if(!indexPath || indexPath.row < 0)
		return;

	AWSRegion region = [self regionForIndexPath:indexPath];
	if( region == AWSRegion_Invalid)
		return;

    [self selectRegion:region];
}

-(void) selectRegion:(AWSRegion)region
{
    __weak typeof(self) weakSelf = self;

    [accountSetupVC selectRegionForUserID:accountSetupVC.user.uuid
                                   region:region
                          completionBlock:^(NSError * _Nonnull error)
     {
         __strong typeof(self) strongSelf = weakSelf;
         if (!strongSelf) return;
         
         if(error)
         {
             [strongSelf.accountSetupVC showError:NSLocalizedString(@"Could not set region",@"Could not set region")
                                          message:error.localizedFailureReason?:error.localizedDescription
                                  completionBlock:^{
												 __strong typeof(self) strongSelf = weakSelf;
												 if (!strongSelf) return;
												 
                                      [strongSelf->accountSetupVC popFromCurrentView   ];
                                  }];
         }
         else
         {
             [strongSelf.accountSetupVC showWait:NSLocalizedString(@"Please Wait", @"Please Wait")
                                         message:NSLocalizedString(@"Activating your account",@"Activating your account")
                                 completionBlock:nil];
             
             [strongSelf.accountSetupVC resumeActivationForUserID:strongSelf->accountSetupVC.user.uuid
                                              cancelOperationFlag:nil
                                                  completionBlock:^(NSError * _Nonnull error)
             {
                 __strong typeof(self) strongSelf = weakSelf;
                 if (!strongSelf) return;
                 
                 [strongSelf.accountSetupVC cancelWait];
                 
                 if(error)
                 {
                     [strongSelf.accountSetupVC showError:NSLocalizedString(@"Activation failed",@"Activation failed")
                                                  message:error.localizedDescription
                                          completionBlock:^{
															__strong typeof(self) strongSelf = weakSelf;
															if (!strongSelf) return;
															
															
                                              [strongSelf->accountSetupVC popFromCurrentView   ];
                                          }];
                 }
             }];
             

            }
     }];
}

#pragma mark - ping

-(void) startPing
{
	__weak typeof(self) weakSelf = self;

	__block atomic_uint pendingCount = 0;

	dispatch_block_t pingSetupCompleteBlock = ^{

		__strong typeof(self) strongSelf = weakSelf;
		if(!strongSelf) return;

		if (atomic_fetch_sub(&pendingCount, 1)  != 1)
		{
			// Still waiting for all tasks to complete
			return;
		}
		[strongSelf->_tblRegions reloadData];

		strongSelf->_tblRegions.allowsSelection = NO;

		strongSelf->pingTimer = [NSTimer scheduledTimerWithTimeInterval:4
													 target:self
												   selector:@selector(stopPing:)
												   userInfo:nil
													repeats:NO];
	};

	_btnAgain.enabled = NO;
	_btnSelect.enabled = NO;
	preferedRegion = nil;

	_tblRegions.allowsSelection = NO;

	//    _lblStatus.text = [NSString stringWithFormat:@"Finding closest host for AWS"];

	dispatch_sync(regionDictQueue, ^{

		__strong typeof(self) strongSelf = weakSelf;
		if(!strongSelf) return;

		pendingCount =  strongSelf->regionDict.count;

		[strongSelf->regionDict enumerateKeysAndObjectsUsingBlock:^(NSNumber* regionNum, NSDictionary* regionInfo, BOOL * _Nonnull stop) {
			NSString* host = [regionInfo objectForKey:kRegionNameKey];
			GBPing* ping = [regionInfo objectForKey:kPingObjectKey];
			if(ping)
			{
				[ping stop];
			}
			else
			{
				ping =  [[GBPing alloc] init];
			}
			ping.host = host;
			ping.delegate = (id<GBPingDelegate> )  self;
			ping.timeout = 1.0;
			ping.pingPeriod = 0.9;

			NSMutableDictionary* newRegionInfo =  [NSMutableDictionary dictionaryWithDictionary:regionInfo];
			[newRegionInfo setObject:ping forKey:kPingObjectKey];
			[newRegionInfo removeObjectForKey :kPingStatus];
			[newRegionInfo removeObjectForKey :kPingTimeKey];
			[strongSelf->regionDict setObject:newRegionInfo forKey:regionNum];

			[ping setupWithBlock:^(BOOL success, NSError *error) {

				//necessary to resolve hostname
				if (success)
				{
					[ping startPinging];
				}
				else
				{
					[self setPingInfoForHost:host pingInfo:nil];
				}

				pingSetupCompleteBlock();

			}];
		}];

	});

}

- (void)stopPing:(id)sender
{
	__weak typeof(self) weakSelf = self;
	

	if(pingTimer)
		[pingTimer invalidate];

	dispatch_sync(regionDictQueue, ^{

		__strong typeof(self) strongSelf = weakSelf;
		if(!strongSelf) return;

		[strongSelf->regionDict enumerateKeysAndObjectsUsingBlock:^(NSNumber* regionNum, NSDictionary* regionInfo, BOOL * _Nonnull stop) {

			GBPing* ping = [regionInfo objectForKey:kPingObjectKey];
			if(ping)
			{
				[ping stop];

			}

			NSMutableDictionary* newRegionInfo =  [NSMutableDictionary dictionaryWithDictionary:regionInfo];
			[newRegionInfo removeObjectForKey :kPingObjectKey];
			[strongSelf->regionDict setObject:newRegionInfo forKey:regionNum];
		}];
	});

	_btnAgain.enabled = YES;
	_tblRegions.allowsSelection = YES;

	[self calulatePreferedRegion];
}

- (void)ping:(GBPing *)pinger didReceiveReplyWithSummary:(GBPingSummary *)summary
{
//	ZDCLogVerbose(@"REPLY>  %@", summary);

	[self setPingInfoForHost:pinger.host pingInfo:summary];
}

- (void)ping:(GBPing *)pinger didReceiveUnexpectedReplyWithSummary:(GBPingSummary *)summary
{
//	ZDCLogVerbose(@"BREPLY> %@", summary);

	[self setPingInfoForHost:pinger.host pingInfo:nil];
}

- (void)ping:(GBPing *)pinger didTimeoutWithSummary:(GBPingSummary *)summary
{
//	ZDCLogVerbose(@"TIMOUT> %@", summary);

	[self setPingInfoForHost:pinger.host pingInfo:nil];
}

- (void)ping:(GBPing *)pinger didFailWithError:(NSError *)error
{
//	ZDCLogVerbose(@"FAIL>   %@", error);

	[self setPingInfoForHost:pinger.host pingInfo:nil];
}

- (void)ping:(GBPing *)pinger didFailToSendPingWithSummary:(GBPingSummary *)summary error:(NSError *)error
{
//	ZDCLogGreen(@"FSENT>  %@, %@", summary, error);

	[self setPingInfoForHost:pinger.host pingInfo:nil];
}


#pragma mark - table management

- (void)createRegionTableWithCompletionBlock:(void (^)(NSError * error))completionBlock
{
	[accountSetupVC showWait:@"Please Wait"
					 message:@"Downloading region info"
			 completionBlock:nil];

	__weak typeof(self) weakSelf = self;

	[restManager fetchConfigWithCompletionQueue:dispatch_get_main_queue()
							   completionBlock:^(NSDictionary * _Nullable config, NSError * _Nullable error)
	 {
#pragma clang diagnostic push
#pragma clang diagnostic warning "-Wimplicit-retain-self"

		 __strong typeof(self) strongSelf = weakSelf;
		 if (strongSelf == nil) return;

		 [strongSelf.accountSetupVC cancelWait];
		 if(!error)
		 {
			 NSArray<NSNumber *> *availableRegions = [config objectForKey:kSupportedConfigurations_Key_AWSRegions];
			 NSArray<NSNumber *> *comingSoonRegions = [config objectForKey:kSupportedConfigurations_Key_AWSRegions_ComingSoon];

			 NSMutableArray <NSNumber *> *otherRegions = NSMutableArray.array;
			 NSMutableDictionary* newRegionDict = NSMutableDictionary.dictionary;

			 // section 0 is available, section 1 is not available
			 for (NSNumber* num in [AWSRegions allRegions])
			 {
				 BOOL isAvalableNow = [availableRegions containsObject:num];
				 BOOL isVailableSoon = [comingSoonRegions containsObject:num];

				 if(!(isAvalableNow || isVailableSoon))
					 [otherRegions addObject:num];

				 NSString* hostName = [AWSRegions dualStackHostForRegion:num.integerValue];
				 hostName = [NSString stringWithFormat:@"s3.%@", hostName];

				 NSString* displayName = [AWSRegions displayNameForRegion:num.integerValue];

				 NSDictionary* entry = @{
										 kRegionNameKey: hostName,
										 kDisplayNameKey: displayName,
										 kIsAvalable: @(isAvalableNow)
										 };
				 newRegionDict[num] = entry;
			 }

			 // sort regions alphabetic

			 availableRegions = [availableRegions sortedArrayUsingComparator:^NSComparisonResult(NSNumber* regNum1, NSNumber* regNum2) {
				 NSString* name1 = [AWSRegions displayNameForRegion:regNum1.integerValue];
				 NSString* name2 = [AWSRegions displayNameForRegion:regNum2.integerValue];
				 return [name1 localizedCaseInsensitiveCompare: name2];
			 }];

			 if(comingSoonRegions.count)
			 {
				 comingSoonRegions = [comingSoonRegions sortedArrayUsingComparator:^NSComparisonResult(NSNumber* regNum1, NSNumber* regNum2) {
					 NSString* name1 = [AWSRegions displayNameForRegion:regNum1.integerValue];
					 NSString* name2 = [AWSRegions displayNameForRegion:regNum2.integerValue];
					 return [name1 localizedCaseInsensitiveCompare: name2];
				 }];
			 }

			 if(otherRegions.count)
			 {
				 otherRegions = [[otherRegions sortedArrayUsingComparator:^NSComparisonResult(NSNumber* regNum1, NSNumber* regNum2) {
					 NSString* name1 = [AWSRegions displayNameForRegion:regNum1.integerValue];
					 NSString* name2 = [AWSRegions displayNameForRegion:regNum2.integerValue];
					 return [name1 localizedCaseInsensitiveCompare: name2];
				 }] mutableCopy];
			 }

			 strongSelf->regionDict = newRegionDict;

			 NSMutableArray* _regionTable = NSMutableArray.array;

			 [_regionTable addObject: @{ kHeaderTitle: @"Available Now",
										 kRegions : availableRegions
										 }];
			 if(comingSoonRegions.count )
			 {
				 [_regionTable addObject: @{ kHeaderTitle: @"Coming Soon",
											 kRegions : comingSoonRegions
											 }];
			 }

			 if(otherRegions.count)
			 {
				 [_regionTable addObject: @{ kHeaderTitle: @"In the works",
											 kRegions : otherRegions
											 }];
			 }

			 strongSelf->regionsTable = _regionTable;

			 [strongSelf->_tblRegions reloadData];
		 }

		 if (completionBlock) {
			 completionBlock(error);
		 }

#pragma clang diagnostic pop
	 }];
}


-(NSIndexPath*) indexPathForRegion:(NSNumber*)region
{
	__block NSIndexPath* indexPath = nil;

	[regionsTable enumerateObjectsUsingBlock:^(NSDictionary* sectionDict, NSUInteger section, BOOL * _Nonnull stop1) {
		NSArray* regionArray = [sectionDict objectForKey:kRegions];

		[regionArray enumerateObjectsUsingBlock:^(NSNumber* num, NSUInteger row, BOOL * _Nonnull stop2) {

			if([region isEqualToNumber:num])
			{
				indexPath = [NSIndexPath indexPathForRow:row inSection:section];
				*stop1 = YES;
				*stop2 = YES;
			}
		}];
	}];

	return indexPath;
}

-(AWSRegion) regionForIndexPath:(NSIndexPath*)indexPath
{
	AWSRegion region = AWSRegion_Invalid;

	if(indexPath &&  indexPath.row >= 0)
	{
		NSDictionary* dict = regionsTable[indexPath.section];
		NSArray* regionArray = [dict objectForKey:kRegions];
		NSNumber* regionNum = [regionArray objectAtIndex:indexPath.row];
		if(regionNum)
			region = regionNum.integerValue;
	}

	return region;
}


-(void)setPingInfoForHost:(NSString*)host pingInfo:(GBPingSummary*)pingInfoIn
{
	if(!host) return;
	__weak typeof(self) weakSelf = self;

	__block NSIndexPath * pathToReload = nil;

	dispatch_sync(regionDictQueue, ^{
		__strong typeof(self) strongSelf = weakSelf;
		if(!strongSelf) return;

		[strongSelf->regionDict enumerateKeysAndObjectsUsingBlock:^(NSNumber* regionNum, NSMutableDictionary* regionInfo, BOOL * _Nonnull stop) {
			NSString* hostName = regionInfo[kRegionNameKey];

			if([hostName isEqualToString:host])
			{
				NSMutableDictionary* newEntry = [NSMutableDictionary dictionaryWithDictionary:regionInfo ];

				if(pingInfoIn)
				{
					[newEntry setObject:@(pingInfoIn.status) forKey:kPingStatus];

					if(pingInfoIn.status == GBPingStatusSuccess)
					{

						NSTimeInterval newPingTime = pingInfoIn.rtt;

						NSNumber* avgPingTime = regionInfo[kPingTimeKey];
						if(avgPingTime)
							newPingTime = (avgPingTime.doubleValue +  newPingTime)/ 2.0;

						[newEntry setObject:@(newPingTime) forKey:kPingTimeKey];
					}
				}
				else
				{
					[newEntry removeObjectForKey:kPingTimeKey];
					[newEntry setObject:@(GBPingStatusFail) forKey:kPingStatus];
				}

				[strongSelf->regionDict setObject:newEntry forKey:regionNum];
				pathToReload =  [self indexPathForRegion:regionNum];
				*stop = YES;

			}
		}];
	});


	if(pathToReload)
	{
		[_tblRegions reloadRowsAtIndexPaths:@[pathToReload] withRowAnimation:UITableViewRowAnimationNone];
	}

}



-(void)calulatePreferedRegion
{
	__block NSTimeInterval lowestPing = DBL_MAX;
	__block NSNumber* closestRegionNum = NULL;
	__weak typeof(self) weakSelf = self;

	dispatch_sync(regionDictQueue, ^{

		__strong typeof(self) strongSelf = weakSelf;
		if(!strongSelf) return;

		[strongSelf->regionDict enumerateKeysAndObjectsUsingBlock:^(NSNumber* regionNum, NSMutableDictionary* regionInfo, BOOL * _Nonnull stop) {

			BOOL isAvalable = [regionInfo[kIsAvalable] boolValue];
			if(isAvalable)
			{
				NSNumber* pingTime = regionInfo[kPingTimeKey];
				if(pingTime && pingTime.doubleValue < lowestPing)
				{
					lowestPing = pingTime.doubleValue;
					closestRegionNum = regionNum;
				}
			}
		}];
	});


	preferedRegion  = closestRegionNum;
	[_tblRegions reloadData];

	[self selectPreferedHost];
}

-(void) selectPreferedHost
{
	NSIndexPath* indexPath = nil;

	if(preferedRegion)
	{
		indexPath = [self indexPathForRegion:preferedRegion];
	}

	[_tblRegions selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionNone];

	_btnSelect.enabled = indexPath!=nil;
}



#pragma mark - regions table

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
	NSDictionary* dict = regionsTable[section];
	NSString* title = [dict objectForKey:kHeaderTitle];

	UIView *container = [UIView new];
	UILabel *label = [UILabel new];

	label.translatesAutoresizingMaskIntoConstraints = NO;
	[container addSubview:label];


	[container addConstraint:
	 [NSLayoutConstraint constraintWithItem:label
								  attribute:NSLayoutAttributeCenterX
								  relatedBy:NSLayoutRelationEqual
									 toItem:container
								  attribute:NSLayoutAttributeCenterX
								 multiplier:1
								   constant:0]];
	[container addConstraint:
	 [NSLayoutConstraint constraintWithItem:label
								  attribute:NSLayoutAttributeCenterY
								  relatedBy:NSLayoutRelationEqual
									 toItem:container
								  attribute:NSLayoutAttributeCenterY
								 multiplier:1
								   constant:0]];

	container.backgroundColor = UIColor.groupTableViewBackgroundColor;
	label.textColor =  UIColor.darkGrayColor;
	label.font = [UIFont boldSystemFontOfSize:17.0];
	label.textAlignment = NSTextAlignmentCenter;
	label.text = title;

	return container;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
	return 30;
}

-(NSInteger)numberOfSectionsInTableView:(UITableView *)tv
{
	return regionsTable.count;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section
{

	NSDictionary* sectionDict = regionsTable[section];
	NSArray* regionArray = [sectionDict objectForKey:kRegions];
	return regionArray.count ;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	PingTableViewCell *cell = (PingTableViewCell *)  [tv dequeueReusableCellWithIdentifier:kPingTableCellIdentifier];

	NSDictionary* sectionDict = regionsTable[indexPath.section];
	NSArray* regionArray = [sectionDict objectForKey:kRegions];
	NSNumber* regionNum = [regionArray objectAtIndex:indexPath.row];

	NSDictionary* regionInfo = [regionDict objectForKey:regionNum];

	NSString* displayName = regionInfo[kDisplayNameKey];
	NSNumber* avgPingTime = regionInfo[kPingTimeKey];
	NSNumber* pingStatus = regionInfo[kPingStatus];
	BOOL isAvalable = [regionInfo[kIsAvalable] boolValue];

	GBPing* pingObj = [regionInfo objectForKey:kPingObjectKey];

	if(pingObj)
	{
		cell._actBusy.hidden = NO;
		cell._imgDot.hidden = YES;
		[cell._actBusy startAnimating];
	}
	else
	{
		cell._actBusy.hidden = YES;
		[cell._actBusy stopAnimating];
	}

	if(pingStatus)
	{
		GBPingStatus status = pingStatus.intValue;

		if(status == GBPingStatusFail)
		{
			cell._lblPingTime.text = @"-";
			cell._imgDot.image = failImage;
			if(!pingObj)
				cell._imgDot.hidden = NO;

		}
		else if(status == GBPingStatusSuccess)
		{
			if(avgPingTime)
			{
				cell._lblPingTime.text =  [NSString stringWithFormat: @"%.0f ms", avgPingTime.doubleValue * 1000];

				if([regionNum isEqual:preferedRegion])
				{
					cell._imgDot.image = okImage;
					cell._imgDot.hidden = NO;

				}
				else
				{
					cell._imgDot.hidden = YES;
				}
			}
		}
		else
		{
			if(!pingObj)  //  died on pending?
			{
				cell._imgDot.image = maybeImage;
				cell._imgDot.hidden = NO;
			}
			else
			{
				cell._imgDot.hidden = YES;
			}

			cell._lblPingTime.text = @"";
		}
	}
	else
	{
		cell._lblPingTime.text = @"";
		cell._imgDot.hidden = YES;
	}

	if(!isAvalable)
	{
		cell._lblHostName.textColor = [UIColor lightGrayColor];
		cell._lblPingTime.textColor = [UIColor lightGrayColor];
		cell.userInteractionEnabled = NO;
	}
	else
	{
		cell._lblHostName.textColor = [UIColor blackColor];
		cell._lblPingTime.textColor = [UIColor blackColor];
		cell.userInteractionEnabled = !standAlone;
	}

	cell._lblHostName.text = displayName;

	return cell;
}

@end
