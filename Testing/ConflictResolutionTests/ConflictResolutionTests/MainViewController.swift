/// ZeroDark.cloud
///
/// Homepage      : https://www.zerodark.cloud
/// GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
/// Documentation : https://zerodarkcloud.readthedocs.io/en/latest
/// API Reference : https://apis.zerodark.cloud
///

import UIKit
import os

class MainViewController: UINavigationController {
	
	class func create(localUserID: String) -> MainViewController? {
		
		let storyboard = UIStoryboard(name: "Main", bundle: nil)
		let mvc = storyboard.instantiateViewController(identifier: "MainViewController") as? MainViewController
		let tvc = storyboard.instantiateViewController(identifier: "TestViewController") as? TestViewController
		
		mvc?.localUserID = localUserID
		tvc?.localUserID = localUserID
		
		if let tvc = tvc {
			mvc?.viewControllers = [tvc]
		}
		
		return mvc
	}
	
	var localUserID: String = ""
	
	override func viewDidLoad() {
		super.viewDidLoad()
		
		os_log("MainViewController: viewDidLoad()")
	}
}
