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

class ConversationsViewController: UIViewController {
	
	var localUserID: String = ""
	var navTitleButton: IconTitleButton?
	
	@IBOutlet var tableView: UITableView!
	@IBOutlet var simulatorView : UIView!
	
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
	}
	
	override func viewWillAppear(_ animated: Bool) {
		
		DDLogInfo("viewWillAppear()")
		super.viewWillAppear(animated)
		
		let zdc = ZDCManager.zdc()
		
		var localUser: ZDCLocalUser?
		zdc.databaseManager?.uiDatabaseConnection.read({ (transaction) in
			
			localUser = transaction.localUser(id: self.localUserID)
		})
		
		if let localUser = localUser {
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
	
	private func writeConvo() {
		DDLogInfo("writeConvo")
		
		let convo = Conversation(remoteUserID: "bob")
		
		let rwConnection = ZDCManager.zdc().databaseManager!.rwDatabaseConnection
		rwConnection.asyncReadWrite { (transaction) in
			
			transaction.setObject(convo, forKey: "foobar", inCollection: "conversations")
		}
	}
	
	private func readConvo() {
		DDLogInfo("readConvo()")
		
		let rwConnection = ZDCManager.zdc().databaseManager!.rwDatabaseConnection
		rwConnection.asyncRead { (transaction) in
			
			if let convo = transaction.conversation(id: "foobar") {
				DDLogInfo("convo.remoteUserID = \(convo.remoteUserID)")
			}
			else {
				DDLogError("Alice is a lying whore")
			}
		}
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Navigation Bar
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
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
	
	@objc func didTapNavTitleButton(_ sender: Any) {
		
		DDLogInfo("didTapNavTitleButton()")
		
		let uiTools = ZDCManager.zdc().uiTools!
		if let navigationController = self.navigationController {
			
			uiTools.pushSettings(forLocalUserID: self.localUserID, with: navigationController)
		}
	}
	
	@objc func didTapPlusButton(_ sender: Any) {
		
		DDLogInfo("didTapPlusButton()")
/*
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
*/
		let msg = Message(conversationID: "foobar", text: "ur mom's a hoe")
		
		let rwConnection = ZDCManager.zdc().databaseManager!.rwDatabaseConnection
		rwConnection.asyncReadWrite { (transaction) in
			
		//	transaction.setObject(msg, forKey: msg.uuid, inCollection: kCollection_Messages)
			
			if let msgsViewTransaction = transaction.ext(DBExt_MessagesView) as? YapDatabaseViewTransaction {
				
				if let lastMsg = msgsViewTransaction.lastObject(inGroup: msg.conversationID) as? Message {
					
					print("lastMsg: \(lastMsg.text)")
				}
			}
		}
	}
	
	private func createConversation(_ remoteUserID: String) {
		
		let conversation = Conversation(remoteUserID: remoteUserID)
		
		let rwConnection = ZDCManager.zdc().databaseManager!.rwDatabaseConnection
		rwConnection.asyncReadWrite { (transaction) in
			
			transaction.setObject(conversation, forKey: conversation.uuid, inCollection: kCollection_Conversations)
		}
		
		// Todo...
	}
}
