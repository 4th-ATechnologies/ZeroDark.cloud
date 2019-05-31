/**
 * ZeroDark.cloud
 * <GitHub wiki link goes here>
**/

import Foundation

extension ZDCCloudTransaction {
	
	public func linkedCollection(forNodeID nodeID: String) -> String? {
		
		if let (collection, _) = linkedCollectionAndKey(forNodeID: nodeID) {
			return collection
		}
		
		return nil
	}
	
	public func linkedKey(forNodeID nodeID: String) -> String? {
		
		if let (_, key) = linkedCollectionAndKey(forNodeID: nodeID) {
			return key
		}
		
		return nil
	}
	
	public func linkedCollectionAndKey(forNodeID nodeID: String) -> (collection: String, key: String)? {
	
		var _key: NSString?
		var _collection: NSString?
		if self.__getLinkedKey(&_key, collection: &_collection, forNodeID: nodeID) {
		
			let key = _key! as String
			let collection = _collection as String? ?? ""
			
			return (collection, key)
		}
		
		return nil
	}
}
