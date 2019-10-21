/// ZeroDark.cloud
///
/// Homepage      : https://www.zerodark.cloud
/// GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
/// Documentation : https://zerodarkcloud.readthedocs.io/en/latest
/// API Reference : https://apis.zerodark.cloud
///
/// Sample App: WhatsZapp

import Foundation
import CocoaLumberjack
import ZeroDarkCloud

class MainViewController: UINavigationController {
	
	var localUserID: String = ""
	var navTitleButton: IconTitleButton?
	
	class func create(localUserID: String) -> MainViewController? {
		let storyboard = UIStoryboard(name: "Main", bundle: nil)
		let vc = storyboard.instantiateViewController(withIdentifier: "MainViewController") as? MainViewController
		
		vc?.localUserID = localUserID
		return vc
	}
	
	// MARK: View Lifecycle
	
	override func viewDidLoad() {
	#if DEBUG
		dynamicLogLevel = .all
	#else
		dynamicLogLevel = .warning
	#endif
		
		DDLogInfo("viewDidLoad()")
		super.viewDidLoad()
		
		if let conversationsVC = ConversationsViewController.create(localUserID: localUserID) {
			
			self.viewControllers = [conversationsVC]
		}
	}
}
