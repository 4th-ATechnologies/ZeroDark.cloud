/// ZeroDark.cloud
///
/// Homepage      : https://www.zerodark.cloud
/// GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
/// Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
/// API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
///
/// Sample App: ZeroDarkTodo

import UIKit
import ZeroDarkCloud

class AccountsTableViewCell : UITableViewCell
{
	@IBOutlet public var userName : UILabel!
	@IBOutlet public var userAvatar : UIImageView!
	var userID : String?

}

protocol SettingsTableHeaderViewDelegate: class {
	func settingsTableHeaderAddTapped(tableview: UITableView?)
}

class SettingsTableHeaderView : UITableViewCell
{
	@IBOutlet public var headerLabel : UILabel!
	@IBOutlet public var btnAdd : UIButton!

	weak var delegate : SettingsTableHeaderViewDelegate!

	func tableview() -> UITableView? {

		var tableView = self.superview
		while(tableView != nil){

			if tableView is UITableView {
				return tableView as? UITableView
			}
			else {
				tableView = self.superview
			}
		}
		return nil;
	}

	@IBAction func btnAddClicked(_ sender: Any) {

		if let tableview = self.tableview() {
			delegate?.settingsTableHeaderAddTapped( tableview: tableview)
		}
	}


}

protocol SettingsViewControllerDelegate: class {
}


class SettingsViewController: UIViewController,
	UITableViewDelegate, UITableViewDataSource,
SettingsTableHeaderViewDelegate {


	let kSection_Accounts 	= 0
	let kSection_Options 	= 1
	let kSection_Last 		= 2

	let kOptions_Activity 	= 0
	let kOptions_Row_1 		= 1
	let kOptions_Row_Last 	= 2

	@IBOutlet public var tblButtons : UITableView!

	var databaseConnection :YapDatabaseConnection!

	weak var delegate : SettingsViewControllerDelegate!
	var localUsersInfo: [[String: Any]] = []
	var warningImage : UIImage!

	var preferedWidth: CGFloat
	{
		get {
			var  width : CGFloat
			switch (UIScreen.main.traitCollection.userInterfaceIdiom) {
			case .pad:
				width = 300
			case .phone:
				width = 260.0
			default:
				width = 260.0
			}

			return width
		}
	}

	class func `initWithDelegate`(delegate: SettingsViewControllerDelegate) -> SettingsViewController {
		let storyboard = UIStoryboard(name: "SettingsViewController", bundle: nil)
		let vc = storyboard.instantiateViewController(withIdentifier: "SettingsViewController") as? SettingsViewController

			vc?.warningImage = UIImage.init(named: "warning")
			vc?.delegate = delegate

		return vc!
	}

     override func viewDidLoad() {
        super.viewDidLoad()
	}

	override func viewWillAppear(_ animated: Bool) {
		self.navigationItem.title =  NSLocalizedString("Settings", comment: "")

		self.setupDatabaseConnection()
		self.refreshView()
	}

	private func refreshView() {
		
		var users: [[String: Any]] = []
		
		databaseConnection .read { (transaction) in
			
			ZDCManager.localUserManager().enumerateLocalUsers(with: transaction,
									using: { (localUser, stop) in
										users.append(["uuid": localUser.uuid,
													  "displayName": localUser.displayName ])
			})
		}
		
		localUsersInfo = users
		self.tblButtons.reloadData()
	}


	// MARK: - database


	private func setupDatabaseConnection()
	{
		databaseConnection = ZDCManager.uiDatabaseConnection()

		NotificationCenter.default.addObserver(self,
											   selector: #selector(self.databaseConnectionDidUpdate(notification:)),
											   name:.UIDatabaseConnectionDidUpdateNotification ,
											   object: nil)

	}

	@objc func databaseConnectionDidUpdate(notification: Notification) {

		let notifications = notification.userInfo?[kNotificationsKey] as! [Notification]
 		let extLocalUsers =  databaseConnection.ext(Ext_View_LocalUsers) as! YapDatabaseViewConnection
		let localUserChanges = extLocalUsers.hasChanges(for: notifications)

 		let hasChanges = localUserChanges

		if(hasChanges)
		{
			self.refreshView()
		}

	}


	// MARK: - Tableview

	func numberOfSections(in tableView: UITableView) -> Int {
	//	 let count = Sections.kSection_Last.rawValue - 1

		return 2
	}


	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {

		var result: Int = 0

		switch section {
			case kSection_Accounts:
			
			if(localUsersInfo.count > 0)
			{
				result =  localUsersInfo.count
			}
			else
			{
 				result = 1
			}
			
		case kSection_Options:
			result = kOptions_Row_Last

		default:
			result = 0
		}

		return result
	}


	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

		var cell: UITableViewCell? = nil

		switch indexPath.section {
		case kSection_Accounts:

			guard
				let accountCell = tableView.dequeueReusableCell(withIdentifier: "AccountsTableViewCell") as? AccountsTableViewCell
			else {
				break;
			}
			
			if localUsersInfo.count == 0 {
				
				accountCell.userName.text = NSLocalizedString("Add Account", comment: "Add Account")
				accountCell.userName.textColor = self.view.tintColor
				accountCell.userAvatar.image = nil
				accountCell.accessoryType = .none;
			}
			else {
				
				let info = localUsersInfo[indexPath.row]
				let uuid = info["uuid"] as? String
				
				var localUser: ZDCLocalUser? = nil
				databaseConnection .read { (transaction) in
					
					localUser = transaction.object(forKey: uuid!, inCollection: kZDCCollection_Users) as? ZDCLocalUser
				}

				if let localUser = localUser {
					
					accountCell.userName.text = info["displayName"] as? String
					accountCell.userID =  uuid
					accountCell.userName.textColor = UIColor.black
					
					accountCell.userAvatar.layer.cornerRadius = accountCell.userAvatar.frame.width / 2
					accountCell.userAvatar.layer.masksToBounds = true
					
					let defaultImage = {
						return ZDCManager.imageManager().defaultUserAvatar()
					}
					
					let preFetch = {(image: UIImage?, willFetch: Bool) in
						
						accountCell.userAvatar.image = image ?? defaultImage()
					}
					let postFetch = {(image: UIImage?, error: Error?) in
						
						accountCell.userAvatar.image = image ?? defaultImage()
					}
					
					ZDCManager.imageManager().fetchUserAvatar(localUser, preFetch: preFetch, postFetch: postFetch)

					accountCell.userName.textColor = localUser.hasCompletedSetup ? UIColor.black : UIColor.lightGray ;

					if localUser.accountSuspended || localUser.accountNeedsA0Token || localUser.accountDeleted
					{
						accountCell.accessoryView = UIImageView.init(image: warningImage)
					}
					else
					{
						accountCell.accessoryView = nil
						
						let isSelected = (uuid == AppDelegate.sharedInstance().currentLocalUserID)
						if(isSelected){
							accountCell.accessoryType = .checkmark;
						}else {
							accountCell.accessoryType = .disclosureIndicator;
						}
					}
				}
			}
			
			cell = accountCell

		//	case kSection_Options,
		default:

			cell = tableView.dequeueReusableCell(withIdentifier: "Settings-Options")
				??  UITableViewCell.init(style: .value1, reuseIdentifier: "Settings-Options" )

			var title = ""
			switch(indexPath.row)
			{
			case kOptions_Activity:
				title = "Show Activity"

			case kOptions_Row_1:
				title = "do thing 2"

			default:
				title = ""
			}

			cell?.textLabel?.text = title
			cell?.accessoryType = .none

		}

		return cell!
	}

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {

		tableView.deselectRow(at: indexPath, animated: true)

		if(indexPath.section == kSection_Accounts){

			if (localUsersInfo.count > 0) {

				let info = localUsersInfo[indexPath.row]
				let  uuid = info["uuid"] as? String

				AppDelegate.sharedInstance().currentLocalUserID = uuid

			}
			else
			{
				self.settingsTableHeaderAddTapped(tableview: tableView)
			}

		}
		else  if(indexPath.section == kSection_Options){
            
            switch(indexPath.row)
            {
            case kOptions_Activity:
                showActivityView()
                
            case kOptions_Row_1:
                test2()
                
            default:
               break
            }

		}
	}


	func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
		return 0
	}

	func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
		return 30
	}

	 func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
		
		let cell = tableView.dequeueReusableCell(withIdentifier: "SettingsTableHeaderView") as? SettingsTableHeaderView
		return cell
	}

	func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {

		if let header = view as? SettingsTableHeaderView{

			if(section == kSection_Accounts){
				header.headerLabel.text = NSLocalizedString("ACCOUNTS", comment:  "Accounts")
				header.btnAdd.isHidden = false;
				header.isUserInteractionEnabled = true;

			}else if(section == kSection_Options){

				header.headerLabel.text = NSLocalizedString("OPTIONS", comment:  "Options")
				header.btnAdd.isHidden = true;
				header.isUserInteractionEnabled = false;
			}

			header.delegate = self
		}
	}

	func tableView(_ tableView: UITableView,
	trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
	->   UISwipeActionsConfiguration? {

		var actions:Array<UIContextualAction> = Array()

		if(indexPath.section == kSection_Accounts){
			
			if (localUsersInfo.count > 0) {
				
				let userInfo = localUsersInfo[indexPath.row]
				let userID = userInfo["uuid"] as! String
				
				let moreAction = UIContextualAction(style: .normal, title: "More…",
																handler: { (action, view, completionHandler) in
																	completionHandler(true)
				})
				
				let deleteAction = UIContextualAction(style: .normal, title: "Delete",
																  handler: { (action, view, completionHandler) in
																	
																	self.maybeDeleteUserID(localUserID: userID,
																								  completion:
																		{ (success) in
																			completionHandler(success)
																			if(success) {
																				AppDelegate.sharedInstance().currentLocalUserID = nil
																			}
																	})
				})
				
				deleteAction.backgroundColor = UIColor.red
				actions.append(contentsOf: [deleteAction,moreAction])
			}
		}


		let configuration = UISwipeActionsConfiguration(actions:actions)

		configuration.performsFirstActionWithFullSwipe = false // This is the line which disables full swipe
		return configuration
	}


	func maybeDeleteUserID(localUserID:String!, completion: @escaping (Bool) -> ()) {
		
		var localUser: ZDCLocalUser? = nil
		ZDCManager.uiDatabaseConnection() .read { (transaction) in
			
			localUser = transaction.object(forKey: localUserID!,
													 inCollection: kZDCCollection_Users) as? ZDCLocalUser
		}
		
		if let localUser = localUser
		{
			let title =  String(format: NSLocalizedString("Delete user \"%@\" from this device?",
																		 comment: "Delete user \"%@\" from this device?"),
									  localUser.displayName)
			
			let warningMessage = NSLocalizedString("You have not backed up your Access Key!\n If you delete this user you might lose access to your data!\n We recommend you backup your Access Key before proceeding.",
																comment: "You have not backed up your Access Key! If you delete this user you might lose access to your data!\n We recommend you backup your Access Key before proceeding.");
			
			let message = localUser.hasBackedUpAccessCode ? nil: warningMessage
			
			let alert =
				UIAlertController(title: title,
										message: message,
										preferredStyle: .alert)
			
			
			let deleteAction = UIAlertAction(title: "Delete", style: .destructive) { (alert: UIAlertAction!) -> Void in
				
				AppDelegate.sharedInstance().deleteUserID(userID: localUserID,
																		completion: { (success) in
																			completion(success)
				})
			}
			
			let backupAction = UIAlertAction(title: "Backup Access Key", style: .default) { (alert: UIAlertAction!) -> Void in
				
				AppDelegate.sharedInstance().currentLocalUserID = localUserID
				
				if let rvc = AppDelegate.sharedInstance().revealController{
					
					let nav = rvc.frontViewController as! UINavigationController
					
					ZDCManager.uiTools().pushSettings(forLocalUserID: localUserID,
																 with: nav  )
				}
				
				completion(false)
			}
			
			
			let cancelAction = UIAlertAction(title: "Cancel", style: .default) { (alert: UIAlertAction!) -> Void in
				
				completion(false)
			}
			
			alert.addAction(deleteAction)
			
			if(!localUser.hasBackedUpAccessCode){
				alert.addAction(backupAction)
			}
			
			alert.addAction(cancelAction)
			
			present(alert, animated: true, completion:nil)
			
		}
		
	}
	
	
	// MARK: - Actions


	func settingsTableHeaderAddTapped(tableview: UITableView?) {

		RootContainerViewController.shared()?.showActivationView(canDismissWithoutNewAccount:true)

	}
    
    func showActivityView() {
		
		if let rvc = AppDelegate.sharedInstance().revealController{
			
			AppDelegate.sharedInstance().toggleSettingsView()

			let nav = rvc.frontViewController as! UINavigationController
			
			ZDCManager.uiTools().pushActivityView(forLocalUserID:nil,
														 with: nav  )

     }
	}
	
    func test2() {
        
    }

}
