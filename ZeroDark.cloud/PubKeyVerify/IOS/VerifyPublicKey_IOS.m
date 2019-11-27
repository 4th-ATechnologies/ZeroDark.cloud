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
	
	IBOutlet __weak UIButton*               _btnPubKeyServer;
	IBOutlet __weak UILabel*                _txtPubKeyServer;
	IBOutlet __weak UIActivityIndicatorView* _actPubKeyServer;
	IBOutlet __weak NSLayoutConstraint*    _cnstPubKeyServerBottom;
	IBOutlet __weak UILabel*                _txtPubKeyServerError;
	
	
	IBOutlet __weak UIButton*               _btnVerifyBlockChain;
	IBOutlet __weak UILabel*                _txtVerifyBlockChain;
	IBOutlet __weak UIActivityIndicatorView* _actVerifyBlockChain;
	IBOutlet __weak NSLayoutConstraint*    _cnstVerifyBlockChainBottom;
	IBOutlet __weak UILabel*                _txtVerifyBlockChainError;
	
	IBOutlet __weak UIButton*               _btnShowTransaction;
	
	ZeroDarkCloud*                     owner;
	
	ZDCImageManager*                   imageManager;
	YapDatabaseConnection*             databaseConnection;
	ZDCPublicKey*                      pubKey;
	NSString *                         blockchainTransaction;
	
	NSDateFormatter*                   formatter;
	
	NSString*                          _localUserID;
	NSString*                          _remoteUserID;
	NSString*                          _preferedAuth0ID;
	
	UIImage*                           defaultUserImage;
	UIImage*                           okImage;
	UIImage*                           warningImage;
	UIImage*                           failImage;
	UIImage*                           questionImage;
	
	UISwipeGestureRecognizer*          swipeRight;
}

- (NSError *)errorWithDescription:(NSString *)description
{
	NSDictionary *userInfo = nil;
	if (description)
		userInfo = @{ NSLocalizedDescriptionKey: description };
	
	NSString *domain = NSStringFromClass([self class]);
	return [NSError errorWithDomain:domain code:0 userInfo:userInfo];
}


- (instancetype)initWithOwner:(ZeroDarkCloud*)inOwner
					  remoteUserID:(NSString* __nonnull)inRemoteUserID
						localUserID:(NSString* __nonnull)inLocalUserID
{
	NSBundle *bundle = [ZeroDarkCloud frameworkBundle];
	UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"VerifyPublicKey_IOS" bundle:bundle];
	self = [storyboard instantiateViewControllerWithIdentifier:@"VerifyPublicKey"];
	if (self)
	{
		owner = inOwner;
		_localUserID = inLocalUserID;
		_remoteUserID = inRemoteUserID;
	}
	return self;
	
}

- (void)viewDidLoad
{
	[super viewDidLoad];
	
	imageManager =  owner.imageManager;
	databaseConnection = owner.databaseManager.uiDatabaseConnection;
	
	formatter = [ZDCDateFormatterCache dateFormatterWithDateStyle:NSDateFormatterShortStyle
																		 timeStyle:NSDateFormatterShortStyle];
	
	
	_txtPubKeyID.lineBreakMode = NSLineBreakByWordWrapping;
	_txtPubKeyID.numberOfLines = 0;
	_txtPubKeyID.font =   [UIFont monospacedDigitSystemFontOfSize:_txtPubKeyID.font.pointSize
																			 weight:UIFontWeightRegular];
	
	_txtUserID.lineBreakMode = NSLineBreakByWordWrapping;
	_txtUserID.numberOfLines = 0;
	_txtUserID.font =   [UIFont monospacedDigitSystemFontOfSize:_txtUserID.font.pointSize
																		  weight:UIFontWeightRegular];
	
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

	defaultUserImage = [imageManager.defaultUserAvatar scaledToSize: _imgAvatar.frame.size
																		 scalingMode: ScalingMode_AspectFill];
		
	okImage =  [UIImage imageNamed:@"roundedGreenCheck"
								 inBundle:[ZeroDarkCloud frameworkBundle]
	 compatibleWithTraitCollection:nil];
	
	warningImage =  [UIImage imageNamed:@"warning"
										inBundle:[ZeroDarkCloud frameworkBundle]
			compatibleWithTraitCollection:nil];
	
	questionImage = [UIImage imageNamed:@"question-circle"
										inBundle:[ZeroDarkCloud frameworkBundle]
			compatibleWithTraitCollection:nil];
	
	
	//    self.navigationItem.hidesBackButton = YES;
	//
	__weak typeof(self) weakSelf = self;
	
	[_txtPubKeyID setLabelCopied:^(NSString * copyString) {
		__strong typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		
		UIPasteboard *board = [UIPasteboard generalPasteboard];
		[board setString:strongSelf->_txtPubKeyID.text];
		
	}];
	
}


-(void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	
	self.navigationItem.title = @"Verify Public Key";
	
	UIImage* image = [[UIImage imageNamed:@"backarrow"
										  inBundle:[ZeroDarkCloud frameworkBundle]
			  compatibleWithTraitCollection:nil] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
	
	UIBarButtonItem* backItem = [[UIBarButtonItem alloc] initWithImage:image
																					 style:UIBarButtonItemStylePlain
																					target:self
																					action:@selector(handleNavigationBack:)];
	
	self.navigationItem.leftBarButtonItem = backItem;
	
	swipeRight = [[UISwipeGestureRecognizer alloc]initWithTarget:self action:@selector(swipeRight:)];
	[self.view addGestureRecognizer:swipeRight];
	
	[self refreshUserInfo];
	[self refreshKeyInfo];
	[self refreshPubKeyIntegrity];
	[self refreshServerCopy];
	[self refreshBlockChainInfo];
}


-(void) viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	[self.view removeGestureRecognizer:swipeRight]; swipeRight = nil;
	
	//   [[NSNotificationCenter defaultCenter]  removeObserver:self];
	
}


-(void)swipeRight:(UISwipeGestureRecognizer *)gesture
{
	[self handleNavigationBack:NULL];
}

- (void)handleNavigationBack:(UIButton *)backButton
{
	[[self navigationController] popViewControllerAnimated:YES];
}



- (void)refreshUserInfo
{
	__weak typeof(self) weakSelf = self;
	
	__block ZDCUser* remoteUser = nil;
	__block ZDCUser* localUser = nil;
	[databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		localUser = [transaction objectForKey:_localUserID inCollection:kZDCCollection_Users];
		remoteUser = [transaction objectForKey:_remoteUserID inCollection:kZDCCollection_Users];
		
		if (!_preferedAuth0ID || ![remoteUser identityWithID:_preferedAuth0ID])
		{
			_preferedAuth0ID = remoteUser.preferredIdentityID;
		}
		
	#pragma clang diagnostic pop
	}];
	
	NSString *displayName = [[remoteUser identityWithID:_preferedAuth0ID] displayName];
	if (!displayName) {
		displayName = remoteUser.displayName;
	}
	
	if(displayName)
		_lblDisplayName.text = displayName;
	else
		_lblDisplayName.text = remoteUser.uuid;
	
	void (^preFetchBlock)(UIImage*, BOOL) = ^(UIImage *image, BOOL willFetch){
		
		__strong typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		
		strongSelf->_imgAvatar.image = image ?: strongSelf->defaultUserImage;
	};
	void (^postFetchBlock)(UIImage*, NSError*) = ^(UIImage *image, NSError *error){
		
		__strong typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		
		strongSelf->_imgAvatar.image = image ?: strongSelf->defaultUserImage;
	};
	
	[imageManager fetchUserAvatar: remoteUser
	                  withOptions: nil
	                preFetchBlock: preFetchBlock
	               postFetchBlock: postFetchBlock];
}

-(void)refreshKeyInfo
{
	if(!_remoteUserID)return;
	__block ZDCUser* user = nil;
	
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-retain-self"
	
	[databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		user = [transaction objectForKey:_remoteUserID inCollection:kZDCCollection_Users];
		if(user)
		{
			pubKey = [transaction objectForKey:user.publicKeyID inCollection:kZDCCollection_PublicKeys];
		}
	}];
	
#pragma clang diagnostic pop
	
	if(pubKey)
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


-(void) refreshPubKeyIntegrity
{
	__weak typeof(self) weakSelf = self;
	
	_txtPubKeyIntegrity.text = @"Verifying Key Integrity…";
	_btnPubKeyIntegrity.hidden = YES;
	_actPubKeyIntegrity.hidden = NO;
	_txtPubKeyIntegrityError.hidden = YES;
	_cnstPubKeyIntegrityBottom.constant = 20;
	[_actPubKeyIntegrity startAnimating];
	
	dispatch_async(dispatch_get_main_queue(), ^{
		
		__strong typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		
		NSError* error = NULL;
		
		// check key validity (does the keyID match the key)
		[strongSelf->pubKey checkKeyValidityWithError:&error];
		
		// check key self signature
		if(!error)
		{
			BOOL sigFound = [strongSelf->owner.cryptoTools checkPublicKeySelfSig:strongSelf->pubKey
																								error:&error];
			if(error || !sigFound)
			{
				error = [strongSelf errorWithDescription:@"Key self-signature is missing"];
			}
		}
		
		[strongSelf->_actPubKeyIntegrity stopAnimating];
		strongSelf->_actPubKeyIntegrity.hidden = YES;
		
		if(error)
		{
			[strongSelf->_btnPubKeyIntegrity setImage: strongSelf->warningImage forState:UIControlStateNormal];
			strongSelf->_txtPubKeyIntegrity.text = @"Key Integrity Verification Failed";
			strongSelf->_txtPubKeyIntegrityError.text = error.localizedDescription;
			strongSelf->_txtPubKeyIntegrityError.textColor = UIColor.redColor;
			[strongSelf->_txtPubKeyIntegrityError sizeToFit];
			strongSelf->_txtPubKeyIntegrityError.hidden = NO;
			strongSelf->_cnstPubKeyIntegrityBottom.constant = strongSelf->_txtPubKeyIntegrityError.frame.size.height  + 30;
			
		}
		else
		{
			strongSelf->_txtPubKeyIntegrity.text = @"Key Integrity Verified";
			[strongSelf->_btnPubKeyIntegrity setImage:strongSelf->okImage forState:UIControlStateNormal];
		}
		strongSelf->_btnPubKeyIntegrity.hidden = NO;
	});
}

-(void) refreshServerCopy
{
	__weak typeof(self) weakSelf = self;
	
	_txtPubKeyServer.text = @"Verifying KeyServer Copy…";
	_btnPubKeyServer.hidden = YES;
	_actPubKeyServer.hidden = NO;
	_txtPubKeyServerError.hidden = YES;
	_cnstPubKeyServerBottom.constant = 20;
	[_actPubKeyServer startAnimating];
	
	[owner.userManager fetchPublicKeyForRemoteUserID: _remoteUserID
	                                     requesterID: _localUserID
	                                 completionQueue: nil
	                                 completionBlock:^(ZDCPublicKey *serverPubKey, NSError *error)
	{
		__strong typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;
		 
		 [strongSelf->_actPubKeyServer stopAnimating];
		 strongSelf->_actPubKeyServer.hidden = YES;
		 
		 // check key validity (does the keyID match the key)
		 if(!error)
		 {
			 [serverPubKey checkKeyValidityWithError:&error];
		 }
		 
		 // check key self signature
		 if(!error)
		 {
			 BOOL sigFound = [strongSelf->owner.cryptoTools checkPublicKeySelfSig:serverPubKey
																								 error:&error];
			 if(error || !sigFound)
			 {
				 error = [self errorWithDescription:@"Key self-signature is missing"];
			 }
		 }
		 
		 // check that keyIDs match
		 if(!error)
		 {
			 if(![strongSelf->pubKey.keyID isEqualToString:serverPubKey.keyID])
			 {
				 error = [self errorWithDescription:@"Key on server doesnt match device."];
			 }
		 }
		 
		 if(error )
		 {
			 [strongSelf->_btnPubKeyServer setImage: strongSelf->warningImage forState:UIControlStateNormal];
			 strongSelf->_txtPubKeyServer.text = @"KeyServer Verification Failed";
			 
			 strongSelf->_txtPubKeyServerError.text = error.localizedDescription;
			 strongSelf->_txtPubKeyServerError.textColor = UIColor.redColor;
			 [strongSelf->_txtPubKeyServerError sizeToFit];
			 strongSelf->_txtPubKeyServerError.hidden = NO;
			 strongSelf->_cnstPubKeyServerBottom.constant = strongSelf->_txtPubKeyServerError.frame.size.height  + 30;
			 
		 }
		 else
		 {
			 strongSelf->_txtPubKeyServer.text = @"Key Server Copy Verified";
			 [strongSelf->_btnPubKeyServer setImage: strongSelf->okImage forState:UIControlStateNormal];
		 }
		 strongSelf->_btnPubKeyServer.hidden = NO;
	 }];
	
	
}


- (void)refreshBlockChainInfo
{
	ZDCLogAutoTrace();
	__weak typeof(self) weakSelf = self;

	if (!_remoteUserID || !_localUserID) return;
	
	__block ZDCUser* remoteUser = nil;
	__block ZDCUser* localUser = nil;
	
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-retain-self"
	
	[databaseConnection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		localUser = [transaction objectForKey:_localUserID inCollection:kZDCCollection_Users];
		remoteUser = [transaction objectForKey:_remoteUserID inCollection:kZDCCollection_Users];
		if(remoteUser)
		{
			pubKey = [transaction objectForKey:remoteUser.publicKeyID inCollection:kZDCCollection_PublicKeys];
		}
	}];
#pragma clang diagnostic pop
	
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
	blockchainTransaction   = nil;
	
	[owner.blockchainManager fetchBlockchainRootForUserID:_remoteUserID
															requesterID: localUser.uuid
													  completionQueue:nil
													  completionBlock:^(NSString * _Nonnull mtr, NSError * _Nonnull error)
	 {
		 __strong typeof(self) strongSelf = weakSelf;
		 if (!strongSelf) return;
		 
		 [strongSelf->_actVerifyBlockChain stopAnimating];
		 strongSelf->_actVerifyBlockChain.hidden = YES;
		 
		 if (error)
		 {
			 [strongSelf->_btnVerifyBlockChain setImage:
			  strongSelf->warningImage forState:UIControlStateNormal];
			 strongSelf->_txtVerifyBlockChain.text = @"Blockchain Verification Failed";
			 
			 strongSelf->_txtVerifyBlockChainError.text = error.localizedDescription;
			 strongSelf->_txtVerifyBlockChainError.textColor = UIColor.redColor;
			 [strongSelf->_txtVerifyBlockChainError sizeToFit];
			 strongSelf->_txtVerifyBlockChainError.hidden = NO;
			 strongSelf->_cnstVerifyBlockChainBottom.constant = strongSelf->_txtVerifyBlockChainError.frame.size.height  + 30;
		 }
		 else if(!mtr)
		 {
			 [strongSelf->_btnVerifyBlockChain setImage: strongSelf->questionImage forState:UIControlStateNormal];
			 strongSelf->_txtVerifyBlockChain.text = @"No Blockchain Entry";
			 
			 if (remoteUser.isLocal && ! [(ZDCLocalUser*)remoteUser isPayingCustomer])
			 {
				 strongSelf->_txtVerifyBlockChainError.text = @"One of the benefits of becoming a customer is that your public key identity is further protected by adding it to the Ethereum Blockchain.";
			 }
			 else
			 {
				 strongSelf->_txtVerifyBlockChainError.text = @"This key has not yet been added to the Ethereum Blockchain.";
			 }
			 
			 strongSelf->_txtVerifyBlockChainError.textColor = UIColor.blackColor;
			 [strongSelf->_txtVerifyBlockChainError sizeToFit];
			 strongSelf->_txtVerifyBlockChainError.hidden = NO;
			 strongSelf->_cnstVerifyBlockChainBottom.constant = strongSelf->_txtVerifyBlockChainError.frame.size.height  + 30;
		 }
		 else
		 {
			 strongSelf->_txtVerifyBlockChain.text = @"Blockchain Entry Verified";
			 [strongSelf->_btnVerifyBlockChain setImage: strongSelf->okImage forState:UIControlStateNormal];
			 
			 strongSelf->blockchainTransaction = mtr;
			 //             _btnShowTransaction.hidden = NO;
			 
			 // cache the merkleTreeRoot is cached, it's immutable.  dont look it up again.
			 [strongSelf->owner.blockchainManager updateBlockChainRoot:mtr
															 forUserID:strongSelf->_remoteUserID
													 completionQueue:nil
													 completionBlock:^{
														 /// nothing needed -
													 }];
		 }
		 strongSelf->_btnVerifyBlockChain.hidden = NO;
	 }];
	
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
