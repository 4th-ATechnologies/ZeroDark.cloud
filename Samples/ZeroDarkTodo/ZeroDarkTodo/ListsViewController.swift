/// ZeroDark.cloud
///
/// Homepage      : https://www.zerodark.cloud
/// GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
/// Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
/// API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
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
	
	var databaseConnection: YapDatabaseConnection!
	var mappings: YapDatabaseViewMappings!
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
        
		if let vt = transaction.ext(Ext_View_Lists) as? YapDatabaseViewTransaction {
			
			vt.enumerateKeys(inGroup: userID) { (collection, key, index, stop) in
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
        
        let sortButton = UIButton()
        sortButton.setImage(UIImage(named: "hamburger")!
            .withRenderingMode(UIImage.RenderingMode.alwaysTemplate),
                            for: .normal)
        
        sortButton.addTarget(self,
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
            sortButtonItem	]
		
		#if DEBUG
		self.vwSimulate.isHidden = false
		self.cnstVwSimulateHeight.constant = 44
		
		if let simVC = ZDCManager.uiTools().simulatePushNotificationViewController() {
			
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
        
        var localUser: ZDCLocalUser!
        databaseConnection .read { (transaction) in
            localUser = transaction.object(forKey: self.localUserID, inCollection: kZDCCollection_Users) as? ZDCLocalUser
        }
        
        self.setNavigationTitle(user: localUser)
        listsTable.reloadData()
		

		
    }
    
    override func viewDidDisappear(_ animated: Bool) {
		
        NotificationCenter.default.removeObserver(self)
     }
    
	private func setNavigationTitle(user: ZDCLocalUser) {
		
		if (btnTitle == nil) {
			
			btnTitle = IconTitleButton.init(type:.custom)
			btnTitle?.setTitleColor(self.view.tintColor, for: .normal)
			btnTitle?.addTarget(self,
			                    action: #selector(self.didHitTitle(_:)),
			                    for: .touchUpInside)
		}
		
		btnTitle?.setTitle(user.displayName, for: .normal)
		btnTitle?.isEnabled = true
		self.navigationItem.titleView = btnTitle
		
		let size = CGSize(width: 30, height: 30)
		let defaultImage = {
			return ZDCManager.imageManager().defaultUserAvatar().scaled(to: size, scalingMode: .aspectFit)
		}
		let processing = {(image: UIImage) in
			return image.scaled(to: size, scalingMode: .aspectFit)
		}
		let preFetch = {[weak self](image: UIImage?, willFetch: Bool) -> Void in
			self?.btnTitle?.setImage(image ?? defaultImage(), for: .normal)
		}
		let postFetch = {[weak self](image: UIImage?, error: Error?) -> Void in
			self?.btnTitle?.setImage(image ?? defaultImage(), for: .normal)
		}
		
		ZDCManager.imageManager().fetchUserAvatar(user,
		                                          withProcessingID: "30*30",
		                                          processingBlock: processing,
		                                          preFetch: preFetch,
		                                          postFetch: postFetch)
	}
	

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Database
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
    private func setupDatabaseConnection()
    {
        databaseConnection = ZDCManager.uiDatabaseConnection()
        
        self.initializeMappings()
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.databaseConnectionDidUpdate(notification:)),
                                               name:.UIDatabaseConnectionDidUpdateNotification ,
                                               object: nil)
        
    }
    
    @objc func databaseConnectionDidUpdate(notification: Notification) {
        
        let notifications = notification.userInfo?[kNotificationsKey] as! [Notification]
        
        if (mappings == nil)
        {
            initializeMappings()
            listsTable.reloadData()
            return;
        }
        
        let ext:YapDatabaseViewConnection =  databaseConnection.extension(Ext_View_Lists) as! YapDatabaseViewConnection
        
        var rowChanges = NSArray()
        var sectionChanges = NSArray()
        
        ext.getSectionChanges(&sectionChanges, rowChanges: &rowChanges, for: notifications, with: mappings)
        
        if(sectionChanges.count == 0 && rowChanges.count == 0)
        {		// No changes for the tableView.
            return
        }
        
        listsTable .beginUpdates()
        if let changes = rowChanges as? [YapDatabaseViewRowChange] {
            
            for theseChanges:YapDatabaseViewRowChange in changes {
                switch theseChanges.type {
                    
                case .delete:
                    listsTable.deleteRows(at: [theseChanges.indexPath!], with: .automatic)
                    break
                    
                case .insert:
                    listsTable.insertRows(at: [theseChanges.newIndexPath!], with: .automatic)
                    break;
                    
                case .move:
                    //  if we performed the move with tableview edit, then they already moved..
                    // dont move them again, just reload at best
                    //	 listsTable.moveRow(at: theseChanges.indexPath!, to: theseChanges.newIndexPath!)
                    listsTable.reloadRows(at: [theseChanges.indexPath!], with: .automatic)
                    listsTable.reloadRows(at: [theseChanges.newIndexPath!], with: .automatic)
                    break
                    
                case .update:
                    listsTable.reloadRows(at: [theseChanges.indexPath!], with: .automatic)
                    break
                    
                default:
                    break
                }
            }
        }
        
        listsTable .endUpdates()
        
    }
    
    
	private func initializeMappings() {
        
		databaseConnection.read { (transaction) in
			
			let vt = transaction.extension(Ext_View_Lists) as? YapDatabaseManualViewTransaction
			if vt != nil {
				
				self.mappings = YapDatabaseViewMappings.init(groups: [self.localUserID], view: Ext_View_Lists)
			}
			else {
				
				// Waiting for view to finish registering
			}
            
			if self.mappings != nil {
				
				self.mappings.update(with: transaction)
			}
		}
	}
    
	func listAtIndexPath(_ indexPath: IndexPath) -> List? {
		
		var list: List? = nil
		databaseConnection.read({ (transaction) in
			
			let viewTransaction = transaction.ext(Ext_View_Lists) as! YapDatabaseManualViewTransaction
			list = viewTransaction.object(at: indexPath, with: self.mappings) as? List
		})
		
		return list
	}
	
	func nodeForList(_ list: List) -> ZDCNode? {
		
		let zdc = ZDCManager.zdc()
		
		var node: ZDCNode? = nil
		databaseConnection.read({ (transaction) in
			
			if let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: self.localUserID) {
				
				node = cloudTransaction.linkedNode(forKey: list.uuid, inCollection: kZ2DCollection_List)
			}
		})
		
		return node
	}
    
    func numberOfPendingTasksForListID (listID: String) -> Int
    {
        var count: Int = 0
        
        databaseConnection.read {  (transaction) in
            if  let vt = transaction.ext(Ext_View_Pending_Tasks) as? YapDatabaseViewTransaction
            {
                count = Int(vt.numberOfItems(inGroup: listID))
            }
        }
        return count
    }
	
	
	func numberOfTotalTasksForListID (listID: String) -> Int
	{
		var count: Int = 0
		
		databaseConnection.read {  (transaction) in
			if  let vt = transaction.ext(Ext_View_Tasks) as? YapDatabaseViewTransaction
			{
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
		
		let list = List(localUserID: localUserID, title: title)
		
		// Next we perform a database transaction.
		//
		// Note that we're doing this using an asynchronous ReadWrite transaction.
		// Apple strongly encourages us to never perform synchronous disk IO on the main thread.
		// So we're just following Apple's guidelines here for a better UI experience.
		//
		// (YapDatabase encourages the same thing, for the same reason.)
		
		db.rwDatabaseConnection.asyncReadWrite({ (transaction) in
			
			// Store the List object in the database.
			//
			// YapDatabase is a collection/key/value store.
			// So we store all List objects in the same collection: kZ2DCollection_List
			// And every list has a uuid, which we use as the key in the database.
			//
			// Wondering how the object gets serialized / deserialized ?
			// The List object supports the Swift Codable protocol.
			
			transaction.setObject(list, forKey: list.uuid, inCollection: kZ2DCollection_List)
			
			// Where does this List object go within the context of the UI.
			// For example, imagine the situation in which there are multiple lists:
			//
			// - Groceries
			// - Weekend Chores
			// - Stuff to get @ hardware store
			//
			// We're going to display these in a TableView to the user.
			// How do we order the items ?
			// Do we automatically sort them somehow ?
			// Or do we allow the user to sort them manually ?
			//
			// For our UI we've decided to let the user sort them manually.
			// This means we also want to store the order within the database.
			// And to accomplish this, we're using an extension that does most of the work for us.
			//
			// So we just need to add the {collection,key} tuple to YapDatabaseManualView.
			
			if let vt = transaction.ext(Ext_View_Lists) as? YapDatabaseManualViewTransaction {
				
				vt.addKey(list.uuid, inCollection:kZ2DCollection_List, toGroup: self.localUserID)
			}
			
			// The ZeroDarkCloud framework supports multiple localUser's.
			// In fact, this is part of the sample app.
			// It allows you to login to multiple users, and switch back and forth between them in the UI.
			//
			// So let's get a reference to the cloud of the correct localUser.
			
			if let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: self.localUserID) {
				
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
				// Basically, every node has a name.
				// And all the children of node X need to have different names.
				// I.e. we cannot have 2 lists both named "foobar".
				//
				// In our case, we actually don't care what the name of the node is.
				// It really doesn't matter to us, so we're just going to use a UUID.
				//
				// For more information on treesystem paths, check out the docs here:
				// https://zerodarkcloud.readthedocs.io/en/latest/advanced/tree/
				
				let treesystemPath = ZDCTreesystemPath(pathComponents: [ UUID().uuidString ])
				
				do {
					
					// Create the corresponding node.
					
					let node = try cloudTransaction.createNode(withPath: treesystemPath)
					
					// And then link our object to the node.
					// This is optional, but it makes life easier for this particular app.
					
					try cloudTransaction.linkNodeID(node.uuid, toKey: list.uuid, inCollection: kZ2DCollection_List)
					
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
			}
            
		}, completionBlock: {
			
			self.pushItemsViewForListID(listID: list.uuid)
		})
	}
    
    private func renameList (listID: String, newTitle: String)
    {
		let zdc = ZDCManager.zdc()

        ZDCManager.rwDatabaseConnection().asyncReadWrite({ (transaction) in
            
            let object  = transaction.object(forKey: listID, inCollection: kZ2DCollection_List)
            if var list = object as? List {
                
                list = list.copy() as! List
                list.title = newTitle
                
                transaction.setObject(list ,
                                      forKey: list.uuid,
                                      inCollection: kZ2DCollection_List)
					
					if let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: self.localUserID),
						let listNode = cloudTransaction.linkedNode(forKey: list.uuid, inCollection: kZ2DCollection_List)
					{
						cloudTransaction.queueDataUpload(forNodeID: listNode.uuid, withChangeset: nil)
					}

            }
        }, completionBlock: {
            // refrehes in databaseConnectionDidUpdate
        })
        
    }
	
	
	//TODO: check is this is shared to me or I am the owner
	
	private func isOwnedByMe (listID: String) -> Bool
	{
		return true;
	}
    
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Actions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    
    //	override func setEditing(_ editing: Bool, animated: Bool) {
    //		super.setEditing(editing, animated: animated)
    //		listsTable.isEditing  = editing
    //	}
    
 
    @objc func didHitTitle(_ sender: Any)
    {
		ZDCManager.uiTools().pushSettings(forLocalUserID: localUserID,
													 with: self.navigationController! )
	}
    
    @objc func didHitSettings(_ sender: Any)
    {
        AppDelegate.sharedInstance().toggleSettingsView()
    }
    
    @objc func didSetEditing(_ sender: Any)
    {
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
    
    private func moreAlertForListID(listID: String!)
    {
        var list: List? = nil
        
        databaseConnection .read { (transaction) in
            list  = transaction.object(forKey: listID, inCollection: kZ2DCollection_List) as? List
        }
        
        // Create an alert
        let alertController = UIAlertController(
            title: "",
            message: nil,
            preferredStyle: .actionSheet)
        
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
    
    private func didTapRenameForListID(listID: String!)
    {
        var list: List! = nil
        
        databaseConnection .read { (transaction) in
            list  = transaction.object(forKey: listID, inCollection: kZ2DCollection_List) as? List
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
		
		var node: ZDCNode? = nil
		databaseConnection.read { (transaction) in
			
			if let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: self.localUserID) {
				
				node = cloudTransaction.linkedNode(forKey: listID, inCollection: kZ2DCollection_List)
			}
		}
		
		let localUserID = AppDelegate.sharedInstance().currentLocalUserID!
		let remoteUserIDs = node?.shareList.allUserIDs() ?? []
		
		ZDCManager.uiTools().pushSharedUsersView(forLocalUserID: localUserID,
															  remoteUserIDs: Set(remoteUserIDs),
															  title: "Shared To",
															  navigationController: self.navigationController!)
		{ (newUsers:Set<String>?, removedUsers:Set<String>?) in
			
			ZDCManager.sharedInstance.modifyListPermissions(listID,
			                                                localUserID  : self.localUserID,
			                                                newUsers     : newUsers ?? Set<String>(),
			                                                removedUsers : removedUsers ?? Set<String>())
		}
	}
    
	func listTableCellRemoteUserClicked(listID: String) {
		
		let zdc = ZDCManager.zdc()
		
		var node: ZDCNode? = nil
		databaseConnection.read { (transaction) in
			
			if let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: self.localUserID) {
				
				node = cloudTransaction.linkedNode(forKey: listID, inCollection: kZ2DCollection_List)
			}
		}
		
		let localUserID = AppDelegate.sharedInstance().currentLocalUserID!
		let remoteUserIDs = node?.shareList.allUserIDs() ?? []
	
		ZDCManager.uiTools().pushSharedUsersView(forLocalUserID: localUserID,
															  remoteUserIDs: Set(remoteUserIDs),
															  title: "Shared To",
															  navigationController: self.navigationController!)
		{ (newUsers: Set<String>?, removedUsers: Set<String>?) in
			
			ZDCManager.sharedInstance.modifyListPermissions(listID,
			                                                localUserID  : self.localUserID,
			                                                newUsers     : newUsers ?? Set<String>(),
			                                                removedUsers : removedUsers ?? Set<String>())
		}
	}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: UITableView
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        var result = 0;
        
        if(mappings != nil)
        {
            result = Int(self.mappings.numberOfItems(inGroup: localUserID))
        }
        
        return result
    }
    
	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "ListTableCell", for: indexPath) as! ListTableCell
		
		if let list: List = self.listAtIndexPath(indexPath) {
            
			cell.listID = list.uuid
			cell.lblTitle?.text = list.title
			cell.delegate = self;
			
			let pendingCount = self.numberOfPendingTasksForListID(listID: list.uuid)
			let totalCount = self.numberOfTotalTasksForListID(listID: list.uuid)
	 
			
			let format = NSLocalizedString("number_of_tasks", comment: "")
			let message = String.localizedStringWithFormat(format, pendingCount, totalCount)
			cell.lblDetail?.text = message
		
			let sharedToCount = nodeForList(list)?.shareList.countOfUserIDs(excluding: self.localUserID) ?? 0
			if(sharedToCount == 0)
			{
				cell.lblCount.isHidden = true;
				cell.btnRemoteUsers.isHidden = true
			}
			else
			{
				cell.btnRemoteUsers.isHidden = false
				cell.btnRemoteUsers .setImage(ZDCManager.imageManager().defaultMultiUserAvatar(), for: .normal)
				
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
        
        let list: List?  = self.listAtIndexPath(indexPath)
        if(list != nil)
        {
            self.pushItemsViewForListID(listID: list!.uuid)
        }
    }
    
    private func pushItemsViewForListID(listID: String)
    {
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
    
    func tableView(_ tableView: UITableView, moveRowAt fromIndexPath: IndexPath, to: IndexPath) {
        
        let list: List?  = self.listAtIndexPath(fromIndexPath)
        if(list != nil)
        {
            
            ZDCManager.rwDatabaseConnection().asyncReadWrite({ (transaction) in
                
                let vt = transaction.ext(Ext_View_Lists) as! YapDatabaseManualViewTransaction
                
                vt.removeItem(at: UInt(fromIndexPath.row),
                              inGroup: self.localUserID)
                
                vt.insertKey((list?.uuid)!,
                             inCollection: kZ2DCollection_List,
                             at: UInt(to.row),
                             inGroup: self.localUserID)
                
            }, completionBlock: {
                
            })
        }
    }
    
    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the item to be re-orderable.
        return true
    }
    
    
	func tableView(_ tableView: UITableView,
	               trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
	) -> UISwipeActionsConfiguration?
	{
		let list: List! = self.listAtIndexPath(indexPath)
		
		let deleteAction =
			UIContextualAction(style: .destructive,
			                   title: "Delete",
			                   handler: {(action, view, completionHandler) in
				
				ZDCManager.rwDatabaseConnection().asyncReadWrite({(transaction) in
					
					transaction.removeObject(forKey: list.uuid, inCollection: kZ2DCollection_List)
					
				}, completionBlock: {
					
					// UI update is handled by databaseConnectionDidUpdate
					completionHandler(true)
				})
			})
		
		let moreAction =
			UIContextualAction(style: .normal,
			                   title: "More…",
			                   handler: {(action, view, completionHandler) in
										
				self.moreAlertForListID(listID: list.uuid)
				completionHandler(true)
			})
		
		let removeAction =
			UIContextualAction(style: .normal,
			                   title: "Remove",
			                   handler: {(action, view, completionHandler) in
										
				ZDCManager.rwDatabaseConnection().asyncReadWrite({(transaction) in
					
					// FIXME: add code to remove me from shared list
					transaction.removeObject(forKey: list.uuid, inCollection: kZ2DCollection_List)
					
				}, completionBlock: {
					
					// UI update is handled by databaseConnectionDidUpdate
					completionHandler(true)
				})
			})
		removeAction.backgroundColor = UIColor.orange
		
		var actions:Array<UIContextualAction> = Array()
		
		if (self.isOwnedByMe(listID: list.uuid))
		{
			actions.append(contentsOf: [deleteAction, moreAction])
		}
		else
		{
 			actions.append( removeAction)
		}
		
		
		let configuration = UISwipeActionsConfiguration(actions:actions)
		return configuration
	}
	
}

