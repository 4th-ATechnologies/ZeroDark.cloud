/// ZeroDark.cloud
///
/// Homepage      : https://www.zerodark.cloud
/// GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
/// Documentation : https://zerodarkcloud.readthedocs.io/en/latest
/// API Reference : https://apis.zerodark.cloud
///
/// Sample App: WhatsZapp

import Foundation
import CocoaLumberjack
import ZeroDarkCloud

import os


class ConversationsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
	
	var localUserID: String = ""
	var navTitleButton: IconTitleButton?
	
	var uiDatabaseConnection: YapDatabaseConnection?
	var mappings: YapDatabaseViewMappings?
	
	@IBOutlet var tableView: UITableView!
	@IBOutlet var simulatorView : UIView!

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Creation
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	class func create(localUserID: String) -> ConversationsViewController? {
		let storyboard = UIStoryboard(name: "Main", bundle: nil)
		let vc = storyboard.instantiateViewController(withIdentifier: "ConversationsViewController") as? ConversationsViewController
		
		vc?.localUserID = localUserID
		return vc
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: View Lifecycle
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	override func viewDidLoad() {
	#if DEBUG
		dynamicLogLevel = .all
	#else
		dynamicLogLevel = .warning
	#endif
	
		DDLogInfo("viewDidLoad()")
		super.viewDidLoad()
		
		#if targetEnvironment(simulator)
		do { // running on the simulator
			
			// Apple doesn't support push notifications on the simulator :(
			// So we have to fake it with a button.
			
			let offset = simulatorView.frame.height
			
			tableView.scrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: offset, right: 0)
			tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: offset, right: 0)
		}
		#else
		do { // running on a real device
			
			simulatorView.hidden = true
		}
		#endif
		
		uiDatabaseConnection = ZDCManager.zdc().databaseManager?.uiDatabaseConnection
		initializeMappings()
		
		let nc = NotificationCenter.default
		
		nc.addObserver( self,
		       selector: #selector(self.uiDatabaseConnectionDidUpdate(_:)),
		           name: Notification.Name.UIDatabaseConnectionDidUpdate,
		         object: nil)
		
		nc.addObserver(self,
		      selector: #selector(self.diskManagerChanged(_:)),
		          name: Notification.Name.ZDCDiskManagerChanged,
		        object: nil)
	}
	
	override func viewWillAppear(_ animated: Bool) {
		
		DDLogInfo("viewWillAppear()")
		super.viewWillAppear(animated)
		
		if let localUser = self.localUser() {
			configureNavigationTitle(localUser)
		}
		
		self.navigationItem.rightBarButtonItem =
		  UIBarButtonItem(barButtonSystemItem: .add,
		                               target: self,
		                               action: #selector(self.didTapPlusButton(_:)))
	}
	
	override func viewDidAppear(_ animated: Bool) {
		
		DDLogInfo("viewDidAppear")
		super.viewDidAppear(animated)
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Utilities
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	private func initializeMappings() {
		
		// What are YapDatabaseViewMappings ???
		//
		// Mappings are explained extensively in the docs:
		// https://github.com/yapstudios/YapDatabase/wiki/Views#mappings
		
		uiDatabaseConnection?.read({ (transaction) in
			
			if let _ = transaction.ext(DBExt_ConversationsView) as? YapDatabaseViewTransaction {
				
				self.mappings = YapDatabaseViewMappings.init(groups: [""], view: DBExt_ConversationsView)
				self.mappings?.update(with: transaction)
			}
			else {
				// Waiting for view to finish registering
			}
		})
	}
	
	private func configureNavigationTitle(_ localUser: ZDCLocalUser) {
		
		DDLogInfo("configureNavigationTitle()")
		
		if navTitleButton == nil {
			
			navTitleButton = IconTitleButton.create()
			navTitleButton?.setTitleColor(self.view.tintColor, for: .normal)
			navTitleButton?.addTarget( self,
			                   action: #selector(self.didTapNavTitleButton(_:)),
			                      for: .touchUpInside)
		}
		
		navTitleButton?.setTitle(localUser.displayName, for: .normal)
		navTitleButton?.isEnabled = true
		self.navigationItem.titleView = navTitleButton
		
		let imageManager = ZDCManager.zdc().imageManager!
		
		let size = CGSize(width: 30, height: 30)
		let defaultImage = {
			return imageManager.defaultUserAvatar().scaled(to: size, scalingMode: .aspectFit)
		}
		let processing = {(image: UIImage) in
			return image.scaled(to: size, scalingMode: .aspectFit)
		}
		let preFetch = {[weak self] (image: UIImage?, willFetch: Bool) -> Void in
			
			// This closure is invoked BEFORE the fetchUserAvatar() function returns.
			
			self?.navTitleButton?.setImage(image ?? defaultImage(), for: .normal)
		}
		let postFetch = {[weak self] (image: UIImage?, error: Error?) -> Void in
			
			// This closure in invoked later, after the imageManager has fetched the image.
			//
			// The image may be cached on disk, in which case it's invoked shortly.
			// Or the image may need to be downloaded, which takes longer.
			
			self?.navTitleButton?.setImage(image ?? defaultImage(), for: .normal)
		}
		
		imageManager.fetchUserAvatar( localUser,
		            withProcessingID: "navTitle",
		             processingBlock: processing,
		                    preFetch: preFetch,
		                   postFetch: postFetch)
	}
	
	private func conversation(indexPath: IndexPath) -> Conversation? {
		
		guard let mappings = self.mappings else {
			return nil
		}
		
		// In DBManager, we setup a YapDatabaseAutoView that automatically sorts all conversations
		// according to their `lastActivity` property.
		
		var conversation: Conversation? = nil
		uiDatabaseConnection?.read({ (transaction) in
			
			if let viewTransaction = transaction.ext(DBExt_ConversationsView) as? YapDatabaseViewTransaction {
				
				conversation = viewTransaction.object(at: indexPath, with: mappings) as? Conversation
			}
		})
		
		return conversation
	}
	
	private func mostRecentMessage(in conversation: Conversation) -> Message? {
		
		// In DBManager, we setup a YapDatabaseAutoView that automatically sorts all messages
		// within each conversation, according to their date:
		//
		// - the earliest message is at index zero
		// - the latest message is at index last
		//
		// So all we need to do is use this view, and ask it for the lastObject within the conversation group.
		
		var message: Message? = nil
		uiDatabaseConnection?.read({ (transaction) in
			
			if let viewTransaction = transaction.ext(DBExt_MessagesView) as? YapDatabaseViewTransaction {
				
				message = viewTransaction.lastObject(inGroup: conversation.uuid) as? Message
			}
		})
		
		return message
	}
	
	private func unreadCount(in conversation: Conversation) -> UInt {
		
		var unreadCount: UInt = 0
		uiDatabaseConnection?.read({ (transaction) in
			
			if let viewTransaction = transaction.ext(DBExt_UnreadMessagesView) as? YapDatabaseViewTransaction {
				
				unreadCount = viewTransaction.numberOfItems(inGroup: conversation.uuid)
			}
		})
		
		return unreadCount
	}
	
	func localUser() -> ZDCLocalUser? {
		
		var localUser: ZDCLocalUser? = nil
		uiDatabaseConnection?.read({ (transaction) in
			
			localUser = transaction.localUser(id: localUserID)
		})
		
		return localUser
	}
	
	private func remoteUser(id userID: String) -> ZDCUser? {
		
		var user: ZDCUser? = nil
		uiDatabaseConnection?.read({ (transaction) in
			
			user = transaction.object(forKey: userID, inCollection: kZDCCollection_Users) as? ZDCUser
		})
		
		if (user != nil) {
			return user
		}
		
		// The user doesn't exist in the database yet.
		// So we're goint to ask ZDC to fetch the user for us.
		// After that completes, we'll refresh the corresponding row in the tableView.
		//
		// Note: The ZDCRemoteUserManager consolidates multiple requests.
		// So if we make this request a hundred times, it will only do a single network request.
		
		let zdc = ZDCManager.zdc()
		zdc.remoteUserManager?.fetchRemoteUser(withID: userID,
		                                  requesterID: self.localUserID,
		                              completionQueue: DispatchQueue.main,
		                              completionBlock:
		{[weak self] (user: ZDCUser?, error: Error?) in
			
			if let user = user {
				self?.updateVisibleRow(forUser: user)
			}
		})
		
		return nil
	}
	
	private func updateVisibleRow(forUser user: ZDCUser) {
		
		guard let indexPaths = tableView.indexPathsForVisibleRows else {
			return
		}
		
		var matchingIndexPath: IndexPath?
		for indexPath in indexPaths {
			
			if let conversation = self.conversation(indexPath: indexPath) {
				
				if conversation.remoteUserID == user.uuid {
					matchingIndexPath = indexPath
					break
				}
			}
		}
		
		if let matchingIndexPath = matchingIndexPath {
			
			tableView.reloadRows(at: [matchingIndexPath], with: .none)
		}
	}
	
	private func createConversation(_ remoteUserID: String) {
		
		let zdc = ZDCManager.zdc()
		let localUserID = self.localUserID
		
		var conversation: Conversation = Conversation(remoteUserID: remoteUserID)
		
		let rwConnection = zdc.databaseManager?.rwDatabaseConnection
		rwConnection?.asyncReadWrite({ (transaction) in
			
			// Step 1 of 3:
			//
			// If the user selected a user for which we already have a conversation,
			// then we can just use the existing conversation.
			
			if let existingConversation = transaction.conversation(id: remoteUserID) {
				
				// We've already setup this conversation
				
				conversation = existingConversation
				return // from transaction block (i.e. jump to completionBlock below)
			}
			
			// Step 2 of 3:
			//
			// Create the conversation object, and write it to the database
			
			transaction.setConversation(conversation)
			
			// Step 3 of 3:
			//
			// Create the corresponding node in the ZDC treesystem.
			// This will trigger ZDC to upload the node to the cloud.
			
			guard let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: localUserID) else {
				return
			}
			
			// First we specify where we want to store the node in the cloud.
			// In this case, we want to use:
			//
			// home://{remoteUserID}
			//
			let path = ZDCTreesystemPath(pathComponents: [conversation.remoteUserID])
			
			do {
				// Then we tell ZDC to create a node at that path.
				// This will only fail if there's already a node at that path.
				//
				let node = try cloudTransaction.createNode(withPath: path)
				//
				// ^ OK, that worked,
				// Which means ZDC now has a node that's queued to be uploaded.
				// So when ZDC is ready to upload the node it will ask the ZeroDarkCloudDelegate for the data.
				//
				// In this app, the ZeroDarkCloudDelegate == ZDCManager
				//
				// @see ZDCManager.data(for:at:transaction:)
				
				// And finally, we create a link between the zdc node and our conversation.
				// This isn't something that's required by ZDC.
				// It's just something we do because its useful for us, within the context of this application.
				//
				try cloudTransaction.linkNodeID(node.uuid, toConversationID: conversation.uuid)
				
			} catch {
				print("Error creating node: \(error)")
			}
			
		}, completionBlock: { [weak self] in
			
			self?.pushMessagesViewController(conversation)
		})
	}
	
	private func pushMessagesViewController(_ conversation: Conversation) {
		
		let msgsVC = MyMessagesViewController(localUserID: localUserID, conversationID: conversation.uuid)
		self.navigationController?.pushViewController(msgsVC, animated: true)
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Notifications
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	@objc private func uiDatabaseConnectionDidUpdate(_ notification: NSNotification) {
		
		guard let tableView = self.tableView else {
			return
		}
		
		guard let mappings = mappings else {
			
			initializeMappings()
			tableView.reloadData()
			return
		}
		
		guard
			let notifications = notification.userInfo?[kNotificationsKey] as? [Notification],
			let ext = uiDatabaseConnection?.ext(DBExt_ConversationsView) as? YapDatabaseViewConnection
		else {
			return
		}
		
		let (sectionChanges, rowChanges) = ext.getChanges(forNotifications: notifications, withMappings: mappings)
		
		if (sectionChanges.count == 0) && (rowChanges.count == 0) {
			// No changes for the tableView
			return
		}
		
		var indexPathsToReload: [IndexPath] = []
		
		tableView.performBatchUpdates({
			
			for rowChange in rowChanges {
				switch rowChange.type {
					 
					case .delete:
						tableView.deleteRows(at: [rowChange.indexPath!], with: .automatic)
					
					case .insert:
						tableView.insertRows(at: [rowChange.newIndexPath!], with: .automatic)
					 
					case .move:
						tableView.moveRow(at: rowChange.indexPath!, to: rowChange.newIndexPath!)
						if rowChange.changes.contains(.changedObject) {
							indexPathsToReload.append(rowChange.newIndexPath!)
						}
					
					case .update:
						tableView.reloadRows(at: [rowChange.indexPath!], with: .automatic)
					
					default:
						break
				}
			}
			
		}, completion: {(completed) in
			
			// UITableView crashes if we try to perform both a move + reload on the same indexPath.
			// Which is kinda silly.
			// I mean, if a cell is moving, that doesn't exclude it from also changing...
			//
			// So we're trying to workaround Apple's bugs here.
			//
			if indexPathsToReload.count > 0 {
				tableView.reloadRows(at: indexPathsToReload, with: .automatic)
			}
		})
	}
	
	@objc private func diskManagerChanged(_ notification: NSNotification) {
		
		if let changes = notification.userInfo?[kZDCDiskManagerChanges] as? ZDCDiskManagerChanges {
		
			if changes.changedUsersIDs.contains(localUserID) {
				
				// The localUser's avatar may have changed.
				// Refresh the nav title.
				
				if let localUser = self.localUser() {
					self.configureNavigationTitle(localUser)
				}
			}
		}
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: User Actions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	@objc func didTapNavTitleButton(_ sender: Any) {
		
		DDLogInfo("didTapNavTitleButton()")
		
		let uiTools = ZDCManager.zdc().uiTools!
		if let navigationController = self.navigationController {
			
			uiTools.pushSettings(forLocalUserID: self.localUserID, with: navigationController)
		}
	}
	
	@objc func didTapPlusButton(_ sender: Any) {
		
		DDLogInfo("didTapPlusButton()")

		guard let navigationController = self.navigationController else {
			return
		}
		
		let completion: SharedUsersViewCompletionHandler = {[weak self] (addedUserIDs, removedUserIDs) in
			
			DDLogInfo("completionHandler")
			
			if let remoteUserID = addedUserIDs.first {
				self?.createConversation(remoteUserID)
			}
		}
		
		let uiTools = ZDCManager.zdc().uiTools!
		uiTools.pushSharedUsersView(forLocalUserID: self.localUserID,
		                             remoteUserIDs: nil,
		                                     title: "New Conversation",
		                      navigationController: navigationController,
		                         completionHandler: completion)
	}
	
	@IBAction func didTapSimulatePushNotification(_ sender: Any) {
		
		DDLogInfo("didTapSimulatePushNotification()")
		
		let zdc = ZDCManager.zdc()
		zdc.syncManager?.pullChangesForAllLocalUsers()
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: UITableViewDataSource
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	func numberOfSections(in tableView: UITableView) -> Int {
		
		if let mappings = mappings {
			return Int(mappings.numberOfSections())
		}
		else {
			return 0
		}
	}
	
	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		
		if let mappings = mappings {
			return Int(mappings.numberOfItems(inSection: UInt(section)))
		}
		else {
			return 0
		}
	}
	
	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		
		let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! ConversationTableViewCell
		
		if let conversation = self.conversation(indexPath: indexPath) {
			
			let conversationID = conversation.uuid
			cell.conversationID = conversation.uuid
			
			let imageManager = ZDCManager.zdc().imageManager!
			
			let avatarSize = cell.avatarView.frame.size
			let defaultImage = {
				return imageManager.defaultUserAvatar().scaled(to: avatarSize, scalingMode: .aspectFit)
			}
			
			if let remoteUser = self.remoteUser(id: conversation.remoteUserID) {
				
				cell.titleLabel.text = remoteUser.displayName
				
				let processing = {(image: UIImage) in
					return image.scaled(to: avatarSize, scalingMode: .aspectFit)
				}
				let preFetch = {(image: UIImage?, willFetch: Bool) -> Void in
					
					// This closure is invoked BEFORE the fetchUserAvatar() function returns.
					
					cell.avatarView.image = image ?? defaultImage()
				}
				let postFetch = {[weak cell] (image: UIImage?, error: Error?) -> Void in
					
					// This closure in invoked later, after the imageManager has fetched the image.
					//
					// The image may be cached on disk, in which case it's invoked shortly.
					// Or the image may need to be downloaded, which takes longer.
					
					if conversationID == cell?.conversationID {
						cell?.avatarView.image = image ?? defaultImage()
					}
				}
				
				imageManager.fetchUserAvatar( remoteUser,
								withProcessingID: "convoCellAvatar",
								 processingBlock: processing,
										  preFetch: preFetch,
										 postFetch: postFetch)
			}
			else {
				
				cell.titleLabel.text = "Fetching user information..."
				cell.avatarView.image = defaultImage()
			}
			
			if let mostRecentMsg = self.mostRecentMessage(in: conversation) {
		
				cell.dateLabel.isHidden = false
				cell.dateLabel.text = mostRecentMsg.date.whenString()
				
				if mostRecentMsg.hasAttachment {
					cell.messageLabel.text = "<image>"
				} else {
					cell.messageLabel.text = mostRecentMsg.text
				}
			}
			else {
				
				cell.dateLabel.isHidden = true
				
				cell.messageLabel.text = "empty conversation"
			}
			
			let unreadCount = self.unreadCount(in: conversation)
			if unreadCount == 0 {
				
				cell.badgeLabel.isHidden = true
			}
			else {
				
				cell.badgeLabel.isHidden = false
				
				if unreadCount < 100 {
					cell.badgeLabel.text = String(unreadCount)
				} else {
					cell.badgeLabel.text = "99+"
				}
			}
		}
		
		return cell
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: UITableViewDelegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		
		if let conversation = self.conversation(indexPath: indexPath) {
			
			self.pushMessagesViewController(conversation)
		}
		
		tableView.deselectRow(at: indexPath, animated: true)
	}
}
