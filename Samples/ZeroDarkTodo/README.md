# ZeroDarkTodo

A simple Todo app that demos many of the features of the ZeroDark.cloud platform.



## Getting Setup

Before you can build-and-run with Xcode, you'll need to install the dependencies using [CocoaPods](https://cocoapods.org/). Open your terminal, navigate to this directory, and then run the following command:

```
pod install
```



## The Basics

Cloud platforms come in all different shapes & sizes. Chances are you've used one before. And its certain that ZeroDark.cloud works differently. So let's start with a basic overview of how data is stored, structured & organized in the cloud.



ZeroDark.cloud provides every user with a treesystem in the cloud. Consider the following tree:

```
       (home)
       /    \
     (A)    (B)
    / | \    |
  (D)(E)(F) (G)
```



The term "treesystem" might be new, but the concept is simple. It's similar to a filesystem, but with one BIG difference:

###### Treesystem != Filesystem

A traditional filesystem has directories & files. This design forces all content to reside in the leaves. That is, if you think about a traditional filesystem as a tree, you can see that all files are leaves, and all non-leaves are directories.

In contrast, the ZeroDark.cloud treesystem acts as a generic tree, where each item in the tree is simply called a "node". A node can be whatever you want it to be - an object, a file, a container, etc. Additionally, **all nodes are allowed to have children**.

###### Treesystem = Hierarchial storage for your data

Look at the tree above, and think about the node (A). If this were a filesystem, then 'A' would have to be a directory. However, in a treesystem 'A' can be anything you want it to be. Perhaps 'A' is a Recipe object. And 'D', 'E' & 'F' are images of the recipe. Or perhaps 'A' is a Conversation object, and 'D', 'E', & 'F' are messages within the conversation. Or maybe 'A' is an Album, and 'D', 'E' & 'F' are songs in the album. You get the idea. 



So a treesystem allows you to store your data in the cloud in a hierarchial fashion. How you go about structuring the hierarchy is completely up to you, which means you can tailor it to meet the needs of your app.



## The Todo Tree

This simple Todo app has 3 different types of nodes:

###### Lists

The user is allowed to create multiple Todo lists. For example: "Groceries", "Weekend Chores", "Stuff to pickup at the hardware store"

###### Todo

Within each List, the user can create a bunch of Todo items. Each Todo item has a title, and a flag that denotes whether or not the item has been completed.

###### TodoImage

The user is also allowed to attach an image to each Todo item. (Just one, to keep this example simple.) For example, if the user is making a grocery list,  they may need to pickup a specific type of BBQ sauce from the store. So the user takes a picture of the bottle to ensure they pickup the right one.



We can structure our treesystem like so:

```
              (home)
             /      \
       (listA)       (listB)
      /   |   \         |
(todo1)(todo2)(todo3)  (todo4)
                        |
                       (todoImageA)
```

This will work out nicely for us. If we delete (todo4), then the server will also delete (todoImageA), which is exactly what we want. And similarly, if we delete (listB), the the server will delete (todo4) & (todoImageA), which is exactly what we want.



## Uploading a node

The process of creating & uploading a node to the cloud is quite easy. If we think about a treesystem, we can separate it into 2 parts

###### 1. Node Metadata

The metadata is everything needed by the treesystem to store a node, but excluding the actual content of the node. So, for example, if we look at (todo4) in the tree above, the metadata would include information such as:

- who is the parent of this node
- what is the name of the node
- who was permission to read / write this node
- when was the node last modified in the cloud
- various sync related information, such as eTag(s)
- various encryption information needed for encrypting the content

###### 2. Node Data

And the data is the actual content of the node. For example, a serialized version of a Todo object.



The process of uploading a new node goes something like this:

TodoApp: "Hey, I've got a new node for you."

ZDC Framework: "No problem, I can sync that for you. Just tell me where you'd like to put it in the treesystem."

TodoApp: "Please put it here: ~/abc123/def456"

ZDC Framework: "OK, I've created a ZDCNode for that path. I will query you later when I'm ready to upload the node's content."

{ Later }

ZDC Framework: "OK, I'm ready to upload the content for the node with path '~/abc123/def456'. Please give me the content. And, as always, I will automatically encrypt the data for you. Only those with permission will have access to the key required to decrypt the content."

TodoApp: "Here you go: 001010100010111010100011111010…."



Here's what this process looks like in Swift:

```Swift
// Create our new List item
let list = List(title: title)

databaseConnection.asyncReadWrite {(transaction) in
   
  // Store our list in the database
  transaction.setObject(list, forKey: list.uuid, inCollection: kZ2DCollection_List)
  
  // The ZeroDarkCloud framework supports multiple localUser's.
  // Get a reference to the cloud of the correct localUser.
  if let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: self.localUserID) {
      
    // Create the treesystem path for our List,
    // which is just: /listID
    let treesystemPath = ZDCTreesystemPath(pathComponents: [ list.uuid ])
     
    do {
      // Create the node
      let node = try cloudTransaction.createNode(with: treesystemPath)
      
      // Link the node to our List item.
      // This is optional (discussed below).
      try cloudTransaction.linkNodeID(node.uuid, toKey: list.uuid, inCollection: kZ2DCollection_List)
        
    } catch {
      print("Error creating node for list: \(error)") 
    }
  }
}
```



That's all you need to do in order to create the node. At this point the framework has queued an upload operation for the node. (The queued operations are stored safely in the database.) And when it's ready to push the node to the cloud, it will ask the ZeroDarkCloudDelegate to provide the data:



```swift
/// ZeroDarkCloudDelegate function:
/// 
/// ZeroDark is asking us to supply the serialized data for a node.
/// This is the data that will get uploaded to the cloud
/// (after ZeroDark encrypts it).
///
func data(for node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadTransaction) -> ZDCData {
  
  let ext = zdc.cloudTransaction(transaction, forLocalUserID: node.localUserID)
  
  // Since we linked our List to the node,
  // we can just ask for the linked information.
  // (There are many ways to accomplish this.
  //  Linking is just one technique you can use.)
  if let (collection, key) = ext?.linkedCollectionAndKey(forNodeID: node.uuid) {
    
    // Is this a List item ?
    if collection == kZ2DCollection_List {
		
      let listID = key
      if let list = transaction.object(forKey: listID, inCollection: collection) as? List {
        
        do {
          // Serialize the List however you like
          let data = try list.cloudEncode()
          return ZDCData.init(data: data)
        } catch {
				  print("Error in list.cloudEncode(): \(error)")
				}
      }
    }
  }
  
  return nil
}
```



That's really all there is to it. The ZeroDark.cloud framework will handle nearly everything else for you including:

- Encrypting the data
- Uploading the node to the server (using background uploads on iOS)
- Managing & updating sync state



## Optional linking

If you store your objects in the same database that ZeroDark uses, then you can optionally link your objects to their corresponding ZDCNode's. This isn't required, but you may find it useful.

When working with the framework, you'll often need to map between your objects and ZDCNode's. Sometimes you'll have your own object, and you need to fetch the corresponding ZDCNode. And sometimes the framework will give you a ZDCNode, and you'll need to map back to your own object. There are dozens of ways to accomplish this. Linking is just one of them.



Food for thought as you think about this:

- Every ZDCNode has a uuid (referrred to as the nodeID). And given the nodeID, you can easily fetch the corresponding node via: `transaction.object(forKey: nodeID, inCollection: kZDCCollection_Nodes)`
- Every ZDCNode has a unique treesystem path. So if you have the path you can easily fetch the corresponding node via: `cloudTransaction.node(with: path)`



## Downloading a node

Recall that every node has (conceptually) 2 different components:

- **metadata**: Such as the filename, permissions, lastModified date, etc
- **data**: The actual content (generated by your app)

The ZeroDark framework automatically fetches the metadata for all nodes in the treesystem. But NOT the data. This way your app always knows the current state of the cloud. However your app is in complete control over what data gets downloaded, and when its downloaded. This allows you to optimize. For example, you may choose to download certain information on demand. Or perhaps you download thumbnail versions of images, and only download the full version if requested.



The ZeroDarkCloudDelegate has various functions that will get invoked as the framework discovers changes in the cloud. Let's take a look at an example:

```swift
/// ZerkDarkCloudDelegate function:
///
/// ZeroDark has just discovered a new node in the cloud.
/// It's notifying us so that we can react appropriately.
///
func didDiscoverNewNode(_ node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
  
  let shouldDownload = /* app specific logic goes here */
  if !shouldDownload {
    return
  }
  
  let options = ZDCDownloadOptions()
  options.cacheToDiskManager = false
  options.canDownloadWhileInBackground = true
  
  let queue = DispatchQueue.global()
  
  let downloadTicket =
    zdc.downloadManager!.downloadNodeData(node,
                                  options: options,
                          completionQueue: queue)
  { (cloudDataInfo: ZDCCloudDataInfo?, cryptoFile: ZDCCryptoFile?, error: Error?) in
   
    if let cryptoFile = cryptoFile {
      
      do {
        let data = try ZDCFileConversion.decryptCryptoFile(intoMemory: cryptoFile)
        
        // Process it
        self.processDownloadedList(data, forNodeID: nodeID)
      }
    }
  }
}
```



## Storing Images

The sample app allows users to optionally attach a single image to each Task. We already know where we want to store these images within the treesystem:

```
              (home)
             /      \
       (listA)       (listB)
      /   |   \         |
(todo1)(todo2)(todo3)  (todo4)
                        |
                       (todoImageA)
```



But where do we store them within our app ?

The ZeroDark.cloud framework support nodes of any size. Everything from empty nodes to multi-gigabyte size nodes. Which is handy because most apps have a combination of both small records (serialized objects), as well as larger files such as images or movies.

For objects, such as a List or Task, we want to store those in the database. But for images, we'd prefer to store them on disk. (They don't really need to be in the database. And most database systems recommend storing such large blobs on disk anyways.)

So you could store the image to disk yourself. Or you can use the ZDCDiskManager, which comes with several nice features:

- Every file you store in the DiskManager is linked to a ZDCNode. When the corresponding ZDCNode is deleted, the DiskManager will automatically delete the corresponding file(s) from disk.
- The DiskManager supports storing files in 2 different modes: Temporary-Cache-Mode or Persistent-Mode
- Files stored in Temporary-Cache-Mode are part of a "storage pool". The maximum size of this storage pool is configurable. And the DiskManager handles deleting files as needed when the max size is exceeded (according to lastAccessed file times). These files are also eligible for garbage collection by the OS due to low-disk-space pressure. Futher, you can set (optional) expiration times for these files. And they will get automatically deleted by the DiskManager after their time-limit expires. All of which ensures your disk usage remains controlled, and contributes to making your app a "good citizen" in the eyes of users and the OS.
- Files stored in Persistent-Mode are not part of the "storage pool", and are only deleted if you manually delete them. (Or if the corresponding node is deleted from the database.)



So storing our image is a rather simple process. We need to:

- Create the node (so zdc can upload it)
- And then store the image using the DiskManager



```swift
public func setImage(_ image: UIImage, forTaskID taskID: String, localUserID: String) {
	
  guard
    let imageData = image.dataWithJPEG()
  else {
    print("Unable to convert image to JPEG !")
    return
  }
  
  // Create our node.
  let imageNode = ZDCNode(localUserID: localUserID)
  
  DispatchQueue.global().async { // Perform disk IO off the main thread

    // Store our image to disk using the DiskManager
    do {
      let diskImport = ZDCDiskImport(cleartextData: imageData)
      diskImport.storePersistently = true // until post-upload
      
      try zdc.diskManager?.importNodeData(diskImport, for: imageNode)
    } catch {
      print("Error storing image in DiskManager: \(error)")
      return
    }
    
    databaseConnection.asyncReadWrite {(transaction) in
      
      guard
        let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: localUserID),
        let taskNode = cloudTransaction.linkedNode(forKey: taskID, inCollection: kZ2DCollection_Task)
      else {
        return
      }
			
      // Update our imageNode.
      // Path is: /{path to task}/img
      imageNode.parentID = taskNode.uuid
      imageNode.name = "img"

      do {
        try cloudTransaction.createNode(imageNode)
      }
      catch {
        print("Error creating imageNode: \(error)")
      }
    }
  }
}
```



## Uploading Images

