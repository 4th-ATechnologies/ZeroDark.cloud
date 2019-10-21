/// ZeroDark.cloud
///
/// Homepage      : https://www.zerodark.cloud
/// GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
/// Documentation : https://zerodarkcloud.readthedocs.io/en/latest
/// API Reference : https://apis.zerodark.cloud
///
/// Sample App: WhatsZapp

import UIKit
import CocoaLumberjack

class RootViewController: UIViewController {
	
	fileprivate var currentViewController: UIViewController? = nil
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
	// Configure log level (for CocoaLumberjack).
	#if DEBUG
		dynamicLogLevel = .all
	#else
		dynamicLogLevel = .warning
	#endif
		
		DDLogInfo("viewDidLoad()")
		
		let zdc = ZDCManager.zdc()
		let uiDatabaseConnection = zdc.databaseManager!.uiDatabaseConnection
		
		var localUserID: String? = nil
		uiDatabaseConnection.read { (transaction) in
			
			localUserID = zdc.localUserManager?.anyLocalUserID(transaction)
		}
		
		if let localUserID = localUserID {
			showMainView(localUserID)
		} else {
			showActivationView(canDismissWithoutNewAccount: false)
		}
	}
	
	func removeCurrentViewController() {
		
		if let currentViewController = currentViewController {
			
			currentViewController.willMove(toParent: nil)
			currentViewController.removeFromParent()
			currentViewController.view.removeFromSuperview()
			currentViewController.didMove(toParent: nil)
		}
	}
	
	func displayViewController(_ viewController: UIViewController) {
		
		if viewController != currentViewController {
			
			removeCurrentViewController()
			
			viewController.willMove(toParent: self)
			addChild(viewController)
			view.addSubview(viewController.view)
			viewController.didMove(toParent: self)
			currentViewController = viewController
		}
	}
	
	func showMainView(_ localUserID: String) {
		
		if let mainVC = MainViewController.create(localUserID: localUserID) {
			
			displayViewController(mainVC)
		}
		else {
			
			DDLogError("ConversationsViewController.create() returned nil")
			removeCurrentViewController()
		}
	}
	
	func showActivationView(canDismissWithoutNewAccount: Bool) {
		
		let uiTools = ZDCManager.zdc().uiTools!
		
		let setupVC = uiTools.accountSetupViewController(withInitialViewController: nil,
		                                               canDismissWithoutNewAccount: canDismissWithoutNewAccount)
		{[weak self] (localUserID: String?, completedActivation: Bool, shouldBackupAccessKey: Bool) in
			
			DDLogInfo("localUserID = \(localUserID ?? "<nil>")")
			
			if let localUserID = localUserID {
				self?.showMainView(localUserID)
			}
			else {
				self?.showActivationView(canDismissWithoutNewAccount: false)
			}
		}
		
		displayViewController(setupVC)
	}
}

