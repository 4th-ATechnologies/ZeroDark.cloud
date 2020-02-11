/// ZeroDark.cloud
///
/// Homepage      : https://www.zerodark.cloud
/// GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
/// Documentation : https://zerodarkcloud.readthedocs.io/en/latest
/// API Reference : https://apis.zerodark.cloud
///

import UIKit
import ZeroDarkCloud

import os

class TestViewController: UIViewController {
	
	class func create(localUserID: String) -> TestViewController? {
		
		let storyboard = UIStoryboard(name: "Main", bundle: nil)
		let vc = storyboard.instantiateViewController(withIdentifier: "TestViewController") as? TestViewController
		
		vc?.localUserID = localUserID
		return vc
	}
	
	var localUserID: String = ""
	
	override func viewDidLoad() {
		super.viewDidLoad()
		os_log("TestViewController: viewDidLoad()")
		
		self.navigationItem.title = "Tests"
	}
	
	@IBAction
	private func showZdcOptions(sender: UIButton) {
		
		os_log("showZdcOptions()")
		
		if let uiTools = ZDCManager.zdc.uiTools,
		   let navigationController = self.navigationController
		{
			uiTools.pushSettings(forLocalUserID: self.localUserID, with: navigationController)
		}
	}
	
	@IBAction
	private func test1ButtonTapped(sender: UIButton) {
	
		os_log("test1ButtonTapped()")
		
		let zdc = ZDCManager.zdc
		let rwConnection = zdc.databaseManager!.rwDatabaseConnection
		
		rwConnection.asyncReadWrite { (transaction) in
			
			guard let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: self.localUserID) else {
				return // from block
			}
			
			let path = ZDCTreesystemPath(pathComponents: ["test1"])
			
			do {
				let _ = try cloudTransaction.createNode(withPath: path)
				
			} catch {
				os_log("Error creating node: %@", String(describing: error))
			}
		}
	}
	
	@IBAction
	private func test2ButtonTapped(sender: UIButton) {
		
		os_log("test2ButtonTapped()")
		
		let zdc = ZDCManager.zdc
		let rwConnection = zdc.databaseManager!.rwDatabaseConnection
		
		rwConnection.asyncReadWrite { (transaction) in
			
			guard let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: self.localUserID) else {
				return // from block
			}
			
			let path = ZDCTreesystemPath(pathComponents: ["test1"])
			
			if let node = cloudTransaction.node(path: path) {
				
				do {
					try cloudTransaction.delete(node)
				} catch {
					os_log("Error deleting node: %@", String(describing: error))
				}
			}
		}
	}
}
