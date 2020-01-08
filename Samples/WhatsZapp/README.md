# WhatsZapp

A simple messaging app that demonstrates several features of the [ZeroDark.cloud](https://www.zerodark.cloud/) platform.



ZeroDark is unique in that it's a **zero-knowledge** system. As in, the messages you send/receive are encrypted end-to-end. So when Alice sends a message to Bob, only Alice & Bob are capable of reading the message. Nobody else. Not even the servers that handle storing and delivering the message.



## Getting Setup

Before you can build-and-run with Xcode, you'll need to install the dependencies using [CocoaPods](https://cocoapods.org/). Open your terminal, navigate to this directory, and then run the following command:

```
pod install
```



Within the code, nearly all ZeroDarkCloud integration is done within the ZDCManager.swift file.



## Overview

This is a sample app, written for the express purpose of teaching. You can think of it as a "chapter 1" exercise from a text book. It's not meant to demonstrate every possible feature — just the basics.



![Conversations](./Screenshots/Conversations.png)



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



#### Treesystem != Filesystem

A traditional filesystem has directories & files. This design forces all content to reside in the leaves. That is, if you think about a traditional filesystem as a tree, you can see that all files are leaves, and all non-leaves are directories.

In contrast, the ZeroDark.cloud treesystem acts as a generic tree, where each item in the tree is simply called a "node". A node can be whatever you want it to be - an object, a file, a container, etc. Additionally, **all nodes are allowed to have children**.



#### Treesystem = Hierarchial storage for your data

Look at the tree above, and think about the node (A). If this were a filesystem, then 'A' would have to be a directory. However, in a treesystem 'A' can be anything you want it to be. Perhaps 'A' is a Recipe object. And 'D', 'E' & 'F' are images of the recipe. Or perhaps 'A' is a Conversation object, and 'D', 'E', & 'F' are messages within the conversation. Or maybe 'A' is an Album, and 'D', 'E' & 'F' are songs in the album. You get the idea. 



So a treesystem allows you to store your data in the cloud in a hierarchial fashion. How you go about structuring the hierarchy is completely up to you, which means you can tailor it to meet the needs of your app.



More details about the treesystem can be found in the [docs](https://zerodarkcloud.readthedocs.io/en/latest/client/tree/).



## The WhatsZapp Treesystem

In order to store data in the ZeroDark cloud, all we have to do is come up with a treesystem design for our data. Every user gets their own treesystem, which comes with a "home" container, and some other special containers. Here's what it looks like:

```
       (alice's treesystem)
       /     /    \      \ 
      /     /      \      \
 (home) (prefs) (outbox) (inbox) 
```

(*These built-in containers are called "trunks".*)

The WhatsZapp treesystem only uses the 'home' & 'inbox' trunk, and is structured like this:

```
                (Alice's Treesystem)
                 /                 \
              (home)              (inbox)    
             /      \               /  \
     (convoBob)    (convoCarol)  (msg5)(msg6)
      /   |   \        |
(msg1)(msg2)(msg3)   (msg4)
                       |
                     (imgA)
```

To explain how everything works, let's start from the very beginning.



## Starting a conversation

Alice has just installed the app for the first time, and she doesn't have any content in her treesystem. She wants a send a message to Bob. Here's what she does. First, she creates a node for her conversation with Bob, and then she adds her outgoing message as a child node:

```
 (alice's treesystem)
       /    \
  (home)    (inbox)
    |
(convoBob)
    |
  (msg1)
```

When she uploads the message node, she instructs the server to copy the node into Bob's inbox:

```
 (alice's treesystem)           (bob's treesystem)
       /    \                      /         \
  (home)    (inbox)            (home)      (inbox)
    |                                         |
(convoBob)            ------------------>  (msg1)
    |                 | server-side-copy
  (msg1)---------------
```

Bob receives the message from Alice. The message then sits in his inbox until he reads it on one of this devices. Once the message has been read, he moves it into a conversation:

```
 (alice's treesystem)           (bob's treesystem)
       /    \                      /            \
  (home)    (inbox)            (home)        (inbox)
    |                             |
(convoBob)                  (convoAlice)
    |                             | 
  (msg1)                       (msg1)
```

If Bob responds to Alice, the reverse flow occurs:

```
 (alice's treesystem)           (bob's treesystem)
       /    \                      /            \
  (home)    (inbox)            (home)        (inbox)
    |          |                   |
(convoBob)  (msg2)<----      (convoAlice)
    |                 |          / \
  (msg1)              |------(msg2)(msg1)
```

&nbsp;

## Designing for the cloud

The treesystem design for this sample app is simply one of many designs that are possible. You might have an idea for a better design.



When you design your treesystem, what you're doing is optimizing for the cloud. For example, imagine we didn't bother with conversation nodes. Every single message that Alice receives (whether from Bob, Carol or whoever), just sits in her inbox. But now fast-forward 12 months. Alice has 100,000 messages sitting in her inbox. And she just bought a new phone. Then she logs into your app on this brand new phone...

Leaving all messages in the inbox container means the app has to download all 100,000 messages. Without doing so, we can't be sure who Alice has conversations with. Now contrast that with our optimized design above.

It's easy for our app to quickly see who Alice has conversations with. All we have to do is download the conversation nodes. (And any pending messages in her inbox.)

Further, we can optimize our app. Alice might have 250,000 messages with her spouse. But there's no need to download them all. We can download only the most recent messages within each conversation. (And download older conversations on demand, if she scrolls back that far.)



When you design the treesystem for your app, think about long-time users of your app. Imagine them upgrading their phone, and then logging into your app on their new phone. How can you exploit the treesystem to minimize the amount of information you must download? How can you make your app quickly restore its previous state?



## Code Structure

**• ZDCManager.swift**

This is where the majority of the sample code is. This class implements the ZeroDarkCloudDelegate protocol. Thus it:

- provides the data to be uploaded to the cloud
- reacts to callbacks from ZDC when it has discovered changes in the cloud



**• ConversationsViewController.swift**

This is the user interface that displays the TableView of all conversations.



**• MyMessagesViewController.swift**

This is the user interface that displays the CollectionView of messages within a conversation. We're using the open-source MessageKit, so there's a minimal amount of work we have to do here.



**• DBManager.swift**

Here we setup our database to index stuff for our user interface. In particular, we store 2 different kinds of objects:

- Conversation
- Message

So we setup indexes that:

- sort conversations based on most recent message
- sort messages within each conversation based on timestamp

(*This is really boilerplate stuff, not directly related to ZeroDarkCloud.*)



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
    
    // Create the treesystem path for our node.
    // (A treesystem path is just an array of strings.)
    let treesystemPath = ZDCTreesystemPath(pathComponents: ["foo", "bar"])
    
    do {
      // Tell the framework to create the node.
      // It will ask the ZeroDarkCloudDelegate for the node's
      // content later, when it's ready to upload the node.
      let node = try cloudTransaction.createNode(with: treesystemPath)
        
    } catch {
      print("Error creating node: \(error)") 
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



#### 1. Node Metadata

The metadata is everything needed by the treesystem to store a node, but excluding the actual content of the node. This includes information such as:

- what is the name of the node
- who is the parent of this node
- who was permission to read / write this node
- when was the node last modified in the cloud
- various sync information, such as eTag(s)
- various crypto information for encrypting & decrypting the content



#### 2. Node Data

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



## More Information

To find out more about ZeroDark.cloud:

- [Website](https://www.zerodark.cloud/)
- [Docs](https://zerodarkcloud.readthedocs.io/en/latest/) (high-level discussion of the framework, how it works, what it does, etc)
- [API Reference](https://apis.zerodark.cloud/index.html) (low-level code documentation for the framework)