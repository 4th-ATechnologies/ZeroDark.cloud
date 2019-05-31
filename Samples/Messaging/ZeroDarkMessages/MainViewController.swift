/**
* ZeroDark.cloud
* <GitHub wiki link goes here>
*
* Sample App: ZeroDarkMessages
**/

import UIKit
import YapDatabase
import ZeroDarkCloud

 
class MainViewController: UIViewController {

	var databaseConnection: YapDatabaseConnection!
	var btnTitle: IconTitleButton?
  	var localUserID: String = ""
	var msgVC: DarkMessageViewController?

	@IBOutlet public var vcContainer : UIView!

	// for simulating push
	@IBOutlet public var vwSimulate : UIView!
	@IBOutlet public var cnstVwSimulateHeight : NSLayoutConstraint!
	@IBOutlet public var btnSimPush : UIButton!
	@IBOutlet public var actPush : UIActivityIndicatorView!

	
	/// Required for the `MessageInputBar` to be visible
	override var canBecomeFirstResponder: Bool {
 
		return msgVC?.canBecomeFirstResponder ?? false
	}
	
	/// Required for the `MessageInputBar` to be visible
	override var inputAccessoryView: UIView? {
		return msgVC?.inputAccessoryView ?? nil
 	}

	
	class func initWithLocalUserID(_ localUserID: String) -> MainViewController {
		let storyboard = UIStoryboard(name: "Main", bundle: nil)
		let vc = storyboard.instantiateViewController(withIdentifier: "MainViewController") as? MainViewController
		
		vc?.localUserID = localUserID
		return vc!
	}

	override func viewDidLoad() {
		super.viewDidLoad()
	
		let settingButton = UIButton()
		settingButton.setImage(UIImage(named: "threebars")!
			.withRenderingMode(UIImage.RenderingMode.alwaysTemplate),
									  for: .normal)
		
		settingButton.addTarget(self,
										action: #selector(self.didHitSettings(_:)),
										for: .touchUpInside)
		let settingButtonItem = UIBarButtonItem(customView: settingButton)
		let width1 = settingButtonItem.customView?.widthAnchor.constraint(equalToConstant: 22)
		width1?.isActive = true
		let height1 = settingButtonItem.customView?.heightAnchor.constraint(equalToConstant: 22)
		height1?.isActive = true
		
		self.navigationItem.leftBarButtonItems = [
			settingButtonItem	]
		
		#if DEBUG
		self.vwSimulate.isHidden = false
		self.cnstVwSimulateHeight.constant = 44
		#else
		self.vwSimulate.isHidden = true
		self.cnstVwSimulateHeight.constant = 0
		#endif

		if let vc:DarkMessageViewController = DarkMessageViewController.initWithLocalUserID(localUserID) as DarkMessageViewController?{
		
			self.msgVC = vc
			vc.willMove(toParent: self)
			addChild(vc)
			vcContainer.addSubview(vc.view)
			vc.didMove(toParent: self)
		}
	}

	override func viewWillAppear(_ animated: Bool) {
		
		self.setupDatabaseConnection()
		
		var localUser: ZDCLocalUser!
		databaseConnection .read { (transaction) in
			localUser = transaction.object(forKey: self.localUserID, inCollection: kZDCCollection_Users) as? ZDCLocalUser
		}
		
		self.setNavigationTitle(user: localUser)

		#if DEBUG
		if((ZDCManager.zdc().syncManager?.isPullingOrPushingChangesForAnyLocalUser())!)
		{
			self.actPush.startAnimating()
			self.btnSimPush.isEnabled = false;
		}
		else
		{
			self.actPush.stopAnimating()
			self.btnSimPush.isEnabled = true;
		}
		
		NotificationCenter.default.addObserver(self,
															selector: #selector(self.pullStarted(notification:)),
															name:.ZDCPullStartedNotification ,
															object: nil)
		
		NotificationCenter.default.addObserver(self,
															selector: #selector(self.pullStopped(notification:)),
															name:.ZDCPullStoppedNotification ,
															object: nil)
		
		NotificationCenter.default.addObserver(self,
															selector: #selector(self.pushStarted(notification:)),
															name:.ZDCPushStartedNotification ,
															object: nil)
		
		NotificationCenter.default.addObserver(self,
															selector: #selector(self.pushStopped(notification:)),
															name:.ZDCPushStoppedNotification ,
															object: nil)
		#endif
		
	}
	
	override func viewDidDisappear(_ animated: Bool) {
		
		
	
		#if DEBUG
		self.actPush.stopAnimating()
		self.btnSimPush.isEnabled = true;
		#endif
		
		NotificationCenter.default.removeObserver(self)

	}
	
	private func setNavigationTitle(user: ZDCLocalUser) {
		
		if (btnTitle == nil) {
			
			btnTitle = IconTitleButton.init(type:.custom)
			btnTitle?.setTitleColor(self.view.tintColor, for: .normal)
			btnTitle?.addTarget(self,
									  action: #selector(self.didHitTitle(_:)),
									  for: .touchUpInside)
		}
		
		btnTitle?.setTitle(user.displayName, for: .normal)
		btnTitle?.isEnabled = true
		self.navigationItem.titleView = btnTitle
		
		let size = CGSize(width: 30, height: 30)
		let defaultImage = {
			return ZDCManager.imageManager().defaultUserAvatar().scaled(to: size, scalingMode: .aspectFit)
		}
		let processing = {(image: UIImage) in
			return image.scaled(to: size, scalingMode: .aspectFit)
		}
		let preFetch = {[weak self](image: UIImage?, willFetch: Bool) -> Void in
			self?.btnTitle?.setImage(image ?? defaultImage(), for: .normal)
		}
		let postFetch = {[weak self](image: UIImage?, error: Error?) -> Void in
			self?.btnTitle?.setImage(image ?? defaultImage(), for: .normal)
		}
		
		ZDCManager.imageManager().fetchUserAvatar(user,
																withProcessingID: "30*30",
																processingBlock: processing,
																preFetch: preFetch,
																postFetch: postFetch)
	}
	
	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		
		msgVC?.view.frame =  vcContainer.frame
	}


	// MARK: Actions
	
	@objc func didHitSettings(_ sender: Any)
	{
		AppDelegate.sharedInstance().toggleSettingsView()
	}
	
	@objc func didHitTitle(_ sender: Any)
	{
		ZDCManager.uiTools().pushSettings(forLocalUserID: localUserID,
													 with: self.navigationController! )
	}
	
 	// MARK: Database
	
	
	private func setupDatabaseConnection()
	{
		databaseConnection = ZDCManager.uiDatabaseConnection()
		
		
	}


	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// MARK: Pull/Push
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	@objc func pullStarted(notification: Notification) {
		
		if(!self.actPush.isAnimating){
			self.actPush.startAnimating()
			self.btnSimPush.isEnabled = false;
		}
		
	}
	
	@objc func pullStopped(notification: Notification) {
		
		if(self.actPush.isAnimating){
			self.actPush.stopAnimating()
			self.btnSimPush.isEnabled = true;
		}
		
	}
	
	@objc func pushStarted(notification: Notification) {
		
		if(!self.actPush.isAnimating){
			self.actPush.startAnimating()
			self.btnSimPush.isEnabled = false;
		}
	}
	
	@objc func pushStopped(notification: Notification) {
		if(self.actPush.isAnimating){
			self.actPush.stopAnimating()
			self.btnSimPush.isEnabled = true;
		}
		
	}

}

