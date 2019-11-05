///
/// ZeroDark.cloud
///
/// Homepage      : https://www.zerodark.cloud
/// GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
/// Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
/// API Reference : https://apis.zerodark.cloud
///

import Foundation

extension ZDCNodeManager {
	
	public func iterateNodeIDs(withParentID parentID: String, transaction: YapDatabaseReadTransaction, using block: (String, inout Bool) -> Void) {
		
		let enumBlock = {(nodeID: String, outerStop: UnsafeMutablePointer<ObjCBool>) -> Void in
			
			var innerStop = false
			block(nodeID, &innerStop)
			
			if innerStop {
				outerStop.pointee = true
			}
		}
		
		self.enumerateNodeIDs(withParentID: parentID, transaction: transaction, using: enumBlock)
	}
	
	public func recursiveIterateNodeIDs(withParentID parentID: String, transaction: YapDatabaseReadTransaction, using block: (String, [String], inout Bool, inout Bool) -> Void) {
		
		let enumBlock = {(nodeID: String, pathFromParent: [String], outerRecurseInto: UnsafeMutablePointer<ObjCBool>, outerStop: UnsafeMutablePointer<ObjCBool>) -> Void in
			
			var innerRecurseInto = false
			var innerStop = false
			block(nodeID, pathFromParent, &innerRecurseInto, &innerStop)
			
			if innerRecurseInto {
				outerRecurseInto.pointee = true
			}
			if innerStop {
				outerStop.pointee = true
			}
		}
		
		self.recursiveEnumerateNodeIDs(withParentID: parentID, transaction: transaction, using: enumBlock)
	}
	
	public func iterateNodes(withParentID parentID: String, transaction: YapDatabaseReadTransaction, using block: (ZDCNode, inout Bool) -> Void) {
		
		let enumBlock = {(node: ZDCNode, outerStop: UnsafeMutablePointer<ObjCBool>) -> Void in
			
			var innerStop = false
			block(node, &innerStop)
			
			if innerStop {
				outerStop.pointee = true
			}
		}
		
		self.enumerateNodes(withParentID: parentID, transaction: transaction, using: enumBlock)
	}
	
	public func recursiveIterateNodes(withParentID parentID: String, transaction: YapDatabaseReadTransaction, using block: (ZDCNode, [ZDCNode], inout Bool, inout Bool) -> Void) {
		
		let enumBlock = {(node: ZDCNode, pathFromParent: [ZDCNode], outerRecurseInto: UnsafeMutablePointer<ObjCBool>, outerStop: UnsafeMutablePointer<ObjCBool>) -> Void in
			
			var innerRecurseInto = false
			var innerStop = false
			block(node, pathFromParent, &innerRecurseInto, &innerStop)
			
			if innerRecurseInto {
				outerRecurseInto.pointee = true
			}
			if innerStop {
				outerStop.pointee = true
			}
		}
		
		self.recursiveEnumerateNodes(withParentID: parentID, transaction: transaction, using: enumBlock)
	}
}
