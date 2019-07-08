/// ZeroDark.cloud
///
/// Homepage      : https://www.zerodark.cloud
/// GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
/// Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
/// API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
///
/// Sample App: ZeroDarkTodo

import UIKit
import Photos

import YapDatabase
import ZeroDarkCloud

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, SettingsViewControllerDelegate, SWRevealViewControllerDelegate {

	var window: UIWindow?
	var revealController: SWRevealViewController?
	var settingsViewController: SettingsViewController?
	var settingsViewNavController: UINavigationController?
	
	fileprivate var _currentLocalUserID : String? = nil

	/// Utility method (less typing)
	///
	class func sharedInstance() -> AppDelegate{
		return UIApplication.shared.delegate as! AppDelegate
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: UIApplicationDelegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	func application(_ application: UIApplication,
	                 didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool
	{
		// Setup ZeroDarkCloud
		ZDCManager.setup()

		// Register with APNs
		UIApplication.shared.registerForRemoteNotifications()
		
		// Setup UI
		self.setupViews();

		return true
	}

	func application(_ application: UIApplication,
	                 didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data)
	{
		// Forward the token to ZeroDarkCloud framework,
		// which will automatically register it with the server.
		ZDCManager.zdc().didRegisterForRemoteNotifications(withDeviceToken: deviceToken)
	}
	
	func application(_ application: UIApplication,
	                 didFailToRegisterForRemoteNotificationsWithError error: Error)
	{
		// The token is not currently available.
		print("Remote notification support is unavailable due to error: \(error.localizedDescription)")
	}
	
	func application(_ application: UIApplication,
	                 didReceiveRemoteNotification userInfo: [AnyHashable : Any],
	                 fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void)
	{
		// Forward to ZeroDarkCloud framework
		ZDCManager.zdc().didReceiveRemoteNotification(userInfo, fetchCompletionHandler: completionHandler)
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: View Setup
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	fileprivate func setupViews(){
		
		settingsViewController = SettingsViewController.`initWithDelegate`(delegate: self)
		settingsViewNavController = UINavigationController.init(rootViewController: settingsViewController!)
		
		revealController = SWRevealViewController.init(rearViewController: settingsViewNavController!,
																	  frontViewController: nil)
		
		revealController?.delegate = self
		revealController?.rearViewRevealWidth = settingsViewController!.preferedWidth
		revealController?.rearViewRevealOverdraw = 0
		revealController?.rearViewRevealDisplacement = 40
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: SWRevealViewController
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	// The SWRevealViewController is what we use to display the side menu.
	//
	// The side menu is what you get if you "hamburger icon" in the upper left-hand corner of the app.
	// (3 solid horizontal lines stacked atop each other vertically)
	
	func toggleSettingsView(){
		
		revealController?.rearViewRevealWidth = settingsViewController!.preferedWidth
		revealController?.revealToggle(animated: true)
	}
	
	func revealController(_ revealController: SWRevealViewController!, willMoveTo position: FrontViewPosition) {
		
		if((position == .right) || (position == .rightMost))
		{
			revealController.frontViewController.view.isUserInteractionEnabled = false
		}
		else if(position == .left)
		{
			revealController.frontViewController.view.isUserInteractionEnabled = true
		}
	}
	
	func revealController(_ revealController: SWRevealViewController!, didMoveTo position: FrontViewPosition) {
		
		if((position == .right) || (position == .rightMost))
		{
			revealController.frontViewController.view.isUserInteractionEnabled = false
		}
		else if(position == .left)
		{
			revealController.frontViewController.view.isUserInteractionEnabled = true
		}
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: User Management
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	/// The app allows you to login to multiple users.
	/// However, even if you login as both Alice & Bob, the UI is only showing one user at-a-time.
	/// That is, it's either showing Alice's stuff or Bob's stuff.
	/// So the UI has a notion of the "current" localUser that's being shown.
	/// This method provides a convenient way to get that localUserID.
	///
	var currentLocalUserID: String?
	{
		get {
			if (_currentLocalUserID == nil)
			{
				var allUsersIDs:Array<String> = []
				
				let databaseConnection = ZDCManager.uiDatabaseConnection()
				databaseConnection.read { (transaction) in
					allUsersIDs = ZDCManager.localUserManager().allLocalUserIDs(transaction)
				}
				
				_currentLocalUserID = allUsersIDs.first
			}
			
			return _currentLocalUserID
		}
		set(localUserID) {
		
			if localUserID != _currentLocalUserID {
				
				_currentLocalUserID = localUserID
				if _currentLocalUserID == nil {
					// fallback to current User
					_currentLocalUserID = self.currentLocalUserID
				}
			}
			
			// does tha user still exist
			var localUser: ZDCLocalUser?
			if let luid = _currentLocalUserID {
				
				ZDCManager.uiDatabaseConnection().read { (transaction) in
					localUser = transaction.object(forKey: luid, inCollection: kZDCCollection_Users) as? ZDCLocalUser
				}
			}
		
			if let localUser = localUser {
				RootContainerViewController.shared()?.showMainView(localUserID: localUser.uuid)
			}
			else {
				RootContainerViewController.shared()?.showActivationView(canDismissWithoutNewAccount:false)
			}
		}
	}

	func deleteUserID(userID:String!, completion: @escaping (Bool) -> ()) {

		ZDCManager.rwDatabaseConnection().asyncReadWrite({ (transaction) in

			let listsIDs = ListsViewController.allListsWithLocalUserID(userID: userID, transaction: transaction)

			ZDCManager.localUserManager().deleteLocalUser(userID, transaction: transaction)

			for listID in listsIDs {

				transaction.removeObject(forKey: listID,
										 inCollection: kZ2DCollection_List)

			}

		}, completionBlock: {

			completion(true)
		})
	}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Utility Functions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	class func checkForCameraAvailable(viewController:UIViewController!,
                                       completion: @escaping (Bool) -> ()) {
        
        let photoAuthorizationStatus = PHPhotoLibrary.authorizationStatus()
        
        switch photoAuthorizationStatus {
        case .authorized:
            completion(true)
            break
            
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization({
                (newStatus) in
                if newStatus ==  PHAuthorizationStatus.authorized {
                    completion(true)
                }
                else
                {
                    completion(false)
                }
            })
            
        case .restricted:
            let alert = UIAlertController(title: "Can not add Photo",
                                          message: "Access to Photo Library is restricted",
                                          preferredStyle: .alert)
            
            let okAction = UIAlertAction(title: "OK", style: .default) { (alert: UIAlertAction!) -> Void in
                completion(false)
            }
            alert.addAction(okAction)
            viewController.present(alert, animated: true, completion:nil)
            
            
        case .denied:
            let alert = UIAlertController(title: "Photo Access Off",
                                          message: "Change your settings to allow access to Photos",
                                          preferredStyle: .alert)
            
            let okAction = UIAlertAction(title: "Change Settings", style: .default) { (alert: UIAlertAction!) -> Void in
                
                UIApplication.shared.open(URL.init(string: UIApplication.openSettingsURLString)!,
                                          options:  [:],
                                          completionHandler: { (complete) in
                                            completion(false)
                })
            }
            
            let cancelAction = UIAlertAction(title: "Cancel", style: .default) { (alert: UIAlertAction!) -> Void in
                completion(false)
            }
            
            alert.addAction(okAction)
            alert.addAction(cancelAction)
            viewController.present(alert, animated: true, completion:nil)
            
            completion(false)
            
        @unknown default:
            break;
        }
    }
}

