/// ZeroDark.cloud
///
/// Homepage      : https://www.zerodark.cloud
/// GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
/// Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
/// API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
///
/// Sample App: ZeroDarkTodo


// save this for inital view to be passed to ZDCManager.uiTools().accountSetupViewController

import UIKit
import ZeroDarkCloud

class InitialViewController: UIViewController {

	@IBOutlet public var lblName : UILabel!
	@IBOutlet public var btnSignIn : UIButton!
	@IBOutlet public var btnCreate : UIButton!

	public var proxy : ZDCAccountSetupViewControllerProxy?
	
	class func createViewContoller() -> InitialViewController! {
		
		let storyboard = UIStoryboard(name: "InitialViewController", bundle: nil)
		let vc = storyboard.instantiateViewController(withIdentifier: "InitialViewController") as? InitialViewController
		
		return vc!
	}

	override func viewDidLoad() {
		super.viewDidLoad()
	}

	private let appDisplayName: String? = {
		
		if let bundleDisplayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
			return bundleDisplayName
		} else if let bundleName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String {
			return bundleName
		}
		return nil
	}()

	
	override func viewWillAppear(_ animated: Bool) {
		
		if let appName = self.appDisplayName   {
			lblName.text = appName
		}

	}
	
	@IBAction func btnSignInClicked(_ sender: Any) {

		if let proxy = proxy {
			proxy.pushSignInToAccount()
		}
	}

	@IBAction func btnCreateClicked(_ sender: Any) {
		if let proxy = proxy {
			proxy.pushCreateAccount()
		}
	}

}
