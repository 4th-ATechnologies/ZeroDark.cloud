/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
 *
 * Sample App: ZeroDarkTodo
**/

import UIKit
import YapDatabase
import ZeroDarkCloud


protocol TaskTableCellDelegate: class {
	func taskTableCellCheckClicked(taskID: String?, checked: Bool )
}

class TaskTableCell : UITableViewCell
{
	@IBOutlet public var hitView : UIView!
	@IBOutlet public var checkMark : SSCheckMark!
	@IBOutlet public var lblTitle : UILabel!
	@IBOutlet public var lblDetail : UILabel!

	@IBOutlet public var cnslblRightOffset : NSLayoutConstraint!
	@IBOutlet public var imgThumb : UIImageView!

	var taskID: String!
	weak var delegate : TaskTableCellDelegate!

	override func awakeFromNib() {
		super.awakeFromNib()
		let tap = UITapGestureRecognizer(target: self, action: #selector(checkClicked))
		hitView.addGestureRecognizer(tap)
	}

	@objc func checkClicked(recognizer: UITapGestureRecognizer) {

		checkMark.checked = !checkMark.checked
		
		delegate?.taskTableCellCheckClicked( taskID: self.taskID,
											checked: self.checkMark.checked)
	}
}



class TasksViewController: UIViewController, UITableViewDelegate, UITableViewDataSource,
							TaskTableCellDelegate {

	@IBOutlet public var tasksTable : UITableView!

 	var listID: String!
	var databaseConnection :YapDatabaseConnection!
	var mappings: YapDatabaseViewMappings!
	var shareBadge: BadgedBarButtonItem?
    
	private let dateFormatter: DateFormatter = {
		let dateFormatter = DateFormatter()
		dateFormatter.dateFormat = "MMM d, h:mm a"
		return dateFormatter
	}()

	class func initWithListID(_ listID: String) -> TasksViewController {
		let storyboard = UIStoryboard(name: "Main", bundle: nil)
		let vc = storyboard.instantiateViewController(withIdentifier: "TasksViewController") as? TasksViewController

		vc?.listID = listID

 		return vc!
	}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: View Lifecycle
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	override func viewDidLoad() {
		super.viewDidLoad()

		let badgeSize = CGSize(width: 22, height: 22)
		let badgeImage = ZDCManager.imageManager().defaultMultiUserAvatar().scaled(to: badgeSize, scalingMode: .aspectFit)
		
		shareBadge = BadgedBarButtonItem(image: badgeImage, mode: .top) { [weak self] in
			
			self?.shareBadgeClicked()
		}
		shareBadge?.badgeColor = self.view.tintColor
		
		let rightBarButton = UIBarButtonItem(
			barButtonSystemItem: .add,
			target: self,
			action: #selector(self.didTapAddItemButton(_:))
		)
		self.navigationItem.rightBarButtonItems = [rightBarButton, shareBadge!]
		
		tasksTable.rowHeight = UITableView.automaticDimension
		tasksTable.estimatedRowHeight = 62
   }
	
	override func viewWillAppear(_ animated: Bool) {

		self.setupDatabaseConnection()
		tasksTable.reloadData()
		
		var list: List? = nil
		databaseConnection .read { (transaction) in
			list = transaction.object(forKey: self.listID, inCollection: kZ2DCollection_List) as? List
		}
		
		self.navigationItem.title = list?.title ?? "List"
		self.updateShareBadge()
	}

	override func viewDidDisappear(_ animated: Bool) {

		NotificationCenter.default.removeObserver(self)
	}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Database
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	private func setupDatabaseConnection() {
		
		// The UIDatabaseConnection is part of the ZeroDarkCloud framework.
		//
		// It's designed to be a shared YapDatabaseConnection that can be used by all the UI classes.
		// That is, if you're on the main thread, you should use the UIDatabaseConnection.
		//
		databaseConnection = ZDCManager.uiDatabaseConnection()
		self.initializeMappings()

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(self.databaseConnectionDidUpdate(notification:)),
			name:.UIDatabaseConnectionDidUpdateNotification ,
			object: nil
		)
	}
	
	private func initializeMappings() {
		
		// What are mappings ?
		//
		// YapDatabase has extensive documentation here:
		// https://github.com/yapstudios/YapDatabase/wiki/Views#mappings
		//
		// Here's the short version:
		//
		// YapDatabase stores an UNORDERED list of objects within a collection/key/value store.
		// But we need to drive a UITableView here, so we need an ORDERED list of Tasks.
		//
		// The solution for this is problem is simple:
		// - Create a persistent YapDatabaseView that sorts the items you need
		// - Create a "mappings" that maps from YapDatabaseView => UITableView data source
		//
		// If there's a perfet correlation between the YapDatabaseView and your UITableView,
		// then the mappings may seem redundant. But I guarantee you'll need them one day.
		//
		// Here's an example:
		// Imagine you're got your UITableView/UICollectionView all setup and working.
		// And then you start getting feedback from users that they want it sorted in reverse.
		// So half of your users want it sorted from old->new, and the other half want new->old.
		// You know you need to add a sort option to the UI, but how to handle the database ?
		// Does this mean you need to resort the YapDatabaseView when the user changes the setting ?
		// Nope, you don't ! Because mappings can invert it for you automatically,
		// without requiring any changes to the underlying YapDatabaseView.
		//
		// In other words, mappings are a powerful glue between a YapDatabaseView,
		// and our UITableView/UICollectionView data source.
		
		databaseConnection.read { (transaction) in
			
			let vt = transaction.extension(Ext_View_Tasks) as? YapDatabaseViewTransaction
			if vt != nil {
				
				self.mappings = YapDatabaseViewMappings.init(groups: [self.listID], view: Ext_View_Tasks)
			}
			else {
				// Waiting for view to finish registering
			}
			
			if self.mappings != nil {
				self.mappings.update(with: transaction)
			}
		}
	}

	/// This method is invoked due to a posted notification: UIDatabaseConnectionDidUpdateNotification
	///
	/// We registered for this notification in setupDatabaseConnection().
	/// The UIDatabaseConnection is part of the ZeroDarkCloud framework.
	///
	/// It's designed to be a shared YapDatabaseConnection that can be used by all the UI classes.
	/// That is, if you're on the main thread, you should use the UIDatabaseConnection.
	///
	@objc func databaseConnectionDidUpdate(notification: Notification) {

		let notifications = notification.userInfo?[kNotificationsKey] as! [Notification]

		if mappings == nil {
			
			initializeMappings()
			tasksTable.reloadData()
 			return;
		}

		guard
			let ext = databaseConnection.extension(Ext_View_Tasks) as? YapDatabaseAutoViewConnection
		else {
			return
		}
		
		// YapDatabaseView tells us exactly what changes occurred.
		//
		// And it gives us this information in a way that allows us to
		// easily animate the changes in our UITableView/UICollectionView.
		
		var rowChanges = NSArray()
		var sectionChanges = NSArray()
		ext.getSectionChanges(&sectionChanges, rowChanges: &rowChanges, for: notifications, with: mappings)

		if (sectionChanges.count == 0) && (rowChanges.count == 0) {
			
			// No changes that affect our tableView
			return
		}

		tasksTable.beginUpdates()
		if let changes = rowChanges as? [YapDatabaseViewRowChange] {

			for change in changes {
				switch change.type {

					case .delete:
						tasksTable.deleteRows(at: [change.indexPath!], with: .automatic)
					
					case .insert:
						tasksTable.insertRows(at: [change.newIndexPath!], with: .automatic)
					
					case .move:
						tasksTable.deleteRows(at: [change.indexPath!], with: .automatic)
						tasksTable.insertRows(at: [change.newIndexPath!], with: .automatic)
					
					case .update:
						tasksTable.reloadRows(at: [change.indexPath!], with: .automatic)
					
					default:
						break
				}
			}
		}

		tasksTable.endUpdates()
	}

	func taskAtIndexPath(indexPath: IndexPath) -> Task? {
		
		var task: Task? = nil
		databaseConnection.read { (transaction) in
			
			if let viewTransaction = transaction.ext(Ext_View_Tasks) as? YapDatabaseViewTransaction {
				
				task = viewTransaction.object(at: indexPath, with: self.mappings) as? Task
			}
		}

		return task
	}
	
	func imageNodeForTask(task: Task) -> ZDCNode? {
		
		let zdc = ZDCManager.zdc()
		let localUserID = AppDelegate.sharedInstance().currentLocalUserID!
		
		// How do we find the node associated with the task's image ?
		//
		// As discussed in the README.md documentation, our treesystem looks like this:
		//
		//          (home)
		//          /    \
		//     (listA)    (listB)
		//      /  \         |
		// (task1)(task2)  (task3)
		//                   |
		//                  (img)
		//
		// Our application only allows for a single image per task.
		// So the name of the image node is always "img".
		//
		// In other words, the treesystem path to the image is always:
		//
		// home:{listNode.name}/{taskNode.name}/img
		//
		// The ZDCNodeManager has a function that will grab this for us given the taskNode.
		
		var imageNode: ZDCNode? = nil
		databaseConnection.read { (transaction) in
			
			if let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: localUserID),
				let taskNode = cloudTransaction.linkedNode(forKey: task.uuid, inCollection: kZ2DCollection_Task)
			{
				imageNode = zdc.nodeManager.findNode(withName: "img", parentID: taskNode.uuid, transaction: transaction)
			}
		}
		
		return imageNode
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Actions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	@objc func didTapAddItemButton(_ sender: Any)
	{
		// Create an alert
		let alert = UIAlertController(title: "New Task",
									  message: "Insert the title of the new Task",
									  cancelButtonTitle: "Cancel",
									  okButtonTitle: "OK",
									  validate: .nonEmpty,
									  textFieldConfiguration: { textField in
										textField.placeholder =  "Task name"
		}) { result in

			switch result {
			case let .ok(String:newName):

				self.addNewTask(title: newName)
				//
				break

			case .cancel:
				break
			}
		}

		// Present the alert to the user
		self.present(alert, animated: true, completion: nil)
	}

	private func addNewTask(title: String) {
		
		let zdc = ZDCManager.zdc()
		let localUserID = AppDelegate.sharedInstance().currentLocalUserID!
		let listID = self.listID!
		
		// Here's what we want to do:
		//
		// 1. Create a Task
		// 2. Create a node, linked to our task
		//
		// Please see the README.md file for a discussion on how this works.
		// You can find it here:
		//
		// - Samples/ZeroDarkTodo/README.md
		//
		// ^^^^^^^^^^ Read this file ^^^^^^^^^^
		
		let task = Task(listID: listID, title: title)
		
		// Next we perform a database transaction.
		//
		// Note that we're doing this using an asynchronous ReadWrite transaction.
		// Apple strongly encourages us to never perform synchronous disk IO on the main thread.
		// So we're just following Apple's guidelines here for a better UI experience.
		//
		// (YapDatabase encourages the same thing, for the same reason.)
		
		ZDCManager.rwDatabaseConnection().asyncReadWrite({ (transaction) in

			// Store the Task object in the database.
			//
			// YapDatabase is a collection/key/value store.
			// So we store all List objects in the same collection: kZ2DCollection_Task
			// And every task has a uuid, which we use as the key in the database.
			//
			// Wondering how the object gets serialized / deserialized ?
			// The Task object supports the Swift Codable protocol.
			
			transaction.setObject(task, forKey: task.uuid, inCollection: kZ2DCollection_Task)
			
			// The ZeroDarkCloud framework supports multiple localUser's.
			// In fact, this is part of the sample app.
			// It allows you to login to multiple users, and switch back and forth between them in the UI.
			//
			// So let's get a reference to the cloud of the correct localUser.
			
			if let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: localUserID) {
			
				// In order to create the node, we're going to have to specify where the node goes within the treesystem.
				// We already know where we want it to go.
				//
				// As described in README.md:
				//
				//          (home)
				//          /    \
				//     (listA)    (listB)
				//      /  \
				// (task1)(task2)
				//
				// So we need to convert this into a treesystemPath.
				// This is similar to a filepath: ~/foo/bar/whatever
				//
				// Basically, every node has a name.
				// And all the children of node X need to have different names.
				// I.e. we cannot have 2 tasks both named "foobar".
				//
				// In our case, we actually don't care what the name of the node is.
				// It really doesn't matter to us, so we're just going to use a UUID.
				//
				// For more information on treesystem paths, check out the docs here:
				// https://zerodarkcloud.readthedocs.io/en/latest/advanced/tree/
				
				if let parentNode = cloudTransaction.linkedNode(forKey: listID, inCollection: kZ2DCollection_List),
				   let listPath = zdc.nodeManager.path(for: parentNode, transaction: transaction) {
					
					let taskPath = listPath.appendingComponent(UUID().uuidString)
					
					do {
						
						// Create the corresponding node.
						
						let node = try cloudTransaction.createNode(withPath: taskPath)
						
						// Link our task to the node.
						// This is optional, but it makes life easier for this particular app.
						
						try cloudTransaction.linkNodeID(node.uuid, toKey: task.uuid, inCollection: kZ2DCollection_Task)
						
					} catch {
						
						// If this happens, it's because we passed an invalid parameter.
						// Here are some examples:
						//
						// - Our treesystem path was invalid.
						//   As in, we passed "/foo/bar", but there's no existing "/foo" node.
						//
						// - There's already a node at that path,
						//   and it's linked to a different Task object.
						
						print("Error creating node for task: \(error)")
					}
				}
			}

		}, completionBlock: {
			
			self.pushItemsViewForTaskID(taskID: task.uuid)
		})
	}

	private func pushItemsViewForTaskID(taskID: String) {
		
		let itemVC = TaskDetailsViewController.initWithTaskID(taskID)
		self.navigationController?.pushViewController(itemVC, animated: true)
	}

	private func invertTaskCompletion(taskID: String) {
		
		let zdc = ZDCManager.zdc()
		let localUserID = AppDelegate.sharedInstance().currentLocalUserID!

		ZDCManager.rwDatabaseConnection().asyncReadWrite({ (transaction) in

			let object  = transaction.object(forKey: taskID, inCollection: kZ2DCollection_Task)
			if var task = object as? Task {

				task = task.copy() as! Task
				task.completed = !task.completed
				task.localLastModified = Date()

				transaction.setObject(task ,
									  forKey: task.uuid,
									  inCollection: kZ2DCollection_Task)
				
				if let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: localUserID),
					let taskNode = cloudTransaction.linkedNode(forKey: task.uuid, inCollection: kZ2DCollection_Task)
				{
					cloudTransaction.queueDataUpload(forNodeID: taskNode.uuid, withChangeset: nil)
				}

			}
		}, completionBlock: {
			// refrehes in databaseConnectionDidUpdate
		})

	}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Tableview
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
 	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {

		let result = self.mappings.numberOfItems(inGroup: self.listID)
		return Int(result)
	}

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		
		let cell = tableView.dequeueReusableCell(withIdentifier: "TaskCell", for: indexPath) as! TaskTableCell

		if let task: Task = self.taskAtIndexPath(indexPath: indexPath) {

			var titleColor:UIColor = UIColor.black

			switch task.priority  {
			case .low:
				titleColor = UIColor.gray

			case .normal:
				titleColor = UIColor.black

			case .high:
				titleColor = UIColor.red
			}

			let titleAttributes = [NSAttributedString.Key.font: UIFont.preferredFont(forTextStyle:.body),
								   NSAttributedString.Key.foregroundColor: titleColor]

			let attributedTitle = NSMutableAttributedString(string: (task.title), attributes: titleAttributes)

			if task.completed {
				
				attributedTitle.addAttributes([
					NSAttributedString.Key.strikethroughStyle:NSUnderlineStyle.thick.rawValue,
					NSAttributedString.Key.strikethroughColor:titleColor
				], range: NSMakeRange(0, attributedTitle.length))
			}
			
			cell.lblTitle?.attributedText = attributedTitle;
			cell.lblDetail?.text = dateFormatter.string(from:(task.creationDate))
			cell.checkMark.checked = task.completed

			let taskID = task.uuid
			cell.taskID = taskID
			
			if let imageNode = self.imageNodeForTask(task: task) {
				
				cell.imgThumb.image = nil
				cell.imgThumb.isHidden = false
				cell.cnslblRightOffset.constant = cell.imgThumb.frame.width + 8
				
				let preFetch = {(image: UIImage?, willFetch: Bool) in
					
					// This method is invoked BEFORE the fetchNodeThumbnail() function returns.
					
					cell.imgThumb.image = image
					
					if willFetch {
						// Image is being fetched from the network.
						// You may want to display a spinner or something.
					}
				}
				let postFetch = {(image: UIImage?, error: Error?) in
					
					// This method is invoked LATER, after the download or disk-read has completed.
					
					if cell.taskID != taskID {
						// The cell has been recycled. Ignore.
						return
					}
					
					if let image = image {
						cell.imgThumb.image = image
					
					}
					if let _ = error {
						// Image download failed.
						// You may want to display an error image or something.
					}
				}
				
				ZDCManager.imageManager().fetchNodeThumbnail(imageNode, preFetch: preFetch, postFetch: postFetch)
				
			} else {
				
				cell.imgThumb.isHidden = true
				cell.cnslblRightOffset.constant = 4
			}
			
			cell.delegate = self

			cell.accessoryType = .disclosureIndicator
		//	cell.accessoryType = UITableViewCell.AccessoryType.disclosureIndicator
		}

		return cell
	}

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {

		if let task = self.taskAtIndexPath(indexPath: indexPath) {
			
			self.pushItemsViewForTaskID(taskID: task.uuid)
		}
	}

	// TaskTableCellDelegate
	func taskTableCellCheckClicked(taskID: String?, checked: Bool) {
		
		self.invertTaskCompletion(taskID: taskID!);
	}

	func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
		
		return true
	}

	func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
		
		return false
	}

	func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
		
		return false
	}

	func tableView(_ tableView: UITableView,
				   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
		->   UISwipeActionsConfiguration? {



			let actions = [

				UIContextualAction(style: .destructive, title: "Delete",
								   handler: { (action, view, completionHandler) in

									if let task: Task = self.taskAtIndexPath(indexPath: indexPath)
									{
										ZDCManager.rwDatabaseConnection().asyncReadWrite({ (transaction) in

											transaction.removeObject(forKey: task.uuid,
																	 inCollection: kZ2DCollection_Task)

										}, completionBlock: {

											// UI update  is handled by  databaseConnectionDidUpdate
											completionHandler(true)
										})

									}
									else
									{
										completionHandler(false)
									}
				})

				/*  // Swift doesnt have a preprocessor?
				
				, UIContextualAction(style: .normal, title: "More…",
				handler: { (action, view, completionHandler) in

				if let task: Task = self.taskAtIndexPath(indexPath: indexPath)
				{
				}
				completionHandler(true)
				})
				*/
			]




			let configuration = UISwipeActionsConfiguration(actions: actions)
			return configuration
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Share badge
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	private func shareBadgeClicked() {
		
		let zdc = ZDCManager.zdc()
		let localUserID = AppDelegate.sharedInstance().currentLocalUserID!
		let listID = self.listID!
		
		var node: ZDCNode? = nil
		self.databaseConnection .read { (transaction) in
			
			if let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: localUserID) {
				
				node = cloudTransaction.linkedNode(forKey: listID, inCollection: kZ2DCollection_List)
			}
		}
		
		var remoteUserIDs = node?.shareList.allUserIDs() ?? []
		remoteUserIDs = remoteUserIDs.filter {$0 != localUserID}
		
		ZDCManager.uiTools().pushSharedUsersView(forLocalUserID: localUserID,
															  remoteUserIDs: Set(remoteUserIDs),
															  title:"Shared To",
															  navigationController: self.navigationController!)
		{ (newUsers: Set<String>?, removedUsers: Set<String>?) in
			
			ZDCManager.sharedInstance.modifyListPermissions(listID,
			                                                localUserID  : localUserID,
			                                                newUsers     : newUsers ?? Set<String>(),
			                                                removedUsers : removedUsers ?? Set<String>())
		}
	}
	
	private func updateShareBadge() {
		
		let zdc = ZDCManager.zdc()
		let localUserID = AppDelegate.sharedInstance().currentLocalUserID!
		
		var count: UInt = 0
		databaseConnection.read { (transaction) in
			
			var node: ZDCNode? = nil
			if let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: localUserID) {
				
				node = cloudTransaction.linkedNode(forKey: self.listID, inCollection: kZ2DCollection_List)
			}
			
			count = node?.shareList.countOfUserIDs(excluding: localUserID) ?? 0
		}
		
		if count > 0 {
			shareBadge?.badgeText = String(count)
		}
		else {
			shareBadge?.badgeText = ""
		}
	}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: RemoteUsersViewController_IOSDelegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	func remoteUserViewController(_ sender: Any,
	                              completedWithNewRecipients recipients: [String]?,
	                              userObjectID: String?)
	{
		// Todo
	}
}
