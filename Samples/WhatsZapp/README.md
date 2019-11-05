# WhatsZapp

A simple messaging app that demonstrates several features of the [ZeroDark.cloud](https://www.zerodark.cloud/) platform.



ZeroDark is unique in that it's a **zero-knowledge** system. As in, the messages you send/receive in WhatsZapp are encrypted end-to-end. So when Alice sends a message to Bob, only Alice & Bob are capable of reading the message. Nobody else. Not even the servers that handle storing and delivering the message.



## Getting Setup

Before you can build-and-run with Xcode, you'll need to install the dependencies using [CocoaPods](https://cocoapods.org/). Open your terminal, navigate to this directory, and then run the following command:

```
pod install
```



Within the code, nearly all ZeroDarkCloud integration is done within the ZDCManager.swift file.



## Overview

This is a sample app, written for the express purpose of teaching. You can think of it as a chapter 1 exercise from a text book. It's not meant to demonstrate every possible feature that's possible.



Insert screenshots here...



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



More details about the treesystem can be found in the [docs](https://zerodarkcloud.readthedocs.io/en/latest/client/tree/).



## The WhatsZapp Treesystem

In order to store data in the ZeroDark cloud, all we have to do is come up with a treesystem design for our data. Every user gets their own treesystem, which comes with a "home" container, and some other special containers. Here's what it looks like:

```
       (Alice's Treesystem)
       /     /    \      \ 
      /     /      \      \
 (home) (prefs) (outbox) (inbox) 
```

The WhatsZapp treesystem only uses the 'home' & 'inbox' containers, and is structured like this:

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

Bob receives the message from Alice, and then moves it into a new conversation node for her:

```
 (alice's treesystem)           (bob's treesystem)
       /    \                      /            \
  (home)    (inbox)            (home)        (inbox)
    |                             |
(convoBob)                  (convoAlice)
    |                             | 
  (msg1)                       (msg1)
```

Now `msg1` contains a reference to Alice's `convoBob` node. So when Bob replies to Alice, he can have the message delivered directly into the proper location:

```
 (alice's treesystem)           (bob's treesystem)
       /    \                      /            \
  (home)    (inbox)            (home)        (inbox)
    |                             |
(convoBob)                  (convoAlice)
   /  \       server-side-copy   / \
(msg1)(msg2) <---------------(msg2)(msg1)
```

This time, `msg2` contains a reference to Bob's `convoAlice` node. So at this point, both parties can continue sending messages back-and-forth without utilizing the `inbox` container.



## Designing for the cloud

When you design your treesystem, what you're doing is optimizing for the cloud. For example, imagine we didn't bother with conversation nodes. Every single message that Alice receives, whether it's from Bob, Carol or whoever, just sits in her inbox. But now fast-forward 12 months. Alice has 100,000 messages sitting in her inbox. And she just bought a new phone. Then she logs into your app on this brand new phone...

Leaving all messages in the inbox container means the app has to download all 100,000 messages. Without doing so, we can't be sure who Alice has conversations with. Now contrast that the design above.

It's easy for our app to quickly see who Alice has conversations with. All we have to do is download the conversation nodes. (And any pending messages in her inbox.)

Further, we can optimize our app. Alice might have 250,000 messages with her spouse. But there's no need to download them all. We can download only the most recent messages within each conversation.



When you design the treesystem for your app, think about long-time users of your app. Imagine them upgrading their phone, and then logging into your app on their new phone. How can you exploit the treesystem to minimize the amount of information you must download? How can you make your app quickly restore its previous state?



## Permissions

The treesystem supports a diverse set of permissions:

- read
- write
- share
- leafs-only
- users-only
- write-once
- burn



These are documented in more detail [here](https://zerodarkcloud.readthedocs.io/en/latest/client/tree/).



So how does Alice give Bob permission to write into `convoBob`? She gives Bob **write-once** permission:

> Users with the write-once permission are allowed to create child nodes. However, the nodes are considered "write once", in that the user can create them, but doesn't have permission to modify them afterwards.

So Bob can write/copy messages into Alice's `convoBob` node, but he can't modify or delete those messages later. (If we wanted to allow Bob to delete those messages later, we'd give him **burn** permission.)

Further, Bob cannot see the messages in Alice's treesystem. That is, he can't get a list of the messages in the `convoBob` node.



## Todo

- Conflict resolution for conversations
- 