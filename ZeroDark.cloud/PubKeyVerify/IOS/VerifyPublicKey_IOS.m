/**
 * ZeroDark.cloud Framework
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://apis.zerodark.cloud
**/

#import "VerifyPublicKey_IOS.h"

#import "ZeroDarkCloudPrivate.h"
#import "ZDCConstantsPrivate.h"
#import "ZDCDateFormatterCache.h"
#import "ZDCImageManagerPrivate.h"
#import "ZDCLogging.h"
#import "ZDCUserManagerPrivate.h"

#import "TCCopyableLabel.h"

// Categories
#import "OSImage+ZeroDark.h"
#import "NSDate+ZeroDark.h"
#import "NSError+ZeroDark.h"
#import "NSString+ZeroDark.h"

// Log Levels: off, error, warning, info, verbose
// Log Flags : trace
#if DEBUG
static const int zdcLogLevel = ZDCLogLevelWarning;
#else
static const int zdcLogLevel = ZDCLogLevelWarning;
#endif

@implementation VerifyPublicKey_IOS
{
	IBOutlet __weak UIImageView*            _imgAvatar;
	IBOutlet __weak UILabel*                _lblDisplayName;
	
	IBOutlet __weak UILabel*                _txtPubKeyType;
	IBOutlet __weak TCCopyableLabel *       _txtPubKeyID;
	IBOutlet __weak TCCopyableLabel *       _txtUserID;
	IBOutlet __weak TCCopyableLabel *       _txtCreated;
	
	
	IBOutlet __weak UIButton*               _btnPubKeyIntegrity;
	IBOutlet __weak UILabel*                _txtPubKeyIntegrity;
	IBOutlet __weak UIActivityIndicatorView* _actPubKeyIntegrity;
	IBOutlet __weak NSLayoutConstraint*    _cnstPubKeyIntegrityBottom;
	IBOutlet __weak UILabel*                _txtPubKeyIntegrityError;
	
	IBOutlet __weak UIButton                * _btnPubKeyServer;
	IBOutlet __weak UILabel                 * _txtPubKeyServer;
	IBOutlet __weak UIActivityIndicatorView * _actPubKeyServer;
	IBOutlet __weak NSLayoutConstraint      * _cnstPubKeyServerBottom;
	IBOutlet __weak UILabel                 * _txtPubKeyServerError;
	
	
	IBOutlet __weak UIButton                * _btnVerifyBlockChain;
	IBOutlet __weak UILabel                 * _txtVerifyBlockChain;
	IBOutlet __weak UIActivityIndicatorView * _actVerifyBlockChain;
	IBOutlet __weak NSLayoutConstraint      * _cnstVerifyBlockChainBottom;
	IBOutlet __weak UILabel                 * _txtVerifyBlockChainError;
	
	IBOutlet __weak UIButton*               _btnShowTransaction;
	
	ZeroDarkCloud *zdc;
	
	NSString * _remoteUserID;
	NSString * _localUserID;
	
	YapDatabaseConnection * uiDatabaseConnection;
	ZDCPublicKey          * pubKey;
	NSString              * blockchainTransaction;
	
	NSDateFormatter * formatter;
	
	UIImage * okImage;
	UIImage * warningImage;
	UIImage * failImage;
	UIImage * questionImage;
	
	UISwipeGestureRecognizer * swipeRight;
}

- (instancetype)initWithOwner:(ZeroDarkCloud *)inOwner
                 remoteUserID:(NSString *)inRemoteUserID
						localUserID:(NSString *)inLocalUserID
{
	NSBundle *bundle = [ZeroDarkCloud frameworkBundle];
	UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"VerifyPublicKey_IOS" bundle:bundle];
	self = [storyboard instantiateViewControllerWithIdentifier:@"VerifyPublicKey"];
	if (self)
	{
		zdc = inOwner;
		_localUserID = [inLocalUserID copy];
		_remoteUserID = [inRemoteUserID copy];
	}
	return self;
	
}

- (void)viewDidLoad
{
	[super viewDidLoad];
	
	uiDatabaseConnection = zdc.databaseManager.uiDatabaseConnection;
	
	formatter = [ZDCDateFormatterCache dateFormatterWithDateStyle: NSDateFormatterShortStyle
	                                                    timeStyle: NSDateFormatterShortStyle];
	
	_txtPubKeyID.lineBreakMode = NSLineBreakByWordWrapping;
	_txtPubKeyID.numberOfLines = 0;
	_txtPubKeyID.font = [UIFont monospacedDigitSystemFontOfSize: _txtPubKeyID.font.pointSize
	                                                     weight: UIFontWeightRegular];
	
	_txtUserID.lineBreakMode = NSLineBreakByWordWrapping;
	_txtUserID.numberOfLines = 0;
	_txtUserID.font = [UIFont monospacedDigitSystemFontOfSize: _txtUserID.font.pointSize
	                                                   weight: UIFontWeightRegular];
	
	_btnPubKeyIntegrity.hidden = YES;
	_actPubKeyIntegrity.hidden = YES;
	_txtPubKeyIntegrityError.hidden = YES;
	_cnstPubKeyIntegrityBottom.constant = 20;
	
	_btnPubKeyServer.hidden = YES;
	_actPubKeyServer.hidden = YES;
	_txtPubKeyServerError.hidden = YES;
	_cnstPubKeyServerBottom.constant = 20;
	
	_btnVerifyBlockChain.hidden = YES;
	_actVerifyBlockChain.hidden = YES;
	_txtVerifyBlockChainError.hidden = YES;
	_cnstVerifyBlockChainBottom.constant = 20;
	
	_btnShowTransaction.hidden = YES;
	blockchainTransaction = nil;
	
	_imgAvatar.layer.cornerRadius = 50 / 2;
	_imgAvatar.clipsToBounds = YES;
		
	okImage = [UIImage imageNamed: @"roundedGreenCheck"
	                     inBundle: [ZeroDarkCloud frameworkBundle]
	compatibleWithTraitCollection: nil];
	
	warningImage = [UIImage imageNamed: @"warning"
	                          inBundle: [ZeroDarkCloud frameworkBundle]
	     compatibleWithTraitCollection: nil];
	
	questionImage = [UIImage imageNamed: @"question-circle"
	                           inBundle: [ZeroDarkCloud frameworkBundle]
	      compatibleWithTraitCollection: nil];
	
	__weak typeof(self) weakSelf = self;
	[_txtPubKeyID setLabelCopied:^(NSString *copyString) {
		
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf)
		{
			UIPasteboard *board = [UIPasteboard generalPasteboard];
			[board setString:strongSelf->_txtPubKeyID.text];
		}
	}];
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	
	self.navigationItem.title = @"Verify Public Key";
	
	UIImage* image = [[UIImage imageNamed:@"backarrow"
										  inBundle:[ZeroDarkCloud frameworkBundle]
			  compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	
	UIBarButtonItem *backItem =
	  [[UIBarButtonItem alloc] initWithImage: image
	                                   style: UIBarButtonItemStylePlain
	                                  target: self
	                                  action: @selector(handleNavigationBack:)];
	
	self.navigationItem.leftBarButtonItem = backItem;
	
	swipeRight = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeRight:)];
	[self.view addGestureRecognizer:swipeRight];
	
	[self refreshUserInfo];
	[self refreshKeyInfo];
	[self refreshPubKeyIntegrity];
	[self refreshServerCopy];
	[self refreshBlockchainInfo];
}


- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	[self.view removeGestureRecognizer:swipeRight]; swipeRight = nil;
	
	//   [[NSNotificationCenter defaultCenter]  removeObserver:self];
}

- (void)swipeRight:(UISwipeGestureRecognizer *)gesture
{
	ZDCLogAutoTrace();
	
	[self handleNavigationBack:NULL];
}

- (void)handleNavigationBack:(UIButton *)backButton
{
	ZDCLogAutoTrace();
	
	[[self navigationController] popViewControllerAnimated:YES];
}

- (void)refreshUserInfo
{
	ZDCLogAutoTrace();
	
	__block ZDCUser *remoteUser = nil;
	__block ZDCUser *localUser = nil;
	[uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		localUser = [transaction objectForKey:_localUserID inCollection:kZDCCollection_Users];
		remoteUser = [transaction objectForKey:_remoteUserID inCollection:kZDCCollection_Users];
		
	#pragma clang diagnostic pop
	}];
	
	_lblDisplayName.text = remoteUser.displayName;
	
	void (^preFetchBlock)(UIImage*, BOOL) = ^(UIImage *image, BOOL willFetch){
		
		// The preFetchBlock is invoked BEFORE the `fetchUserAvatar` method returns
		
		if (image) {
			self->_imgAvatar.image = image;
		} else {
			self->_imgAvatar.image = [self->zdc.imageManager.defaultUserAvatar scaledToSize: self->_imgAvatar.frame.size
			                                                                    scalingMode: ScalingMode_AspectFill];
		}
	};
	
	__weak typeof(self) weakSelf = self;
	void (^postFetchBlock)(UIImage*, NSError*) = ^(UIImage *image, NSError *error){
		
		// The postFetchBlock is invoked LATER, possibly after a download
		__strong typeof(self) strongSelf = weakSelf;
		if (strongSelf && image)
		{
			strongSelf->_imgAvatar.image = image;
		}
	};
	
	[zdc.imageManager fetchUserAvatar: remoteUser
	                      withOptions: nil
	                    preFetchBlock: preFetchBlock
	                   postFetchBlock: postFetchBlock];
}

- (void)refreshKeyInfo
{
	ZDCLogAutoTrace();
	
	if (!_remoteUserID) return;
	
	__block ZDCUser* user = nil;
	
	[uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		user = [transaction objectForKey:_remoteUserID inCollection:kZDCCollection_Users];
		if(user)
		{
			pubKey = [transaction objectForKey:user.publicKeyID inCollection:kZDCCollection_PublicKeys];
		}
		
	#pragma clang diagnostic pop
	}];
	
	if (pubKey)
	{
		NSDictionary* keyDict = pubKey.keyDict;
		
		NSData* pubKeyKeyIDData = [[NSData alloc] initWithBase64EncodedString:pubKey.keyID options:0];
		if(pubKeyKeyIDData.length == 16)
		{
			NSUInteger  len = pubKeyKeyIDData.length / 2;
			NSString* hexString0 = [NSString hexEncodeBytesWithSpaces:pubKeyKeyIDData.bytes
																				length:len];
			NSString* hexString1 = [NSString hexEncodeBytesWithSpaces:pubKeyKeyIDData.bytes + len
																				length:len];
			
			NSString* hexString = [NSString stringWithFormat:@"%@\r%@", hexString0, hexString1];
			_txtPubKeyID.text = hexString;
		}
		else
		{
			NSString* hexString = [NSString hexEncodeBytesWithSpaces:pubKeyKeyIDData.bytes
																			  length:pubKeyKeyIDData.length];
			_txtPubKeyID.text = hexString;
			
		}
		
		
		NSMutableString *string = [NSMutableString stringWithString:keyDict[@"userID"]];
		[string insertString:@"\r" atIndex:16];
		_txtUserID.text =  string;
		
		_txtPubKeyType.text =  keyDict[@"keySuite"];
		
		NSString* dateString =  keyDict[@"start-date"];
		NSDate* date = [NSDate dateFromRfc3339String:dateString];
		
		if(date)
		{
			_txtCreated.text = [formatter stringFromDate:date];
		}
		else
		{
			_txtCreated.text = @"Invalid";
		}
	}
}


- (void)refreshPubKeyIntegrity
{
	ZDCLogAutoTrace();
	
	_txtPubKeyIntegrity.text = @"Verifying Key Integrity…";
	_btnPubKeyIntegrity.hidden = YES;
	_actPubKeyIntegrity.hidden = NO;
	_txtPubKeyIntegrityError.hidden = YES;
	_cnstPubKeyIntegrityBottom.constant = 20;
	[_actPubKeyIntegrity startAnimating];
	
	// check key validity (does the keyID match the key)
	NSError *error = nil;
	[pubKey checkKeyValidityWithError:&error];
	
	// check key self signature
	if (!error)
	{
		BOOL sigFound = [zdc.cryptoTools checkPublicKeySelfSig:pubKey error:&error];
		if (error || !sigFound)
		{
			error = [NSError errorWithClass:[self class] code:0 description:@"Key self-signature is missing"];
		}
	}
	
	[_actPubKeyIntegrity stopAnimating];
	_actPubKeyIntegrity.hidden = YES;
	
	if (error)
	{
		[_btnPubKeyIntegrity setImage:warningImage forState:UIControlStateNormal];
		_txtPubKeyIntegrity.text = @"Key Integrity Verification Failed";
		_txtPubKeyIntegrityError.text = error.localizedDescription;
		_txtPubKeyIntegrityError.textColor = UIColor.redColor;
		[_txtPubKeyIntegrityError sizeToFit];
		_txtPubKeyIntegrityError.hidden = NO;
		_cnstPubKeyIntegrityBottom.constant = _txtPubKeyIntegrityError.frame.size.height  + 30;
	}
	else
	{
		_txtPubKeyIntegrity.text = @"Key Integrity Verified";
		[_btnPubKeyIntegrity setImage:okImage forState:UIControlStateNormal];
	}
	
	_btnPubKeyIntegrity.hidden = NO;
}

- (void)refreshServerCopy
{
	ZDCLogAutoTrace();
	
	_txtPubKeyServer.text = @"Verifying KeyServer Copy…";
	_btnPubKeyServer.hidden = YES;
	_actPubKeyServer.hidden = NO;
	_txtPubKeyServerError.hidden = YES;
	_cnstPubKeyServerBottom.constant = 20;
	[_actPubKeyServer startAnimating];
	
	__block ZDCUser *remoteUser = nil;
	
	[uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		remoteUser = [transaction objectForKey:_remoteUserID inCollection:kZDCCollection_Users];
		
	#pragma clang diagnostic pop
	}];
	
	__weak typeof(self) weakSelf = self;
	[zdc.restManager fetchPubKeyForUser: remoteUser
	                        requesterID: _localUserID
	                    completionQueue: nil
	                    completionBlock:^(ZDCPublicKey *serverPubKey, NSError *error)
	{
		[weakSelf didFetchServerCopy:serverPubKey error:error];
	}];
}

- (void)didFetchServerCopy:(ZDCPublicKey *)serverPubKey error:(NSError *)error
{
	ZDCLogAutoTrace();
	
	[_actPubKeyServer stopAnimating];
	_actPubKeyServer.hidden = YES;
	
	// check key validity (does the keyID match the key)
	if (!error)
	{
		[serverPubKey checkKeyValidityWithError:&error];
	}
	
	// check key self signature
	if (!error)
	{
		BOOL sigFound = [zdc.cryptoTools checkPublicKeySelfSig:serverPubKey error:&error];
		if (error || !sigFound)
		{
			error = [NSError errorWithClass:[self class] code:0 description:@"Key self-signature is missing"];
		}
	}
	
	// check that keyIDs match
	if (!error)
	{
		if (![pubKey.keyID isEqualToString:serverPubKey.keyID])
		{
			error = [NSError errorWithClass:[self class] code:0 description:@"Key on server doesn't match device."];
		}
	}
	
	if (error)
	{
		[_btnPubKeyServer setImage:warningImage forState:UIControlStateNormal];
		_txtPubKeyServer.text = @"KeyServer Verification Failed";
		
		_txtPubKeyServerError.text = error.localizedDescription;
		_txtPubKeyServerError.textColor = UIColor.redColor;
		[_txtPubKeyServerError sizeToFit];
		_txtPubKeyServerError.hidden = NO;
		_cnstPubKeyServerBottom.constant = _txtPubKeyServerError.frame.size.height + 30;
	}
	else
	{
		_txtPubKeyServer.text = @"Key Server Copy Verified";
		[_btnPubKeyServer setImage:okImage forState:UIControlStateNormal];
	}
	
	_btnPubKeyServer.hidden = NO;
}

- (void)refreshBlockchainInfo
{
	ZDCLogAutoTrace();

	if (!_remoteUserID || !_localUserID) return;
	
	__block ZDCUser *remoteUser = nil;
	__block ZDCUser *localUser = nil;
	
	[uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		localUser = [transaction objectForKey:_localUserID inCollection:kZDCCollection_Users];
		remoteUser = [transaction objectForKey:_remoteUserID inCollection:kZDCCollection_Users];
		if(remoteUser)
		{
			pubKey = [transaction objectForKey:remoteUser.publicKeyID inCollection:kZDCCollection_PublicKeys];
		}
		
	#pragma clang diagnostic pop
	}];
	
	// once the merkleTreeRoot is cached, it's immutable.  dont look it up again.
	if(remoteUser.blockchainTransaction)
	{
		_txtVerifyBlockChain.text = @"Blockchain Entry Verified";
		[_btnVerifyBlockChain setImage: okImage forState:UIControlStateNormal];
		_btnVerifyBlockChain.hidden = NO;
		_actVerifyBlockChain.hidden = YES;
		
		//        _btnShowTransaction.hidden = NO;
		blockchainTransaction = remoteUser.blockchainTransaction   ;
		return;
	}
	
	_txtVerifyBlockChain.text = @"Verifying Blockchain Entry…";
	_btnVerifyBlockChain.hidden = YES;
	_actVerifyBlockChain.hidden = NO;
	_btnShowTransaction.hidden = YES;
	_txtVerifyBlockChainError.hidden = YES;
	_cnstVerifyBlockChainBottom.constant = 20;
	
	[_actVerifyBlockChain startAnimating];
	blockchainTransaction = nil;
	
	__weak typeof(self) weakSelf = self;
	[zdc.blockchainManager fetchBlockchainRootForUserID: _remoteUserID
	                                        requesterID: _localUserID
	                                    completionQueue: nil
	                                    completionBlock:^(NSString *merkleTreeRoot, NSError *error)
	{
		[weakSelf didFetchBlockchainInfo:merkleTreeRoot error:error];
	}];
}

- (void)didFetchBlockchainInfo:(NSString *)merkleTreeRoot error:(NSError *)error
{
	ZDCLogAutoTrace();
	
	[_actVerifyBlockChain stopAnimating];
	_actVerifyBlockChain.hidden = YES;
	
	if (error)
	{
		[_btnVerifyBlockChain setImage:warningImage forState:UIControlStateNormal];
		_txtVerifyBlockChain.text = @"Blockchain Verification Failed";
		
		_txtVerifyBlockChainError.text = error.localizedDescription;
		_txtVerifyBlockChainError.textColor = UIColor.redColor;
		[_txtVerifyBlockChainError sizeToFit];
		_txtVerifyBlockChainError.hidden = NO;
		_cnstVerifyBlockChainBottom.constant = _txtVerifyBlockChainError.frame.size.height + 30;
	}
	else if (!merkleTreeRoot)
	{
		[_btnVerifyBlockChain setImage:questionImage forState:UIControlStateNormal];
		_txtVerifyBlockChain.text = @"No Blockchain Entry";
		
		__block ZDCUser *remoteUser = nil;
		[uiDatabaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		#pragma clang diagnostic push
		#pragma clang diagnostic ignored "-Wimplicit-retain-self"
			
			remoteUser = [transaction objectForKey:_remoteUserID inCollection:kZDCCollection_Users];
			
		#pragma clang diagnostic pop
		}];
		
		if (remoteUser.isLocal && ![(ZDCLocalUser *)remoteUser isPayingCustomer])
		{
			_txtVerifyBlockChainError.text = @"One of the benefits of becoming a customer is that your public key identity is further protected by adding it to the Ethereum Blockchain.";
		}
		else
		{
			_txtVerifyBlockChainError.text = @"This key has not yet been added to the Ethereum Blockchain.";
		}
		
		_txtVerifyBlockChainError.textColor = UIColor.blackColor;
		[_txtVerifyBlockChainError sizeToFit];
		_txtVerifyBlockChainError.hidden = NO;
		_cnstVerifyBlockChainBottom.constant = _txtVerifyBlockChainError.frame.size.height  + 30;
	}
	else
	{
		_txtVerifyBlockChain.text = @"Blockchain Entry Verified";
		[_btnVerifyBlockChain setImage:okImage forState:UIControlStateNormal];
		
		blockchainTransaction = merkleTreeRoot;
	//	_btnShowTransaction.hidden = NO;
		
		// Cache the merkleTreeRoot — it's immutable
		NSString *remoteUserID = _remoteUserID;
		
		YapDatabaseConnection *rwConnection = zdc.databaseManager.rwDatabaseConnection;
		[rwConnection asyncReadWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
			
			ZDCUser *remoteUser = [transaction objectForKey:remoteUserID inCollection:kZDCCollection_Users];
			if (remoteUser)
			{
				remoteUser = [remoteUser copy];
				remoteUser.blockchainTransaction = merkleTreeRoot;
				
				[transaction setObject:remoteUser forKey:remoteUserID inCollection:kZDCCollection_Users];
			}
		}];
	}
	
	_btnVerifyBlockChain.hidden = NO;
}

-(IBAction)btnShowTransactionHit:(id)sender
{
	if(blockchainTransaction .length)
	{
		//        NSURL* verifyURL = [[AppConstants blockChainVerifyURL] URLByAppendingPathComponent:blockChainTransactionID];
		//        [[UIApplication sharedApplication] openURL:verifyURL];
		//       FIX_LATER("show merkleTreeRoot")
	}
	
}

@end
