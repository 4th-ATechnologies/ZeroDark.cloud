/// ZeroDark.cloud
///
/// Homepage      : https://www.zerodark.cloud
/// GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
/// Documentation : https://zerodarkcloud.readthedocs.io/en/latest
/// API Reference : https://apis.zerodark.cloud
///
/// Sample App: ZeroDarkTodo

import UIKit
import Photos
import YapDatabase
import ZeroDarkCloud
import ImageScrollView

protocol TaskPhotoViewControllerDelegate: class {
	func taskPhotoImageWasUpdated(image: UIImage?) 
}

class TaskPhotoViewController: UIViewController, UINavigationControllerDelegate, UIImagePickerControllerDelegate{
	
	@IBOutlet weak var imgPhoto: ImageScrollView!
	
	weak var delegate : TaskPhotoViewControllerDelegate!

	var taskID : String!
	var imageNodeID: String?
	var databaseConnection: YapDatabaseConnection!
	var newImage: UIImage?
	
	var isDisplayingFullSizeImage: Bool = false
	
	lazy var imagePicker = UIImagePickerController()
	
	class func `initWithDelegate`(delegate: TaskPhotoViewControllerDelegate, taskID: String) -> TaskPhotoViewController {
		
		let storyboard = UIStoryboard(name: "Main", bundle: nil)
		let vc = storyboard.instantiateViewController(withIdentifier: "TaskPhotoViewController") as? TaskPhotoViewController
		
		vc?.taskID = taskID
		vc?.delegate = delegate;
		return vc!

		}
 
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: View Lifecycle
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	override func viewDidLoad() {
		imgPhoto.setup()
	}
	
	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		
		self.setupDatabaseConnection()
		self.refreshView()
	}
	
	override func viewDidDisappear(_ animated: Bool) {
		super.viewDidDisappear(animated)
		
		NotificationCenter.default.removeObserver(self)
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Refresh
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	private func defaultImage() -> UIImage? {
		
		return UIImage.init(named: "photos_ios")
	}
	
	private func refreshView() {
		
		let zdc = ZDCManager.zdc()
		let localUserID = AppDelegate.sharedInstance().currentLocalUserID!
		
		var task: Task? = nil
		var imageNode: ZDCNode? = nil
		
		databaseConnection?.read { (transaction) in
			
			task = transaction.object(forKey: self.taskID, inCollection: kZ2DCollection_Task) as? Task
			
			// We don't create an explicit object for the TaskImage.
			// That is, we have the following model classes:
			// - List
			// - Task
			//
			// But there is no TaskImage class.
			// Because, well, it's just an image. It doesn't have any properties to store.
			//
			// So instead we store the image to disk via the ZDCDiskManager.
			// And we create a corresponding ZDCNode in the treesystem so that it gets uploaded properly.
			//
			// OK, so then how do we know if a Task has an associated image ?
			// Just check to see if there's a corresponding ZDCNode for the image.
			//
			// We can do this by asking the treesystem for the childNode with name "img".
			
			if
				let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: localUserID),
				let taskNode = cloudTransaction.linkedNode(forKey: self.taskID, inCollection: kZ2DCollection_Task)
			{
				imageNode =
				  zdc.nodeManager.findNode(withName    : "img",
				                           parentID    : taskNode.uuid,
				                           transaction : transaction)
			}
		}
		
		self.navigationItem.title = task?.title ?? "Unknown"
		
		// The image may or may not be downloaded.
		//
		// For example, if deviceA originally created the task, and uploaded the image,
		// then deviceB may not have the image downloaded at this point.
		//
		// In fact, as an optimization, we don't download the images when we discover them in the cloud.
		// Instead, we download them on demand. Otherwise we may be downloading a bunch of images
		// the user may never even bother looking at.
		
		imageNodeID = imageNode?.uuid
		
		if let imageNode = imageNode {
			
			loadThumbnail(imageNode)
			loadFullSizeImage(imageNode)
		}
		else {
			self.imgPhoto.display(image:self.defaultImage()!)
		}
	}
	
	private func loadThumbnail(_ imageNode: ZDCNode) {
		
		let zdc = ZDCManager.zdc()
		
		// We probably already have the thumbnail for this image (if it exists).
		//
		// This is because both the TasksViewController & TaskDetailsViewController fetch the thumbanil.
		// So the user has already gone through 2 view controllers,
		// which both requested a download of the thumbanail already.
		//
		// Which means it's probably a good idea to display the thumbnail first,
		// while we wait for the full image to download.
		//
		// Now, there's no guarantee the thumbnail is downloaded.
		// If the Internet is going slow, it might still be in-flight.
		// But even if that's the case, it's still a good idea to try to fetch the thumbnail first.
		//
		// Here's why:
		// 1.) The DownloadManager automatically coalesces multiple requests for the same thing.
		//     So requesting the thumbnail again (via the ImageManager) won't trigger an additional download.
		//
		// 2.) Since the thumbnail is smaller, it's likely to arrive before the full image.
		//     So we might as well display it first for the user.
		
		let preFetch = {(image: UIImage?, willFetch: Bool) in
			
			// The preFetch closure is invoked BEFORE the fetchNodeThumbnail() function returns.
			if let image = image ?? self.defaultImage() {
				self.imgPhoto.display(image: image)
			}
		}
		let postFetch = {[weak self] (image: UIImage?, error: Error?) in
			
			if self?.isDisplayingFullSizeImage ?? true {
				return
			}
			
			if let image = image {
				self?.imgPhoto.display(image: image)
			}
		}
		
		let options = ZDCFetchOptions()
		options.downloadIfMarkedAsNeedsDownload = true
		
		zdc.imageManager?.fetchNodeThumbnail(imageNode, with: options, preFetch: preFetch, postFetch: postFetch)
	}
	
	private func loadFullSizeImage(_ imageNode: ZDCNode) {
		
		let zdc = ZDCManager.zdc()
		
		let updateUI = {[weak self] (image: UIImage) -> Void in
			
			assert(Thread.isMainThread, "Bad programmer - no cookie")
			
			self?.imgPhoto.display(image:image)
			self?.isDisplayingFullSizeImage = true
		}
		
		let decryptImage = {(cryptoFile: ZDCCryptoFile) -> Void in
			
			ZDCFileConversion.decryptCryptoFile(intoMemory: cryptoFile,
			                                    completionQueue: DispatchQueue.global(),
			                                    completionBlock:
			{ (rawImageData: Data?, error: Error?) in
				
				if
					let rawImageData = rawImageData,
					let image = UIImage(data: rawImageData)
				{
					DispatchQueue.main.async {
						updateUI(image)
					}
				}
			})
		}
		
		// Fetch the full version of the file from the DiskManager.
		// This version may or may not be out-of-date.
		//
		let export = zdc.diskManager?.nodeData(imageNode)
		
		let isMissing = (export == nil)
		var isOutOfDate = false
		if !isMissing {
			
			databaseConnection.read {(transaction) in
				
				if let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: imageNode.localUserID) {
					
					isOutOfDate = cloudTransaction.nodeIsMarkedAsNeedsDownload(imageNode.uuid, components: .data)
				}
			}
		}
		
		if !isOutOfDate {
			
			if let cryptoFile = export?.cryptoFile {
				decryptImage(cryptoFile)
			}
		}
		
		if isMissing || isOutOfDate {
			
			let options = ZDCDownloadOptions()
			options.cacheToDiskManager = true
			options.canDownloadWhileInBackground = true
			
			zdc.downloadManager?.downloadNodeData(imageNode,
			                                      options: options,
			                                      completionQueue: DispatchQueue.global(),
			                                      completionBlock:
			{[weak self] (cloudDataInfo: ZDCCloudDataInfo?, cryptoFile: ZDCCryptoFile?, error: Error?) in
				
				if let cloudDataInfo = cloudDataInfo,
				   let cryptoFile = cryptoFile
				{
					decryptImage(cryptoFile)
					self?.unmarkNodeAsNeedsDownload(imageNode, eTag: cloudDataInfo.eTag)
				}
			})
		}
	}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Database
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	private func setupDatabaseConnection() {
		
		let zdc = ZDCManager.zdc()
		databaseConnection = zdc.databaseManager!.uiDatabaseConnection

		NotificationCenter.default.addObserver( self,
		                              selector: #selector(self.databaseConnectionDidUpdate(notification:)),
		                                  name: .UIDatabaseConnectionDidUpdate,
		                                object: nil)
	}

	@objc func databaseConnectionDidUpdate(notification: Notification) {
		
		let notifications = notification.userInfo?[kNotificationsKey] as! [Notification]
		var hasChanges = false
		
		if (taskID != nil) {
			
			hasChanges = databaseConnection.hasChange(forKey: taskID,
			                                          inCollection: kZ2DCollection_Task,
			                                          in: notifications)
		}
		
		if hasChanges {
			self.refreshView()
		}
	}
	
	private func unmarkNodeAsNeedsDownload(_ node: ZDCNode, eTag: String) {
		
		let zdc = ZDCManager.zdc()
		let rwConnection = zdc.databaseManager!.rwDatabaseConnection
		
		rwConnection.asyncReadWrite { (transaction) in
			
			if let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: node.localUserID) {
				
				cloudTransaction.unmarkNodeAsNeedsDownload(node.uuid, components: .data, ifETagMatches: eTag)
			}
		}
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Actions
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	@IBAction func btnDeleteClicked(_ sender: Any) {
		
		let alert =
			UIAlertController(title: "Remove Photo",
			                  message: "Are you sure you want remove this photo from the task?",
									preferredStyle: .alert)
		
		let clearAction = UIAlertAction(title: "Remove", style: .destructive) { (alert: UIAlertAction!) -> Void in
			
			self.imgPhoto.display(image:self.defaultImage()!)
			self.delegate?.taskPhotoImageWasUpdated(image: nil);
			self.navigationController?.popViewController(animated: true)
		}
		
		let cancelAction = UIAlertAction(title: "Cancel", style: .default) { (alert: UIAlertAction!) -> Void in
			
			// Nothing to do here
		}
		
		alert.addAction(clearAction)
		alert.addAction(cancelAction)
		
		present(alert, animated: true, completion:nil)
	}
	
	@IBAction func btnEditClicked(_ sender: Any) {
		
		AppDelegate.checkForCameraAvailable(viewController: self) { (isAvailable) in
			
			if isAvailable {
				
				if UIImagePickerController.isSourceTypeAvailable(.savedPhotosAlbum){
					
					self.imagePicker.delegate = self
					self.imagePicker.sourceType = .photoLibrary;
					self.imagePicker.allowsEditing = false
					self.imagePicker.modalPresentationStyle = .overCurrentContext
					self.present(self.imagePicker, animated: true, completion: nil)
				}
			}
		}
		
	}
	
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: - UIImagePickerControllerDelegate
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
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
		
		if let pickedImage = pickedImage {
			
			let orientedImage = pickedImage.correctOrientation()
			
			self.imgPhoto.display(image:orientedImage);
			self.delegate?.taskPhotoImageWasUpdated(image: orientedImage);
		}
	}
	
	func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
		
		dismiss(animated: true, completion:nil)
	}
}
