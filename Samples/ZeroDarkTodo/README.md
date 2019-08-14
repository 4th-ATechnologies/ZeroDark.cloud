# ZeroDarkTodo

A simple Todo app that demonstrates several features of the [ZeroDark.cloud](https://www.zerodark.cloud/) platform.



## Getting Setup

Before you can build-and-run with Xcode, you'll need to install the dependencies using [CocoaPods](https://cocoapods.org/). Open your terminal, navigate to this directory, and then run the following command:

```
pod install
```



Within the code, nearly all ZeroDarkCloud integration is done within the ZDCManager.swift file.



## Overview

ZeroDarkTodo is a simple app, with only a few screens. First, we allow the user to create multiple Lists. Each list has a title, and simply acts as a container for a group of todo items.

![ScreenShot_Lists](https://github.com/4th-ATechnologies/ZeroDark.cloud/raw/master/Samples/ZeroDarkTodo/Images/ScreenShot_Lists.png)

Within each List, we allow the user to create any number of todo items, which we call Tasks:

![ScreenShot_Tasks](https://github.com/4th-ATechnologies/ZeroDark.cloud/raw/master/Samples/ZeroDarkTodo/Images/ScreenShot_Tasks1.png)

We also allow the user to give each Task a priority (low, normal, high). And we allow them to optionally attach a photo to a Task:

![ScreenShot_Tasks2](https://github.com/4th-ATechnologies/ZeroDark.cloud/raw/master/Samples/ZeroDarkTodo/Images/ScreenShot_Tasks2.png)

And finally, we allow the user to share a List with other users. That is, to collaborate on a List. So, for example, Alice could share a list with Bob. Any changes that either of them make (add, modify or delete a Task) will be visible to both users.

![ScreenShot_Sharing](https://github.com/4th-ATechnologies/ZeroDark.cloud/raw/master/Samples/ZeroDarkTodo/Images/ScreenShot_Sharing.png)

## The Basics

Cloud platforms come in all different shapes & sizes. Chances are you've used one before. And its certain that ZeroDark.cloud works differently. So let's start with a basic overview of how data is stored, structured & organized in the cloud.



ZeroDark.cloud provides every user with a [treesystem](https://zerodarkcloud.readthedocs.io/en/latest/client/tree/) in the cloud. Consider the following tree:

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



## The Todo Treesystem

In order to store data in the ZeroDark cloud, all we have to do is come up with a treesystem design for our data. For this sample app, the treesystem looks like this:

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

The process of creating & uploading a node to the cloud is quite easy. It goes something like this:

- **App**: "Hey ZDC, I would like to create a new node."

- **ZDC Framework**: "No problem, I can sync that for you. Just tell me where you'd like to put it in the treesystem."

- **App**: "Please put it here: ~/foo/bar"

- **ZDC Framework**: "OK, I've created a node for that path. I will query you later when I'm ready to upload the node's content."

- { Later }

- **ZDC Framework**: "OK, I'm ready to upload the content for the node with path '~/foo/bar'. Please give me the content. I will automatically encrypt the data for you, and then upload it to the cloud. Only those you granted permission will have access to the key required to decrypt the content."

- **App**: "Here you go: 001010100010111010100011111010…."



In code, it looks like this:

```swift
databaseConnection.asyncReadWrite {(transaction) in

  // Get a reference to the cloud of the correct localUser.
  // (The ZeroDarkCloud framework supports multiple localUser's.)
  if let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: self.localUserID) {
    
    // Create the treesystem path for our List,
    // which is just: /listID
    // (A treesystem path is basically just an array of strings.)
    let treesystemPath = ZDCTreesystemPath(pathComponents: [ list.uuid ])
     
    do {
      // Tell the framework to create the node.
      // It will ask the ZeroDarkCloudDelegate for the node's
      // content later, when it's ready to upload the node.
      let node = try cloudTransaction.createNode(with: treesystemPath)
        
    } catch {
      print("Error creating node for list: \(error)") 
    }
  }
}
```



And then you implement the [ZeroDarkCloudDelegate](https://apis.zerodark.cloud/Protocols/ZeroDarkCloudDelegate.html) protocol somewhere. And handle the request for the node's data:

```swift
/// ZeroDarkCloudDelegate function:
/// 
/// ZeroDark is asking us to supply the data for a node.
/// This is the data that will get uploaded to the cloud
/// (after ZeroDark encrypts it).
///
func data(for node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadTransaction) -> ZDCData {
  
  // If you want to store a serialized object in the cloud,
  // it might look something like this:
  let data = myObject.serializeAsJSON()
  return ZDCData(data: data)
  
  // If you want to store a file in the cloud,
  // it might look like this:
  let fileURL = self.imageURL()
  return ZDCData(cleartextFileURL: fileURL)
  
  // Or maybe you need to run an asynchronous task
  // in order to generate the data to be stored in the cloud.
  let promise = ZDCDataPromise()
  DispatchQueue.global().async {
    let data = someSlowTask()
    promise.fulfill(ZDCData(data: data))
	}
  return ZDCData(promise: promise)
}
```

And that's all there is to it !



The framework doesn't care how you structure your cloud data. You're free to use JSON, protocol buffers, some custom binary format... whatever you want.

Additionally, ZeroDark.cloud allows you to store nodes of any size. You can even store multi-gigabyte sized files. And the framework will automatically upload the large file using a multi-part process that can recover from network interruptions.



The framework aims at being unopinionated concerning how you implement your app. You don't have to subclass NSManagedObject, or any such silliness. The framework simply focuses on keeping the local treesystem in-sync with the cloud treesystem.

Further, the framework only downloads the treesystem skeleton. It allows you to decide what content to download, and when. That is, if we think about a treesystem, we can separate it into 2 parts:



###### 1. Node Metadata

The metadata is everything needed by the treesystem to store a node, but excluding the actual content of the node. This includes information such as:

- what is the name of the node
- who is the parent of this node
- who was permission to read / write this node
- when was the node last modified in the cloud
- various sync information, such as eTag(s)
- various crypto information for encrypting & decrypting the content



###### 2. Node Data

The data is the actual content of the node. In other words, the content that your app generates.



## Treesystem notifications

The framework automatically downloads node metadata, and creates a skeleton of the treesystem on the local device. The [ZeroDarkCloudDelegate](https://apis.zerodark.cloud/Protocols/ZeroDarkCloudDelegate.html) is then notified about changes to the treesystem that have been detected:

```swift
/// ZeroDarkCloudDelegate:

func didDiscoverNewNode(_ node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
  // add code here
}

func didDiscoverModifiedNode(_ node: ZDCNode, with change: ZDCNodeChange, at path: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
  // add code here
}

func didDiscoverMovedNode(_ node: ZDCNode, from oldPath: ZDCTreesystemPath, to newPath: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
  // add code here
}

func didDiscoverDeletedNode(_ node: ZDCNode, at path: ZDCTreesystemPath, timestamp: Date?, transaction: YapDatabaseReadWriteTransaction) {
  // add code here
}
```



## Downloading a node

Your app gets to decide which nodes are downloaded, and when. This allows you to make various optimizations for your app. For example, you might choose to only download recent content. Or download certain nodes only on demand.

And downloading is easy using the [DownloadManager](https://zerodarkcloud.readthedocs.io/en/latest/client/downloadManager/):

```Swift
let options = ZDCDownloadOptions()
options.cacheToDiskManager = true
options.canDownloadWhileInBackground = true

zdc.downloadManager?.downloadNodeData( node,
                              options: options,
                      completionQueue: DispatchQueue.global())
{(cloudDataInfo: ZDCCloudDataInfo?, cryptoFile: ZDCCryptoFile?, error: Error?) in

 // download complete
}
```



Of course, downloads can fail due to network problems (e.g. disconnected from WiFi). So the framework also has a way for you to mark a node as "needs download":

```swift
func didDiscoverNewNode(_ node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadWriteTransaction) {
  
  guard let cloudTransaction = zdc.cloudTransaction(transaction, forLocalUserID: node.localUserID) else {
    return
  }
  cloudTransaction.markNodeAsNeedsDownload(node.uuid, components: .all)
  
  downloadNode(node, at: path)
}

func didReconnectToInternet() {
  // When we reconnect to Internet, we can enumerate the list
  // of nodes that are marked as "needs download".
  downloadPendingNodes()
}
```





## Images & Thumbnails

ZeroDark.cloud is a [zero-knowledge](https://zerodarkcloud.readthedocs.io/en/latest/overview/encryption/) system. The server is not capable of reading the content generated by your app. This means the data stored in the cloud is an encrypted blob - the server cannot decrypt it, and doesn't even know if it's an image or not. 

So the framework allows you to optionally create thumbnails within the app, and have those thumbnails uploaded alongside your node's data. You can optionally create metadata too, such as information about a video (e.g. length, format, etc):

```swift
/// ZeroDarkCloudDelegate:

func thumbnail(for node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadTransaction) -> ZDCData? {
  // Add code here if you want to store a thumbnail for the node.
  // The thumbnail gets stored alongside the node's data,
  // and can be downloaded indepedently.
  return nil
}

func metadata(for node: ZDCNode, at path: ZDCTreesystemPath, transaction: YapDatabaseReadTransaction) -> ZDCData? {
  // Add code here if you want to store additional metadata for the node.
  // The metadata gets stored alongside the node's data,
  // and can be downloaded independently.
  return nil
}
```



And downloading the thumbnail or metadata for a node is easy:

```swift
let comps: ZDCNodeMetaComponents = [.metadata]
		
zdc.downloadManager!.downloadNodeMeta( node,
                           components: comps,
                              options: options,
                      completionQueue: DispatchQueue.global())
{(cloudDataInfo: ZDCCloudDataInfo?, metadata: Data?, thumbnail: Data?, error: Error?) in
  // data downloaded & decrypted for you
}
```



For thumbnails, the process can be even easier if you use the [ThumbnailManager](https://apis.zerodark.cloud/Classes/ZDCImageManager.html).



## Linking nodes to your own objects

It's often helpful to create mappings between nodes in the treesystem, and your own objects or files in the app. You can do this by tagging the node with various information. These tags are stored in the local database, but aren't synced to the cloud. They're just for the local device:

```swift
// Setting a tag
cloudTransaction.setTag(fileURL, forNodeID: node.uuid, withIdentifier: "url")

// Getting a tag
let fileURL = cloudTransaction.tag(forNodeID: node.uuid, withIdentifier: "url")
```



## More Information

To find out more about ZeroDark.cloud:

- [Website](https://www.zerodark.cloud/)
- [Docs](https://zerodarkcloud.readthedocs.io/en/latest/) (high-level discussion of the framework, how it works, what it does, etc)
- [API Reference](https://apis.zerodark.cloud/index.html) (low-level code documentation for the framework)