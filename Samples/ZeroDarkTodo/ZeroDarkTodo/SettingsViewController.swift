/// ZeroDark.cloud
///
/// Homepage      : https://www.zerodark.cloud
/// GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
/// Documentation : https://zerodarkcloud.readthedocs.io/en/latest
/// API Reference : https://apis.zerodark.cloud
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
                              UITableViewDelegate,
                              UITableViewDataSource,
                              SettingsTableHeaderViewDelegate
{
	enum Section: Int, CaseIterable {
		 case accounts
		 case options
	}
	
	enum Options: Int, CaseIterable {
		case activity
	}

	@IBOutlet public var tblButtons : UITableView!

	var databaseConnection :YapDatabaseConnection!

	weak var delegate : SettingsViewControllerDelegate!
	var sortedLocalUserInfo: [ZDCUserDisplay] = []
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

	override func viewWillAppear(_ animated: Bool) {
		self.navigationItem.title = NSLocalizedString("Settings", comment: "")

		self.setupDatabaseConnection()
		self.refreshView()
	}

	private func refreshView() {
		
		let zdc = ZDCManager.zdc()
		
		databaseConnection.read { (transaction) in
			
			let localUsers = zdc.localUserManager!.allLocalUsers(transaction)
			self.sortedLocalUserInfo = zdc.userManager!.sortedUnambiguousNames(for: localUsers)
		}
		
		self.tblButtons.reloadData()
	}

	/////////////////////////////////////////////
	// MARK: Database
	/////////////////////////////////////////////

	private func setupDatabaseConnection()
	{
		let zdc = ZDCManager.zdc()
		databaseConnection = zdc.databaseManager!.uiDatabaseConnection

		NotificationCenter.default.addObserver( self,
		                              selector: #selector(self.databaseConnectionDidUpdate(notification:)),
		                                  name: .UIDatabaseConnectionDidUpdate,
		                                object: nil)
	}

	@objc func databaseConnectionDidUpdate(notification: Notification) {

		if let notifications = notification.userInfo?[kNotificationsKey] as? [Notification],
 			let extLocalUsers = databaseConnection.ext(Ext_View_LocalUsers) as? YapDatabaseViewConnection
		{
 			let hasChanges = extLocalUsers.hasChanges(for: notifications)
		
			if hasChanges {
				
				self.refreshView()
			}
		}
	}

	/////////////////////////////////////////////
	// MARK: Tableview
	/////////////////////////////////////////////
	
	func numberOfSections(in tableView: UITableView) -> Int {

		return Section.allCases.count
	}

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {

		var result: Int = 0

		switch section
		{
			case Section.accounts.rawValue:
			
				if sortedLocalUserInfo.count > 0 {
					result = sortedLocalUserInfo.count
				}
				else {
 					result = 1
				}
			
			case Section.options.rawValue:
			
				result = Options.allCases.count
			
			default: break;
		}

		return result
	}

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

		let zdc = ZDCManager.zdc()
		
		var cell: UITableViewCell? = nil
		
		switch indexPath.section {
		case Section.accounts.rawValue:

			guard
				let accountCell = tableView.dequeueReusableCell(withIdentifier: "AccountsTableViewCell") as? AccountsTableViewCell
			else {
				break;
			}
			
			if sortedLocalUserInfo.count == 0 {
				
				accountCell.userName.text = NSLocalizedString("Add Account", comment: "Add Account")
				accountCell.userName.textColor = self.view.tintColor
				accountCell.userAvatar.image = nil
				accountCell.accessoryType = .none;
			}
			else {
				
				let localUserInfo: ZDCUserDisplay = sortedLocalUserInfo[indexPath.row]
				let localUserID = localUserInfo.userID
				
				var localUser: ZDCLocalUser? = nil
				databaseConnection .read { (transaction) in
					
					localUser = transaction.localUser(id: localUserID)
				}

				if let localUser = localUser {
					
					if localUserInfo.displayName.count > 0 {
						accountCell.userName.text = localUserInfo.displayName
					} else {
						accountCell.userName.text = "wtf"
					}
					
					accountCell.userID = localUserID
					accountCell.userName.textColor = UIColor.black
					
					accountCell.userAvatar.layer.cornerRadius = accountCell.userAvatar.frame.width / 2
					accountCell.userAvatar.layer.masksToBounds = true
					
					let defaultImage = {() -> UIImage in
						return zdc.imageManager!.defaultUserAvatar()
					}
					
					let preFetch = {(image: UIImage?, willFetch: Bool) in
						
						accountCell.userAvatar.image = image ?? defaultImage()
					}
					let postFetch = {(image: UIImage?, error: Error?) in
						
						accountCell.userAvatar.image = image ?? defaultImage()
					}
					
					zdc.imageManager!.fetchUserAvatar( localUser,
					                             with: nil,
					                         preFetch: preFetch,
					                        postFetch: postFetch)

					accountCell.userName.textColor = localUser.hasCompletedSetup ? UIColor.black : UIColor.lightGray ;

					if localUser.accountSuspended || localUser.accountNeedsA0Token || localUser.accountDeleted
					{
						accountCell.accessoryView = UIImageView.init(image: warningImage)
					}
					else
					{
						accountCell.accessoryView = nil
						
						let isSelected = (localUserID == AppDelegate.sharedInstance().currentLocalUserID)
						if isSelected {
							accountCell.accessoryType = .checkmark
						} else {
							accountCell.accessoryType = .disclosureIndicator
						}
					}
				}
			}
			
			cell = accountCell

		case Section.options.rawValue:

			cell = tableView.dequeueReusableCell(withIdentifier: "Settings-Options")
				??  UITableViewCell.init(style: .value1, reuseIdentifier: "Settings-Options" )

			var title = ""
			switch indexPath.row
			{
			case Options.activity.rawValue:
				title = "Show Activity Monitor"

			default:
				title = ""
			}

			cell?.textLabel?.text = title
			cell?.accessoryType = .none
			
		default: break
		}

		return cell!
	}

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {

		tableView.deselectRow(at: indexPath, animated: true)

		switch indexPath.section {
		case Section.accounts.rawValue:

			if sortedLocalUserInfo.count > 0 {

				let localUserInfo: ZDCUserDisplay = sortedLocalUserInfo[indexPath.row]
				let localUserID = localUserInfo.userID

				AppDelegate.sharedInstance().currentLocalUserID = localUserID
			}
			else {
				
				self.settingsTableHeaderAddTapped(tableview: tableView)
			}

		case Section.options.rawValue:
            
			switch indexPath.row {
			case Options.activity.rawValue:
				showActivityView()
                
			default: break
			}
			
		default: break
		}
	}

	func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
		return 30
	}
	
	func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
		return 0
	}

	func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
		
		let cell = tableView.dequeueReusableCell(withIdentifier: "SettingsTableHeaderView") as? SettingsTableHeaderView
		return cell
	}

	func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {

		guard let header = view as? SettingsTableHeaderView else {
			return
		}

		switch section {
		case Section.accounts.rawValue:
			
			header.headerLabel.text = NSLocalizedString("ACCOUNTS", comment:  "Accounts")
			header.btnAdd.isHidden = false;
			header.isUserInteractionEnabled = true;

		case Section.options.rawValue:

			header.headerLabel.text = NSLocalizedString("OPTIONS", comment:  "Options")
			header.btnAdd.isHidden = true;
			header.isUserInteractionEnabled = false;
			
		default: break
		}

		header.delegate = self
	}

	func tableView(_ tableView: UITableView,
	trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
	-> UISwipeActionsConfiguration? {

		var actions = Array<UIContextualAction>()

		if indexPath.section == Section.accounts.rawValue {
			
			if sortedLocalUserInfo.count > 0 {
				
				let localUserInfo: ZDCUserDisplay = sortedLocalUserInfo[indexPath.row]
				let localUserID = localUserInfo.userID
				
				let moreAction =
				  UIContextualAction(style: .normal,
				                     title: "More…",
				                   handler:
				{ (action, view, completionHandler) in
					
					completionHandler(true)
				})
				
				let deleteAction =
				  UIContextualAction(style: .normal,
				                     title: "Delete",
				                   handler:
				{(action, view, completionHandler) in
																	
					self.maybeDeleteUserID(localUserID: localUserID, completion: {(success) in
						
						completionHandler(success)
						if success {
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


	func maybeDeleteUserID(localUserID: String, completion: @escaping (Bool) -> ()) {
		
		var localUser: ZDCLocalUser? = nil
		databaseConnection.read { (transaction) in
			
			localUser = transaction.localUser(id: localUserID)
		}
		
		if let localUser = localUser {
			
			let titleFrmt = NSLocalizedString( "Delete user \"%@\" from this device?",
			                          comment: "Delete user prompt")
			
			let title = String(format: titleFrmt, localUser.displayName)
			
			let warningMessage = NSLocalizedString("""
				You have not backed up your access key!\n
				If you delete this user you might lose access to your data!
				We recommend you backup your access key before proceeding.
				""",
				comment: "Delete user warning");
				
			let message = (localUser.hasCompletedSetup && !localUser.hasBackedUpAccessCode) ? warningMessage : nil
				
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
					
					ZDCManager.zdc().uiTools!.pushSettings(forLocalUserID: localUserID, with: nav)
				}
				
				completion(false)
			}
			
			
			let cancelAction = UIAlertAction(title: "Cancel", style: .default) { (alert: UIAlertAction!) -> Void in
				
				completion(false)
			}
			
			alert.addAction(deleteAction)
			
			if(localUser.hasCompletedSetup && !localUser.hasBackedUpAccessCode){
				alert.addAction(backupAction)
			}
			
			alert.addAction(cancelAction)
			
			present(alert, animated: true, completion:nil)
			
		}
		
	}
	
	/////////////////////////////////////////////
	// MARK: Actions
	/////////////////////////////////////////////

	func settingsTableHeaderAddTapped(tableview: UITableView?) {

		RootContainerViewController.shared()?.showActivationView(canDismissWithoutNewAccount:true)
	}
    
	func showActivityView() {
		
		AppDelegate.sharedInstance().toggleSettingsView()
		
		if let revealController = AppDelegate.sharedInstance().revealController,
			let navController = revealController.frontViewController as? UINavigationController
		{
			ZDCManager.zdc().uiTools?.pushActivityView(forLocalUserID: nil, with: navController)
		}
	}
}
