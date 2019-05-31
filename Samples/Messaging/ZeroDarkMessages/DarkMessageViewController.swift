/**
* ZeroDark.cloud
* <GitHub wiki link goes here>
*
* Sample App: ZeroDarkMessages
**/

import UIKit
import YapDatabase
import ZeroDarkCloud
import MessageKit

struct MessageUser: SenderType, Equatable {
	var senderId: String
	var displayName: String
}

class DarkMessageViewController:  MessagesViewController  {
	
	var localUserID: String = ""
	var databaseConnection: YapDatabaseConnection!
	var currentSender: MessageUser?

	override func viewDidLoad() {
		super.viewDidLoad()
		
		
//
//		configureMessageCollectionView()
//		configureMessageInputBar()
//		loadFirstMessages()
//		title = "MessageKit"
		
	}

	
	class func initWithLocalUserID(_ localUserID: String) -> DarkMessageViewController {
		let vc = self.init()
		vc.localUserID = localUserID
		return vc
	}
	
	override func viewWillAppear(_ animated: Bool) {
		
		databaseConnection = ZDCManager.uiDatabaseConnection()
		
		var localUser: ZDCLocalUser!
		databaseConnection .read { (transaction) in
			localUser = transaction.object(forKey: self.localUserID, inCollection: kZDCCollection_Users) as? ZDCLocalUser
		}

		if let localUser = localUser {
				currentSender = MessageUser(senderId: localUser.uuid, displayName: localUser.displayName)
	 		}
	
		
	}
	
	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		
//		MockSocket.shared.connect(with: [SampleData.shared.nathan, SampleData.shared.wu])
//			.onNewMessage { [weak self] message in
//				self?.insertMessage(message)
//		}
	}
	
	override func viewDidDisappear(_ animated: Bool) {
		super.viewDidDisappear(animated)
//		MockSocket.shared.disconnect()
 	}

	
//	func currentSender() -> SenderType {
//		<#code#>
//	}
//
//	func messageForItem(at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> MessageType {
//		<#code#>
//	}
//
//	func numberOfSections(in messagesCollectionView: MessagesCollectionView) -> Int {
//
//	}
//


}

