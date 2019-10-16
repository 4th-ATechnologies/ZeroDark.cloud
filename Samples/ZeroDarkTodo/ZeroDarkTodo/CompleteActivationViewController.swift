/// ZeroDark.cloud
///
/// Homepage      : https://www.zerodark.cloud
/// GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
/// Documentation : https://zerodarkcloud.readthedocs.io/en/latest
/// API Reference : https://apis.zerodark.cloud
///
/// Sample App: ZeroDarkTodo

import UIKit

class CompleteActivationViewController: UIViewController {

	var localUserID : String!

	@IBOutlet public var btnCompleteActivation : UIButton!

	class func `initWithLocalUserID`(_ localUserID: String) -> CompleteActivationViewController {
		let storyboard = UIStoryboard(name: "Main", bundle: nil)
		let vc = storyboard.instantiateViewController(withIdentifier: "CompleteActivationViewController") as? CompleteActivationViewController

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


    }

	override func viewWillAppear(_ animated: Bool) {

		self.navigationItem.title =  NSLocalizedString("Please complete activation", comment: "")

	}

	// MARK: - actions
	@objc func didHitSettings(_ sender: Any)
	{
		AppDelegate.sharedInstance().toggleSettingsView()
	}


	@IBAction func btnCompleteActivationAction(_ sender: Any) {

		RootContainerViewController.shared()?.showResumeActivationView(localUserID: localUserID) 

	}

}
