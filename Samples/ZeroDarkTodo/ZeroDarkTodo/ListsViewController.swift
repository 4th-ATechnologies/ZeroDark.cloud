/// ZeroDark.cloud
///
/// Homepage      : https://www.zerodark.cloud
/// GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
/// Documentation : https://zerodarkcloud.readthedocs.io/en/latest
/// API Reference : https://apis.zerodark.cloud
///
/// Sample App: ZeroDarkTodo

import UIKit
import YapDatabase
import ZeroDarkCloud


protocol ListTableCellDelegate: class {
	func listTableCellRemoteUserClicked(listID: String)
}

class ListTableCell : UITableViewCell
{
	@IBOutlet public var lblTitle : UILabel!
	@IBOutlet public var lblDetail : UILabel!
	@IBOutlet public var btnRemoteUsers : KGHitTestingButton!
    
	@IBOutlet public var lblCount : BadgedBarLabel!
	@IBOutlet public var cnstlblCountWidth : NSLayoutConstraint!
	
	var listID: String!
	weak var delegate : ListTableCellDelegate!

	@IBAction func btnRemoteUserClicked(_ sender: Any) {
		delegate?.listTableCellRemoteUserClicked(listID: self.listID)
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

class ListsViewController: UIViewController, UITableViewDelegate, UITableViewDataSource,
SettingsViewControllerDelegate, ListTableCellDelegate {
	
	var uiDatabaseConnection: YapDatabaseConnection!
	var mappings: YapDatabaseViewMappings?
	var btnTitle: IconTitleButton?
    
	var localUserID: String = ""
    
	@IBOutlet public var listsTable : UITableView!
	
	// for simulating push
	@IBOutlet public var vwSimulate : UIView!
	@IBOutlet public var cnstVwSimulateHeight : NSLayoutConstraint!
	
    
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Class Functions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	class func allListsWithLocalUserID(userID: String, transaction:YapDatabaseReadTransaction ) -> [String] {
        
		var result:[String] = []
        
		if let viewTransaction = transaction.ext(Ext_View_Lists) as? YapDatabaseViewTransaction {
			
			viewTransaction.iterateKeys(inGroup: userID) {(collection, key, index, stop) in
				result.append(key)
			}
		}
		
		return result
	}
    
	class func initWithLocalUserID(_ localUserID: String) -> ListsViewController {
		
		let storyboard = UIStoryboard(name: "Main", bundle: nil)
		let vc = storyboard.instantiateViewController(withIdentifier: "ListsViewController") as? ListsViewController
		
		vc?.localUserID = localUserID
		
		return vc!
	}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: View Lifecycle
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    
	override func viewDidLoad() {
		super.viewDidLoad()
		
		let settingsImage = UIImage(named: "threebars")!.withRenderingMode(.alwaysTemplate)
		
		let settingButton = UIButton()
		settingButton.setImage(settingsImage, for: .normal)
		settingButton.addTarget( self,
		                 action: #selector(self.didHitSettings(_:)),
		                    for: .touchUpInside)
		
		let settingButtonItem = UIBarButtonItem(customView: settingButton)
		let width1 = settingButtonItem.customView?.widthAnchor.constraint(equalToConstant: 22)
		width1?.isActive = true
		let height1 = settingButtonItem.customView?.heightAnchor.constraint(equalToConstant: 22)
		height1?.isActive = true
		
		self.navigationItem.leftBarButtonItems = [
			settingButtonItem
		]
		
		let sortImage = UIImage(named: "hamburger")!.withRenderingMode(.alwaysTemplate)
		
		let sortButton = UIButton()
		sortButton.setImage(sortImage, for: .normal)
		sortButton.addTarget( self,
		              action: #selector(self.didSetEditing(_:)),
		                 for: .touchUpInside)
		
		let sortButtonItem = UIBarButtonItem(customView: sortButton)
		let width = sortButtonItem.customView?.widthAnchor.constraint(equalToConstant: 22)
		width?.isActive = true
		let height = sortButtonItem.customView?.heightAnchor.constraint(equalToConstant: 22)
		height?.isActive = true
        
		self.navigationItem.rightBarButtonItems = [
            
			UIBarButtonItem(barButtonSystemItem: .add,
			                             target: self,
			                             action: #selector(self.didTapAddItemButton(_:))),
			sortButtonItem
		]
		
	#if DEBUG
		
		self.vwSimulate.isHidden = false
		self.cnstVwSimulateHeight.constant = 44
		
		let zdc = ZDCManager.zdc()
		if let simVC = zdc.uiTools?.simulatePushNotificationViewController() {
			
			simVC.view.frame = self.vwSimulate.bounds;
			simVC.willMove(toParent: self)
			self.vwSimulate.addSubview(simVC.view)
			self.addChild(simVC)
			simVC.didMove(toParent: self)
		}
		
	#else
		
		self.vwSimulate.isHidden = true
		self.cnstVwSimulateHeight.constant = 0
	
	#endif
	}
    
	override func viewWillAppear(_ animated: Bool) {
        
		self.setupDatabaseConnection()
        
		var localUser: ZDCLocalUser?
		uiDatabaseConnection.read {(transaction) in
			
			localUser = transaction.localUser(id: self.localUserID)
		}
		
		if let localUser = localUser {
			self.setNavigationTitle(user: localUser)
		}
		listsTable.reloadData()
	}
	
	override func viewDidDisappear(_ animated: Bool) {
	
		NotificationCenter.default.removeObserver(self)
	}
    
	private func setNavigationTitle(user: ZDCLocalUser) {
		
		if (btnTitle == nil) {
			
			btnTitle = IconTitleButton.create()
			btnTitle?.setTitleColor(self.view.tintColor, for: .normal)
			btnTitle?.addTarget(self,
			                    action: #selector(self.didHitTitle(_:)),
			                       for: .touchUpInside)
		}
		
		btnTitle?.setTitle(user.displayName, for: .normal)
		btnTitle?.isEnabled = true
		self.navigationItem.titleView = btnTitle
		
		let zdc = ZDCManager.zdc()
		
		let size = CGSize(width: 30, height: 30)
		let defaultImage = { () -> UIImage in
			return zdc.imageManager!.defaultUserAvatar().scaled(to: size, scalingMode: .aspectFill)
		}
		let processing = {(image: UIImage) in
			return image.scaled(to: size, scalingMode: .aspectFill)
		}
		let preFetch = {[weak self](image: UIImage?, willFetch: Bool) -> Void in
			self?.btnTitle?.setImage(image ?? defaultImage(), for: .normal)
		}
		let postFetch = {[weak self](image: UIImage?, error: Error?) -> Void in
			self?.btnTitle?.setImage(image ?? defaultImage(), for: .normal)
		}
		
		zdc.imageManager!.fetchUserAvatar( user,
		                             with: nil,
		                     processingID: "30*30",
		                  processingBlock: processing,
		                         preFetch: preFetch,
		                        postFetch: postFetch)
	}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Database
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	private func setupDatabaseConnection() {
		
		let zdc = ZDCManager.zdc()
		
		uiDatabaseConnection = zdc.databaseManager?.uiDatabaseConnection
		self.initializeMappings()
        
		NotificationCenter.default.addObserver( self,
		                              selector: #selector(self.databaseConnectionDidUpdate(notification:)),
		                                  name: .UIDatabaseConnectionDidUpdate,
		                                object: nil)
	}
    
	@objc func databaseConnectionDidUpdate(notification: Notification) {
        
		let notifications = notification.userInfo?[kNotificationsKey] as! [Notification]
		
		guard let mappings = self.mappings else {
			
			initializeMappings()
			listsTable.reloadData()
			return;
		}
		
		guard let ext = uiDatabaseConnection.extension(Ext_View_Lists) as? YapDatabaseViewConnection else {
			return
		}
		
		let (sectionChanges, rowChanges) = ext.getChanges(forNotifications: notifications, withMappings: mappings)
		
		if (sectionChanges.count == 0) && (rowChanges.count == 0) {
			// No changes for the tableView
			return
		}
		
		listsTable.beginUpdates()
		for change in sectionChanges {
			switch change.type {
				case .delete:
					listsTable.deleteSections(IndexSet(integer: Int(change.index)), with: .automatic)
				
				case .insert:
					listsTable.insertSections(IndexSet(integer: Int(change.index)), with: .automatic)
				
				default:
					break
			}
		}
		for change in rowChanges {
			switch change.type {
				
				case .delete:
					listsTable.deleteRows(at: [change.indexPath!], with: .automatic)
				
				case .insert:
					listsTable.insertRows(at: [change.newIndexPath!], with: .automatic)
				
				case .move:
					listsTable.moveRow(at: change.indexPath!, to: change.newIndexPath!)
					
					// We would use this is the user manually moved the row
				//	listsTable.reloadRows(at: [changes.indexPath!], with: .automatic)
				//	listsTable.reloadRows(at: [changes.newIndexPath!], with: .automatic)
				
				case .update:
					listsTable.reloadRows(at: [change.indexPath!], with: .automatic)
				
				default:
					break
         }
		}
		listsTable.endUpdates()
	}
    
	private func initializeMappings() {
        
		uiDatabaseConnection.read { (transaction) in
			
			if transaction.extension(Ext_View_Lists) is YapDatabaseViewTransaction {
				
				self.mappings = YapDatabaseViewMappings.init(groups: [self.localUserID], view: Ext_View_Lists)
				self.mappings!.update(with: transaction)
			}
			else {
				// Waiting for view to finish registering
			}
		}
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	func listAtIndexPath(_ indexPath: IndexPath) -> List? {
		
		var list: List? = nil
		if let mappings = self.mappings {
		
			uiDatabaseConnection.read({ (transaction) in
	
				let viewTransaction = transaction.ext(Ext_View_Lists) as! YapDatabaseViewTransaction
				list = viewTransaction.object(at: indexPath, with: mappings) as? List
			})
		}
		return list
	}
	
	func nodeForList(_ list: List) -> ZDCNode? {
		
		let zdc = ZDCManager.zdc()
		
		var listNode: ZDCNode? = nil
		uiDatabaseConnection.read({ (transaction) in
			
			if let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: self.localUserID) {
				
				listNode = cloudTransaction.linkedNode(forKey: list.uuid, inCollection: kCollection_Lists)
			}
		})
		
		return listNode
	}
    
	func numberOfPendingTasks(listID: String) -> Int {
		
		var count: Int = 0
		uiDatabaseConnection.read {  (transaction) in
			
			if let vt = transaction.ext(Ext_View_Pending_Tasks) as? YapDatabaseViewTransaction {
				count = Int(vt.numberOfItems(inGroup: listID))
			}
		}
		
		return count
	}
	
	func numberOfTotalTasks(listID: String) -> Int {
		
		var count: Int = 0
		uiDatabaseConnection.read { (transaction) in
			
			if let vt = transaction.ext(Ext_View_Tasks) as? YapDatabaseViewTransaction {
				count = Int(vt.numberOfItems(inGroup: listID))
			}
		}
		
		return count
	}

	private func createNewList(title: String) {
		
		let zdc = ZDCManager.zdc()
		let db = zdc.databaseManager!
		let localUserID = self.localUserID
		
		// Here's what we want to do:
		//
		// 1. Create a List
		// 2. Create a node, linked to our list
		//
		// Please see the README.md file for a discussion on how this works.
		// You can find it here:
		//
		// - Samples/ZeroDarkTodo/README.md
		//
		// ^^^^^^^^^^ Read this file ^^^^^^^^^^
		
		var listID: String? = nil
		
		// Perform a database transaction.
		//
		// Note that we're doing this using an asynchronous ReadWrite transaction.
		// Apple strongly encourages us to never perform synchronous disk IO on the main thread.
		// So we're just following Apple's guidelines here for a better UI experience.
		//
		// (YapDatabase encourages the same thing, for the same reason.)
		
		db.rwDatabaseConnection.asyncReadWrite({ (transaction) in
			
			guard let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: localUserID) else {
				return // from transaction
			}
			
			
			// In order to create the node, we're going to have to specify where the node goes within the treesystem.
			// We already know where we want it to go.
			//
			// As described in README.md:
			//
			//       (home)
			//       /    \
			// (listA)    (listB)
			//
			// So we need to convert this into a treesystemPath.
			// This is similar to a filepath: ~/foo/bar/whatever
			//
			// For more information on treesystem paths, check out the docs here:
			// https://zerodarkcloud.readthedocs.io/en/latest/advanced/tree/
			
			var path = ZDCTreesystemPath(pathComponents: [ title ])
			
			// Every node in the treesystem has a name.
			// And all the children of node X need to have different names.
			// I.e. we cannot have 2 child nodes of X both named "foobar".
			//
			// In a similar manner, for this sample project,
			// we want to ensure there aren't 2 List's with the same name.
			//
			// So we're going to use treesystem to handle the unique-name stuff for us.
			
			path = cloudTransaction.conflictFreePath(path)
			
			// Now we can create our list.
			
			let list = List(localUserID: localUserID, title: path.nodeName)
			listID = list.uuid
			
			// Store the List object in the database.
			//
			// YapDatabase is a collection/key/value store.
			// So we store all List objects in the same collection: kCollection_Lists
			// And every list has a uuid, which we use as the key in the database.
			//
			// Wondering how the object gets serialized / deserialized ?
			// The List object supports the Swift Codable protocol.
			
			transaction.setObject(list, forKey: list.uuid, inCollection: kCollection_Lists)
			
			do {
				
				// Create the corresponding node.
				
				let node = try cloudTransaction.createNode(withPath: path)
				
				// And then link our object to the node.
				// This is optional, but it makes life easier for this particular app.
				
				try cloudTransaction.linkNodeID(node.uuid, toKey: list.uuid, inCollection: kCollection_Lists)
				
			} catch {
				
				// If this happens, it's because we passed an invalid parameter.
				// Here are some examples:
				//
				// - Our treesystem path was invalid.
				//   As in, we passed "/foo/bar", but there's no existing "/foo" node.
				//
				// - There's already a node at that path,
				//   and it's linked to a different List object.
				
				print("Error creating node for list: \(error)")
			}
            
		}, completionBlock: {
			
			if let listID = listID {
				
				self.pushItemsViewForListID(listID: listID)
			}
		})
	}
    
	private func renameList (listID: String, newTitle: String) {
		
		let zdc = ZDCManager.zdc()
		let rwDatabaseConnection = zdc.databaseManager!.rwDatabaseConnection
		
		let localUserID = self.localUserID
		
		rwDatabaseConnection.asyncReadWrite({ (transaction) in
			
			guard var list = transaction.object(forKey: listID, inCollection: kCollection_Lists) as? List else {
				return
			}
			
			list = list.copy() as! List
			list.title = newTitle
			
			transaction.setObject(list, forKey: list.uuid, inCollection: kCollection_Lists)
			
			if let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: localUserID),
				var listNode = cloudTransaction.linkedNode(forKey: list.uuid, inCollection: kCollection_Lists)
			{
				listNode = listNode.copy() as! ZDCNode
				listNode.name = newTitle
				
				do {
					try cloudTransaction.modifyNode(listNode)
				} catch {
					print("Error renaming node for list: \(error)")
				}
			}
		})
	}
	
	private func isOwnedByMe(listID: String) -> Bool {
		
		let zdc = ZDCManager.zdc()
		let localUserID = self.localUserID
		
		var result = true
		uiDatabaseConnection.read {(transaction) in
			
			if let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: localUserID),
				let listNode = cloudTransaction.linkedNode(forKey: listID, inCollection: kCollection_Lists)
			{
				// If our listNode is a pointer,
				// then the owner is somebody else.
				//
				// In other words, the node in our treesystem is pointing to
				// a list in another user's treesystem.
				
				if listNode.isPointer {
					result = false
				}
			}
		}
		
		return result
	}
    
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Actions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	@objc func didHitTitle(_ sender: Any) {
		
		let zdc = ZDCManager.zdc()
		zdc.uiTools?.pushSettings(forLocalUserID: localUserID, with: self.navigationController!)
	}
    
	@objc func didHitSettings(_ sender: Any) {
		
		AppDelegate.sharedInstance().toggleSettingsView()
	}
	
	@objc func didSetEditing(_ sender: Any) {
		
		let willEdit = !self.isEditing
		self.setEditing(willEdit, animated: true)
		listsTable.isEditing  = willEdit
	}
    
    @objc func didTapAddItemButton(_ sender: Any)
    {
        
        self.setEditing(false, animated: true)
        listsTable.isEditing  = false
        
        // Create an alert
        let alert = UIAlertController(title: NSLocalizedString("New to-do List", comment: ""),
                                      message: NSLocalizedString("New to-do List", comment: ""),
                                      cancelButtonTitle: NSLocalizedString("Cancel", comment: ""),
                                      okButtonTitle:  NSLocalizedString("OK", comment: ""),
                                      validate: .nonEmpty,
                                      textFieldConfiguration: { textField in
                                        textField.placeholder =   NSLocalizedString("List Name", comment: "")
        }) { result in
            
            switch result {
            case let .ok(String:newName):
                
                self.createNewList(title: newName)
                //
                break
                
            case .cancel:
                break
            }
        }
        
        // Present the alert to the user
        self.present(alert, animated: true, completion: nil)
    }
    
	private func moreAlertForListID(listID: String) {
		
		var list: List? = nil
        
		uiDatabaseConnection.read { (transaction) in
		
			list = transaction.object(forKey: listID, inCollection: kCollection_Lists) as? List
		}
        
		// Create an alert
		let alertController = UIAlertController(
			title          : "",
			message        : nil,
			preferredStyle : .actionSheet
		)
        
        let titleAttributes = [NSAttributedString.Key.font: UIFont.preferredFont(forTextStyle:.headline),
                               NSAttributedString.Key.foregroundColor: UIColor.black]
        
        let titleString = NSAttributedString(string: (list?.title)!, attributes: titleAttributes)
        alertController.setValue(titleString, forKey: "attributedTitle")
        
        let renameAction = UIAlertAction(title: NSLocalizedString("Rename", comment: ""), style: .default) { (action:UIAlertAction) in
            self.didTapRenameForListID(listID: listID)
        }
        
        let shareAction = UIAlertAction(title: NSLocalizedString("Sharing…", comment: ""), style: .default) { (action:UIAlertAction) in
            self.didTapAddUserForListID(listID: listID)
        }
        
        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel…", comment: ""), style: .cancel) { (action:UIAlertAction) in
            
        }
        
        alertController.addAction(renameAction)
        alertController.addAction(shareAction)
        alertController.addAction(cancelAction)
        
        self.present(alertController, animated: true, completion: nil)
    }
    
	private func didTapRenameForListID(listID: String) {
		
		var list: List! = nil
        
      uiDatabaseConnection.read { (transaction) in
			
			list  = transaction.object(forKey: listID, inCollection: kCollection_Lists) as? List
		}
        
        let alert = UIAlertController(title:  NSLocalizedString("Rename List Entry", comment: ""),
                                      message: nil,
                                      cancelButtonTitle: NSLocalizedString("Cancel", comment: ""),
                                      okButtonTitle:  NSLocalizedString("Rename", comment: ""),
                                      validate: .nonEmpty,
                                      textFieldConfiguration: { textField in
                                        textField.placeholder =  NSLocalizedString("List Name", comment: "")
                                        textField.text = list.title
        }) { result in
            
            switch result {
            case let .ok(String:newName):
                self.renameList(listID: listID, newTitle: newName);
                break
                
            case .cancel:
                break
            }
        }
        
        // Present the alert to the user
        self.present(alert, animated: true, completion: nil)
    }
    
	private func didTapAddUserForListID(listID: String) {
		
		let zdc = ZDCManager.zdc()
		
		var listNode: ZDCNode? = nil
		uiDatabaseConnection.read { (transaction) in
			
			if let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: self.localUserID) {
				
				listNode = cloudTransaction.linkedNode(forKey: listID, inCollection: kCollection_Lists)
			}
		}
		
		let localUserID = AppDelegate.sharedInstance().currentLocalUserID!
		let remoteUserIDs = listNode?.shareList.allUserIDs() ?? []
		
		zdc.uiTools!.pushSharedUsersView(forLocalUserID: localUserID,
		                                          remoteUserIDs: Set(remoteUserIDs),
		                                                  title: "Shared To",
		                                   navigationController: self.navigationController!)
		{(newUsers:Set<String>?, removedUsers:Set<String>?) in
			
			ZDCManager.sharedInstance.modifyListSharing( listID,
			                                localUserID: self.localUserID,
			                                   newUsers: newUsers ?? Set<String>(),
			                               removedUsers: removedUsers ?? Set<String>())
		}
	}
    
	func listTableCellRemoteUserClicked(listID: String) {
		
		let zdc = ZDCManager.zdc()
		
		var listNode: ZDCNode? = nil
		uiDatabaseConnection.read { (transaction) in
			
			if let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: self.localUserID) {
				
				listNode = cloudTransaction.linkedNode(forKey: listID, inCollection: kCollection_Lists)
			}
		}
		
		let localUserID = AppDelegate.sharedInstance().currentLocalUserID!
		let remoteUserIDs = listNode?.shareList.allUserIDs() ?? []
	
		zdc.uiTools?.pushSharedUsersView(forLocalUserID: localUserID,
		                                  remoteUserIDs: Set(remoteUserIDs),
		                                          title: "Shared To",
		                           navigationController: self.navigationController!)
		{ (newUsers: Set<String>?, removedUsers: Set<String>?) in
			
			ZDCManager.sharedInstance.modifyListSharing( listID,
			                                localUserID: self.localUserID,
			                                   newUsers: newUsers ?? Set<String>(),
			                               removedUsers: removedUsers ?? Set<String>())
		}
	}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: UITableView
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
		var result = 0;
		
		if let mappings = self.mappings {
			result = Int(mappings.numberOfItems(inGroup: localUserID))
		}
		
		return result
	}
    
	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		
		let zdc = ZDCManager.zdc()
		let cell = tableView.dequeueReusableCell(withIdentifier: "ListTableCell", for: indexPath) as! ListTableCell
		
		if let list = self.listAtIndexPath(indexPath) {
            
			cell.listID = list.uuid
			cell.lblTitle?.text = list.title
			cell.delegate = self;
			
			let pendingCount = self.numberOfPendingTasks(listID: list.uuid)
			let totalCount = self.numberOfTotalTasks(listID: list.uuid)
			
			let format = NSLocalizedString("number_of_tasks", comment: "")
			let message = String.localizedStringWithFormat(format, pendingCount, totalCount)
			cell.lblDetail?.text = message
		
			let sharedToCount = nodeForList(list)?.shareList.countOfUserIDs(excluding: self.localUserID) ?? 0
			if sharedToCount == 0 {
				
				cell.lblCount.isHidden = true;
				cell.btnRemoteUsers.isHidden = true
			}
			else {
				
				cell.btnRemoteUsers.isHidden = false
				cell.btnRemoteUsers.setImage(zdc.imageManager!.defaultMultiUserAvatar(), for: .normal)
				
				// a lot of work to make the badge look pretty
				cell.lblCount.isHidden = false;
				cell.lblCount.font = UIFont.systemFont(ofSize: 14)
				cell.lblCount.textAlignment = .center
				cell.lblCount.clipsToBounds = true
				cell.lblCount.layer.cornerRadius = cell.lblCount.frame.size.height/2;
				cell.lblCount.edgeInsets = UIEdgeInsets.init(top: 0, left: 4, bottom: 0, right: 3)
				cell.lblCount.text =  String(sharedToCount)
				
				var rect: CGRect = cell.lblCount.frame //get frame of label
				rect.size = (cell.lblCount.text?.size(withAttributes: [NSAttributedString.Key.font: UIFont(name: cell.lblCount.font.fontName , size: cell.lblCount.font.pointSize)!]))! //Calculate as per label font
				
				let width = rect.width + 8
				cell.cnstlblCountWidth.constant  = max(18,width);
			}
		}
		
		cell.accessoryType = .disclosureIndicator
		return cell
	}
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
		if let list = self.listAtIndexPath(indexPath) {
			self.pushItemsViewForListID(listID: list.uuid)
		}
	}
    
	private func pushItemsViewForListID(listID: String) {
		let itemVC = TasksViewController.initWithListID(listID)
		self.navigationController?.pushViewController(itemVC, animated: true)
	}
    
	func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
		// Return false if you do not want the specified item to be editable.
		return true
	}
	
	
	func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
		return false
	}
    
	func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
		  if tableView.isEditing {
				return .delete
		  }
		  return .none
	 }
	
	func tableView(_ tableView: UITableView,
	               trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
	) -> UISwipeActionsConfiguration?
	{
		guard let list = self.listAtIndexPath(indexPath) else {
			return nil
		}
		
		let zdc = ZDCManager.zdc()
		let rwDatabaseConnection = zdc.databaseManager!.rwDatabaseConnection
		
		//
		// Delete
		//
		
		let delete_handler: UIContextualAction.Handler = {(action, view, completionHandler) in
			
			rwDatabaseConnection.asyncReadWrite({ (transaction) in
				
				transaction.removeObject(forKey: list.uuid, inCollection: kCollection_Lists)
				
			}, completionBlock: {
				
				// UI update is handled by databaseConnectionDidUpdate
				completionHandler(true)
			})
		}
		
		let delete_action = UIContextualAction(style: .destructive,
		                                       title: "Delete",
		                                     handler: delete_handler)
		
		//
		// More
		//
		
		let more_handler: UIContextualAction.Handler = {(action, view, completionHandler) in
			
			self.moreAlertForListID(listID: list.uuid)
			completionHandler(true)
		}
		
		let more_action = UIContextualAction(style: .normal,
		                                     title: "More…",
		                                   handler: more_handler)
		
		//
		// Remove
		//
		
		let remove_handler: UIContextualAction.Handler = {(action, view, completionHandler) in
			
			rwDatabaseConnection.asyncReadWrite({ (transaction) in
				
				transaction.removeObject(forKey: list.uuid, inCollection: kCollection_Lists)
				
			}, completionBlock: {
				
				// UI update is handled by databaseConnectionDidUpdate
				completionHandler(true)
			})
		}
		
		let remove_action = UIContextualAction(style: .normal,
		                                       title: "Remove",
		                                     handler: remove_handler)
		remove_action.backgroundColor = UIColor.orange
		
		//
		// Configuration
		//
		
		var actions: Array<UIContextualAction> = []
		
		if self.isOwnedByMe(listID: list.uuid) {
			actions.append(contentsOf: [delete_action, more_action])
		}
		else {
 			actions.append(remove_action)
		}
		
		let configuration = UISwipeActionsConfiguration(actions:actions)
		return configuration
	}
}
