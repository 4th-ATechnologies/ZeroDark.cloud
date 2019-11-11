/// ZeroDark.cloud
///
/// Homepage      : https://www.zerodark.cloud
/// GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
/// Documentation : https://zerodarkcloud.readthedocs.io/en/latest
/// API Reference : https://apis.zerodark.cloud
///
/// Sample App: ZeroDarkTodo

import Foundation

import CocoaLumberjack
import YapDatabase

let Ext_View_Lists         = "Lists"
let Ext_View_Tasks         = "Tasks"
let Ext_View_Pending_Tasks = "PendingTasks"
let Ext_Hooks              = "Hooks"

extension Notification.Name {
	static let UIDBConnectionWillUpdate = Notification.Name("UIDBConnectionWillUpdate")
	static let UIDBConnectionDidUpdate  = Notification.Name("UIDBConnectionDidUpdate")
}

/// We're using YapDatabase in this example.
/// You don't have to use it (but it's pretty awesome).
///
/// https://github.com/yapstudios/YapDatabase
///
class DBManager {
	
	public static var sharedInstance: DBManager = {
		let dbManager = DBManager()
		return dbManager
	}()
	
	private var _uiDatabaseConnection: YapDatabaseConnection?
	
	private init() {
	#if DEBUG
		dynamicLogLevel = .all
	#else
		dynamicLogLevel = .warning
	#endif
	}
	
	public func configureDatabase(_ db: YapDatabase) {
		
		db.registerCodableSerialization(List.self, forCollection: kCollection_Lists)
		db.registerCodableSerialization(Task.self, forCollection: kCollection_Tasks)
		db.registerCodableSerialization(Invitation.self, forCollection: kCollection_Invitations)
		
		registerExtension_ListsView(db)
		registerExtension_TasksView(db)
		registerExtension_PendingTasksView(db)
		registerExtension_Hooks(db)
		
		setupUIDatabaseConnection(db)
	}
	
	/// In the user interface, we need to display a tableView of all the Lists.
	///
	/// We're going to create a YapDatabaseView to sort them for us.
	///
	private func registerExtension_ListsView(_ database: YapDatabase) {
		
		// YapDatabaseAutoView is a YapDatabase extension.
		// It allows us to store a list of {collection,key} tuples.
		// Furthermore, the view creates this list automatically using a grouping & sorting block.
		//
		// YapDatabase has extensive documentation for views:
		// https://github.com/yapstudios/YapDatabase/wiki/Views
		//
		// Here's the cliff notes version:
		//
		// Imagine you're storing a large collection of Book's in the databse.
		// You'd like to create a "view" of this data wherein each book is first grouped
		// according to its genre. For example, "fiction", "mystery", "travel", etc.
		// Then, within each genre, you want to sort the books by title, in alphabetical order.
		//
		// So there are 2 tasks:
		// Task 1: GROUP the books by genre
		// Task 2: SORT the books within each genre
		//
		// And this is what we're doing here.
		//
		// The grouping block allows us to group each item into the database.
		// We simply return a string, and the view will place the item into a group that matches this string.
		// From our Books example above, this means we'd return a string like "fiction".
		// If you return nil from the grouping block, then the item isn't included in the view at all.
		//
		// And the sorting block does what you think it does.
		// It sorts 2 items just like any comparison block.
		// And YapDatabaseAutoView uses it to sort all the items in a group.
		// (Just like an Array would use a similar technique to sort the items in an Array.)
		
		// GROUPING CLOSURE:
		//
		// We're only going to have 1 group in our view.
		// So the group name will just be the empty string.
		//
		let grouping = YapDatabaseViewGrouping.withObjectBlock {
			(transaction, collection, key, obj) -> String? in
			
			if let list = obj as? List {
				return list.localUserID
			}
			return nil
		}
		
		// SORTING CLOSURE:
		//
		// Sort the List's by title.
		//
		let sorting = YapDatabaseViewSorting.withObjectBlock({
			(transaction, group, collection1, key1, obj1, collection2, key2, obj2) -> ComparisonResult in
			
			let list1 = obj1 as! List
			let list2 = obj2 as! List
			
			return list1.title.localizedCaseInsensitiveCompare(list2.title)
		})
		
		let version = "2019-18-13-B"; // <---------- change me if you modify grouping or sorting closure
		let locale = NSLocale()
		
		let versionTag = "\(version)-\(locale)"
		
		let options = YapDatabaseViewOptions()
		options.allowedCollections = YapWhitelistBlacklist(whitelist: Set([kCollection_Lists]))
		
		let view =
			YapDatabaseAutoView(grouping: grouping,
			                     sorting: sorting,
			                  versionTag: versionTag,
			                     options: options)
		
		let extName = Ext_View_Lists
		database.asyncRegister(view, withName: extName) {(ready) in
			
			if !ready {
				DDLogError("Error registering \(extName) !!!")
			}
		}
	}
	
	/// In the user interface, we need to display a tableView of all the tasks in a list.
	/// We need to sort these tasks somehow.
	/// We use a YapDatabaseView to accomplish this, as described below.
	///
	private func registerExtension_TasksView(_ database : YapDatabase) {
		
		// YapDatabaseAutoView is described above (in setupView_Lists function)
		//
		// YapDatabase has extensive documentation for views:
		// https://github.com/yapstudios/YapDatabase/wiki/Views
		
		// GROUPING CLOSURE:
		//
		// Group all the Task's into groups, based on their List.
		//
		let grouping = YapDatabaseViewGrouping.withObjectBlock({
			(transaction, collection, key, obj) -> String? in
			
			if let task = obj as? Task {
				return task.listID
			}
			return nil
		})
		
		// SORTING CLOSURE:
		//
		// Sort all the Task's in a given List.
		//
		// We want to sort the Tasks like so:
		// - If the Task is marked as completed, move it towards the bottom of the list.
		// - If the Task is NOT completed, move it towards the top of the list.
		// - Within each section, sort the Task's by creationDate.
		//
		// There are many different ways in which we could go about doing this.
		// I bet you can think of something better.
		//
		let sorting = YapDatabaseViewSorting.withObjectBlock({
			(transaction, group, collection1, key1, obj1, collection2, key2, obj2) -> ComparisonResult in
			
			let task1 = obj1 as! Task
			let task2 = obj2 as! Task
			
			if (task1.completed && !task2.completed)
			{
				return .orderedDescending
			}
			else if (!task1.completed && task2.completed)
			{
				return .orderedAscending
			}
			else
			{
				return task2.creationDate.compare(task1.creationDate)
			}
		})
		
		let versionTag =  "2019-02-04-x"; // <---------- change me if you modify grouping or sorting closure
		
		let options = YapDatabaseViewOptions()
		options.allowedCollections = YapWhitelistBlacklist(whitelist: Set([kCollection_Tasks]))

		let view =
			YapDatabaseAutoView(grouping: grouping,
			                     sorting: sorting,
			                  versionTag: versionTag,
			                     options: options)

		let extName = Ext_View_Tasks
		database.asyncRegister(view, withName: extName) {(ready) in
			
			if !ready {
				DDLogError("Error registering \(extName) !!!")
			}
		}
	}
	
	// In the user interface, we need a quick way to get the total count of all Task's that are not completed.
	// We need to do this on a per-list basis.
	// So we're going to create a View that will give us this info.
	//
	private func registerExtension_PendingTasksView(_ database: YapDatabase) {
		
		// YapDatabaseAutoView is described above (in setupView_Lists function)
		//
		// YapDatabase has extensive documentation for views:
		// https://github.com/yapstudios/YapDatabase/wiki/Views
		
		// GROUPING CLOSURE:
		//
		// Group the Task's into groups based on their List.
		// Only include Tasks that are NOT complete.
		//
		let grouping = YapDatabaseViewGrouping.withObjectBlock(
		{(transaction, collection, key, obj) -> String? in
			
			if let task = obj as? Task {
				
				if !task.completed {
					return task.listID
				}
			}
			
			return nil
		})
		
		// SORTING CLOSURE:
		//
		// It doesn't matter how we sort these Tasks.
		// We're only interested in the count (per List).
		//
		let sorting = YapDatabaseViewSorting.withObjectBlock({
			(transaction, group, collection1, key1, obj1, collection2, key2, obj2) -> ComparisonResult in
			
			let task1 = obj1 as! Task
			let task2 = obj2 as! Task
			
			return task1.uuid.compare(task2.uuid)
		})
		
		let versionTag =  "2019-02-04-x"; // <---------- change me if you modify grouping or sorting closure
		
		let options = YapDatabaseViewOptions()
		options.allowedCollections = YapWhitelistBlacklist(whitelist: Set([kCollection_Tasks]))

		let view = YapDatabaseAutoView(grouping: grouping,
		                                sorting: sorting,
		                             versionTag: versionTag,
		                                options: options)

		let extName = Ext_View_Pending_Tasks
		database.asyncRegister(view, withName: extName) { (ready) in
			
			if !ready {
				DDLogError("Error registering \(extName) !!!")
			}
		}
	}
	
	/// In our UI, we have a TableView that displays all the List items.
	/// And within the TableView row, we display information concerning the Task's within the List.
	/// For example:
	///
	/// > Weekend Chores
	/// > 2 tasks remaining, 5 total
	///
	/// In practice, this means we need to update this TableView cell whenever either:
	///
	/// - The List is changed
	/// - Any children Tasks are added/modified/deleted
	///
	/// YapDatabase has a few tricks we can use to simplify the work we need to do.
	/// First, we setup our UI (in ListsViewController) so that it listens for changes to any List.
	/// Then, we add hooks so that if a Task is changed, we will automatically "touch" the parent List.
	/// And by "touching" a List item, it will get reported to the UI via the database listeners.
	///
	private func registerExtension_Hooks(_ database: YapDatabase) {
		
		let hooks = YapDatabaseHooks()
		
		// DidModifyRow:
		//
		//   This closure is called after an item is inserted or modified in the database.
		//
		hooks.didModifyRow = {(transaction: YapDatabaseReadWriteTransaction, collection: String, key: String,
			proxyObject: YapProxyObject, _, _) in
			
			if collection == kCollection_Tasks,
				let task = proxyObject.realObject as? Task
			{
				// A Task item was inserted or modified.
				// So we "touch" the parent List, which will trigger a UI update for it.
				//
				transaction.touchObject(forKey: task.listID, inCollection: kCollection_Lists)
			}
		}
		
		// WillRemoveRow:
		//
		//   This closure is called before an item is removed from the database.
		//
		hooks.willRemoveRow = {(transaction: YapDatabaseReadWriteTransaction, collection: String, key: String) in
			
			if collection == kCollection_Tasks,
				let task = transaction.object(forKey: key, inCollection: collection) as? Task
			{
				// A Task item will be deleted.
				// So we "touch" the parent List, which will trigger a UI update for it.
				//
				transaction.touchObject(forKey: task.listID, inCollection: kCollection_Lists)
			}
		}
		
		let extName = Ext_Hooks
		database.asyncRegister(hooks, withName: extName) {(ready) in
			
			if !ready {
				DDLogError("Error registering \(extName) !!!")
			}
		}
	}
	
	private func setupUIDatabaseConnection(_ db: YapDatabase) {
		
		_uiDatabaseConnection = db.newConnection()
		_uiDatabaseConnection?.objectCacheLimit = 1000;
		_uiDatabaseConnection?.metadataCacheLimit = 1000;
		_uiDatabaseConnection?.name = "uiDatabaseConnection"
		
	#if DEBUG
		_uiDatabaseConnection?.permittedTransactions = [.YDB_MainThreadOnly, .YDB_SyncReadTransaction] // NO asyncReads!
	#endif
		
		_uiDatabaseConnection?.enableExceptionsForImplicitlyEndingLongLivedReadTransaction()
		_uiDatabaseConnection?.beginLongLivedReadTransaction()
		
		let nc = NotificationCenter.default
		nc.addObserver( self,
		      selector: #selector(self.databaseModified(notification:)),
		          name: Notification.Name.YapDatabaseModified,
		        object: db)
	}
	
	public func uiDatabaseConnection() -> YapDatabaseConnection? {
		
		assert(Thread.isMainThread, "Can't use the uiDatabaseConnection outside the main thread")
		return _uiDatabaseConnection
	}
	
	@objc func databaseModified(notification: Notification) {
		
		guard let uiDatabaseConnection = _uiDatabaseConnection else {
			return
		}
		
		let nc = NotificationCenter.default
		
		// Notify observers we're about to update the database connection
		nc.post(name: Notification.Name.UIDBConnectionWillUpdate, object: self)
		
		// Move uiDatabaseConnection to the latest commit.
		// Function returns all the notifications for each commit we jump.
		
		let notifications = uiDatabaseConnection.beginLongLivedReadTransaction()
		
		// Notify observers that the uiDatabaseConnection was updated
		let userInfo = ["notifications": notifications]

		nc.post(name: Notification.Name.UIDBConnectionDidUpdate,
		      object: self,
		    userInfo: userInfo)
	}
}
