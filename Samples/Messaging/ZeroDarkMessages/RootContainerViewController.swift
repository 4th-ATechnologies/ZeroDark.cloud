/**
* ZeroDark.cloud
* <GitHub wiki link goes here>
*
* Sample App: ZeroDarkMessages
**/

import UIKit
import ZeroDarkCloud

// Used for status bar hidden/visible logic
class ListNavigationViewController: UINavigationController {
}


class RootContainerViewController: UIViewController {

	fileprivate var rootViewController: UIViewController? = nil

	fileprivate static var containerController: RootContainerViewController? = nil

	@discardableResult  class func shared() -> RootContainerViewController?  {
		return containerController
	}

	required init?(coder aDecoder: NSCoder)
	{
		super.init(coder: aDecoder)!;
		RootContainerViewController.containerController = self
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		if let localUserID = AppDelegate.sharedInstance().currentLocalUserID {
			showMainView(localUserID: localUserID)

		} else {
			showActivationView(canDismissWithoutNewAccount:false)
		}
}


	/// Displays the MapViewController
	func showMainView(localUserID: String) {

		var localUser: ZDCLocalUser?
		ZDCManager.uiDatabaseConnection() .read { (transaction) in
			localUser = transaction.object(forKey: localUserID, inCollection: kZDCCollection_Users) as? ZDCLocalUser
		}

		var vc: UIViewController

		if let localUser = localUser {
			
			if (localUser.hasCompletedSetup && !localUser.accountNeedsA0Token) {
				vc = MainViewController.initWithLocalUserID(localUserID)
			} else {
				vc = CompleteActivationViewController.initWithLocalUserID(localUserID)
			}

			let nav  = UINavigationController.init(rootViewController: vc)

			if let rvc = AppDelegate.sharedInstance().revealController{

				rvc.frontViewController = nav
				rvc.setFrontViewPosition(.left, animated: true)

				if(rootViewController is SWRevealViewController)
				{
 					return
				}

				rvc.willMove(toParent: self)
				addChild(rvc)

				if let rootViewController = self.rootViewController {
					self.rootViewController = rvc
					rootViewController.willMove(toParent: nil)

					transition(from: rootViewController, to: rvc, duration: 0.55, options: [.transitionCrossDissolve, .curveEaseOut], animations: { () -> Void in

					}, completion: { _ in
						rvc.didMove(toParent: self)
						rootViewController.removeFromParent()
						rootViewController.didMove(toParent: nil)

						// This needs to be after [self.window makeKeyAndVisible],
						//        // or the gesture recognizer may be disabled.
						//				revealController.frontViewController.view.hidden = NO; // force view load
						rvc.tapGestureRecognizer()

					})
				} else {
					rootViewController = rvc
					view.addSubview(rvc.view)
					rvc.didMove(toParent: self)
					rvc.tapGestureRecognizer()

				}
				}

			}
	}


	func showActivationView(canDismissWithoutNewAccount: Bool) {
		
		// create a user controlled initial view
		if let initialVC = InitialViewController.createViewContoller() {
			
			let setupVC = ZDCManager.uiTools().accountSetupViewController(withInitialViewController:initialVC,
																							  canDismissWithoutNewAccount:canDismissWithoutNewAccount)
			{ (localUserID:String?,
				completedActivation:Bool,
				shouldBackupAccessKey:Bool) in
				
				AppDelegate.sharedInstance().currentLocalUserID = localUserID;
			}

			initialVC.proxy = setupVC
			
			rootViewController?.willMove(toParent: nil)
			rootViewController?.removeFromParent()
			rootViewController?.view.removeFromSuperview()
			rootViewController?.didMove(toParent: nil)
			
			setupVC.willMove(toParent: self)
			addChild(setupVC)
			view.addSubview(setupVC.view)
			setupVC.didMove(toParent: self)
			rootViewController = setupVC
			
		}
	}

	func showResumeActivationView(localUserID: String) {

//		guard !(rootViewController is AccountSetupViewController_IOS)
//			else { return }
//
		let setupVC = ZDCManager.uiTools().accountResumeSetup(forLocalUserID: localUserID)
		{ (localUserID:String?,
			completedActivation:Bool,
			shouldBackupAccessKey:Bool) in
			
			AppDelegate.sharedInstance().currentLocalUserID = localUserID;
		}

	 	rootViewController?.willMove(toParent: nil)
		rootViewController?.removeFromParent()
		rootViewController?.view.removeFromSuperview()
		rootViewController?.didMove(toParent: nil)

		setupVC.willMove(toParent: self)
		addChild(setupVC)
		view.addSubview(setupVC.view)
		setupVC.didMove(toParent: self)
		rootViewController = setupVC
	}

}
