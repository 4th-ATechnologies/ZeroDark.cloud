/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
 *
 * Sample App: ZeroDarkTodo
**/

import UIKit
import YapDatabase
import ZeroDarkCloud

class FitButton: UIButton {

	required init?(coder aDecoder: NSCoder) {
		super.init(coder: aDecoder)
	}

	override func layoutSubviews() {
		self.imageEdgeInsets = UIEdgeInsets(top: 4, left:4, bottom: 4, right: 4)
		self.imageView?.contentMode = .scaleAspectFit
		self.contentHorizontalAlignment = .center
		self.contentVerticalAlignment = .center
		super.layoutSubviews()
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

class TaskDetailsViewController: UIViewController, TaskPhotoViewControllerDelegate,
                          UITextViewDelegate, UINavigationControllerDelegate, UIImagePickerControllerDelegate
{
	@IBOutlet public var btnIcon : FitButton!
	@IBOutlet public var hitView : UIView!
	@IBOutlet public var checkMark : SSCheckMark!
	@IBOutlet public var seg : UISegmentedControl!
	@IBOutlet public var taskName : UITextView!
	@IBOutlet public var taskDetails : UITextView!

	@IBOutlet public var uuid : UILabel!
	@IBOutlet public var created : UILabel!
	@IBOutlet public var modifiedLabel : UILabel!
	@IBOutlet public var modifiedValue : UILabel!

	var taskID : String!
	var databaseConnection :YapDatabaseConnection!
	var tap: UITapGestureRecognizer!
	var imagePicker = UIImagePickerController()
	
	var imageWasUpdated: Bool = false
	var updatedImage: UIImage? = nil

	private let dateFormatter: DateFormatter = {
		let dateFormatter = DateFormatter()
		dateFormatter.dateFormat = "MMM d, h:mm a"
		return dateFormatter
	}()

	private let defaultImage = UIImage.init(named: "photos_ios")

	class func initWithTaskID(_ taskID: String) -> TaskDetailsViewController {
		
		let storyboard = UIStoryboard(name: "Main", bundle: nil)
		let vc = storyboard.instantiateViewController(withIdentifier: "TaskDetailsViewController") as? TaskDetailsViewController

		vc?.taskID = taskID
		return vc!
	}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: View Lifecycle
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	override func viewDidLoad() {
		super.viewDidLoad()
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		
		self.setupDatabaseConnection()

		tap = UITapGestureRecognizer(target: self, action: #selector(checkClicked))
		hitView.addGestureRecognizer(tap)

		btnIcon.layer.cornerRadius = 10
		btnIcon.layer.borderWidth = 1
		btnIcon.layer.borderColor = self.view.tintColor.cgColor

		taskName.delegate = self
		
		self.refreshView()
	}

	override func viewDidLayoutSubviews() {
		taskName.setContentOffset(.zero, animated: false)
		taskDetails.setContentOffset(.zero, animated: false)
	}

	override func viewWillDisappear(_ animated: Bool) {
		
		self.updateRecord()
	}
	
	override func viewDidDisappear(_ animated: Bool) {

		NotificationCenter.default.removeObserver(self)
		hitView.removeGestureRecognizer(tap)
	}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Refresh
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	private func reloadThumbnail() {
		
	}
	
	private func refreshView() {

		databaseConnection.read { (transaction) in
			
			guard
				let task = transaction.object(forKey: self.taskID, inCollection: kZ2DCollection_Task) as? Task
			else {
				return
			}
			
			self.navigationItem.title = task.title
			self.taskName.text = task.title
			self.taskDetails.text = task.details

			self.checkMark.checked = task.completed
			self.created.text =  self.dateFormatter.string(from:task.creationDate)
			self.uuid.text = task.uuid

			if (task.lastModified() != nil) {
				
				self.modifiedValue.text = self.dateFormatter.string(from:task.lastModified()!)
				self.modifiedLabel.isHidden = false
				self.modifiedValue.isHidden = false
			}
			else {
				
				self.modifiedLabel.isHidden = true
				self.modifiedValue.isHidden = true
			}
			
			self.seg.selectedSegmentIndex = task.priority.rawValue
			
			if(imageWasUpdated) {
				self.btnIcon.setImage((updatedImage ?? self.defaultImage), for: .normal)
			}
			else
			{
				if let imageNode = self.imageNode(forTask: task, transaction: transaction) {
					
					// The preFetch closure is invoked BEFORE the `fetchNodeThumbnail` function returns.
					//
					// If preFetch.willInvoke is false, the postFetch closure will NOT be called.
					//
					let preFetch = {(image: UIImage?, willInvoke: Bool) in
						
						self.btnIcon.setImage((image ?? self.defaultImage), for: .normal)
					}
					let postFetch = {(image: UIImage?, error: Error?) in
						
						if (image != nil) {
							self.btnIcon.setImage(image, for: .normal)
							
						} else {
							// Network request failed.
							// You may want to display an error image ?
						}
					}
					
					ZDCManager.imageManager().fetchNodeThumbnail(imageNode, preFetch: preFetch, postFetch: postFetch)
				}
				else {
					
					self.btnIcon.setImage(defaultImage, for: .normal)
				}
			}
	
		}
	}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Database
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	private func setupDatabaseConnection() {
		
		databaseConnection = ZDCManager.uiDatabaseConnection()

		NotificationCenter.default.addObserver(self,
											   selector: #selector(self.databaseConnectionDidUpdate(notification:)),
											   name:.UIDatabaseConnectionDidUpdateNotification ,
											   object: nil)
	}

	@objc func databaseConnectionDidUpdate(notification: Notification) {

		let notifications = notification.userInfo?[kNotificationsKey] as! [Notification]
		
		let hasChanges = databaseConnection.hasChange(
			forKey: taskID,
			inCollection: kZ2DCollection_Task,
			in: notifications
		)

		if hasChanges {
			self.refreshView()
		}
	}

	func imageNode(forTask task: Task, transaction: YapDatabaseReadTransaction) -> ZDCNode? {
		
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
		
		if let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: localUserID),
			let taskNode = cloudTransaction.linkedNode(forKey: task.uuid, inCollection: kZ2DCollection_Task)
		{
			imageNode = zdc.nodeManager.findNode(withName: "img", parentID: taskNode.uuid, transaction: transaction)
		}
		
		return imageNode
	}

	func updateRecord() {
		
		let newTitle = self.taskName.text
		let newDetails = self.taskDetails.text
		let newPriorty = TaskPriority(rawValue: ((self.seg?.selectedSegmentIndex)!))!
		let newCompleted = self.checkMark.checked
		
		let zdc = ZDCManager.zdc()
		let localUserID = AppDelegate.sharedInstance().currentLocalUserID!

		ZDCManager.rwDatabaseConnection().asyncReadWrite { (transaction) in
			
			guard
				var task = transaction.object(forKey: self.taskID, inCollection: kZ2DCollection_Task) as? Task
				else {
					return
			}
			
			task = task.copy() as! Task
			var needsUpdate = false
			
			if  (newTitle != nil)
				&& (newTitle!.count > 0)
				&& (newTitle! != task.title)
			{
				task.title = newTitle!
				needsUpdate = true
			}
			
			if (newDetails != task.details)
			{
				task.details = newDetails
				needsUpdate = true
			}
			
			if (newPriorty != task.priority)
			{
				task.priority = newPriorty
				needsUpdate = true
			}
			
			if (newCompleted != task.completed)
			{
				task.completed = newCompleted
				needsUpdate = true
			}
			
			if (needsUpdate)
			{
				task.localLastModified = Date()
				transaction.setObject(task , forKey: task.uuid, inCollection: kZ2DCollection_Task)
		
				if let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: localUserID),
					let taskNode = cloudTransaction.linkedNode(forKey: task.uuid, inCollection: kZ2DCollection_Task)
				{
					cloudTransaction.queueDataUpload(forNodeID: taskNode.uuid, withChangeset: nil)
				}

			}
		}
		
		if imageWasUpdated {

			if let newImage = updatedImage {
				ZDCManager.sharedInstance.setImage(newImage, forTaskID: self.taskID, localUserID: localUserID)
			}
			else {
				ZDCManager.sharedInstance.clearImage(forTaskID: self.taskID, localUserID: localUserID)
			}
			
		}
	}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Actions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
		super.touchesBegan(touches, with: event)
		
		let touch = touches.first
		if (touch?.view != taskName) {
			
			view.endEditing(true)
		}
	}
	
	@IBAction func priorityChanged(_ sender: Any) {

		self.updateRecord()
	}

	@IBAction func btnIconClicked(_ sender: Any) {

		var hasImage: Bool = false
		databaseConnection .read { (transaction) in
			
			if let task = transaction.object(forKey: self.taskID, inCollection: kZ2DCollection_Task) as? Task {
				
				let imageNode = self.imageNode(forTask: task, transaction: transaction)
				hasImage = (imageNode != nil)
			}
		}

		if hasImage {
			
			let itemVC = TaskPhotoViewController.initWithDelegate(delegate: self, taskID: taskID)
			self.navigationController?.pushViewController(itemVC, animated: true)
		}
		else {
			
			AppDelegate.checkForCameraAvailable(viewController: self) { (isAvailable) in
				
				if isAvailable {
					if UIImagePickerController.isSourceTypeAvailable(.savedPhotosAlbum) {

						self.imagePicker.delegate = self
						self.imagePicker.sourceType = .photoLibrary;
						self.imagePicker.allowsEditing = false
						self.imagePicker.modalPresentationStyle = .overCurrentContext
						self.present(self.imagePicker, animated: true, completion: nil)
					}
				}
			}
		}
	}

	@objc func checkClicked(recognizer: UITapGestureRecognizer) {

		let newValue:Bool  = !checkMark.checked
		checkMark.checked = newValue

		self.updateRecord()
	}

	func textViewDidEndEditing(_ textView: UITextView) {

		if(textView == taskName || textView == taskDetails)
		{
			self.updateRecord()
		}
	}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: UIImagePickerControllerDelegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	func imagePickerController(_ picker: UIImagePickerController,
	                           didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any])
	{
		picker.dismiss(animated: true)

		var pickedImage :UIImage?

		if (info[UIImagePickerController.InfoKey.editedImage] != nil)
		{
			pickedImage = info[UIImagePickerController.InfoKey.editedImage] as? UIImage
		}

		if (info[UIImagePickerController.InfoKey.originalImage] != nil)
		{
			pickedImage = info[UIImagePickerController.InfoKey.originalImage] as? UIImage
		}

		if let safeImage = pickedImage as UIImage? {
			
			let orientedImage =  safeImage.correctOrientation()
			
			btnIcon.setImage(orientedImage, for: .normal)
	 
			self.updatedImage = orientedImage
			self.imageWasUpdated = true
		}
	}

	func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
		
		picker.dismiss(animated: true, completion: nil)
	}
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	// MARK: TaskPhotoViewControllerDelegate
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

	func taskPhotoImageWasUpdated(image: UIImage?)
	{
		
		self.updatedImage = image
		self.imageWasUpdated = true
	}
	

}
