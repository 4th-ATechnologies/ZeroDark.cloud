//
//  test_MerkleTree.m
//  ZeroDarkCloudTesting
//
//  Created by Robbie Hanson on 12/18/19.
//  Copyright © 2019 4th-A Technologies. All rights reserved.
//

#import <XCTest/XCTest.h>

#import "ZDCMerkleTree.h"

@interface test_MerkleTree : XCTestCase
@end

@implementation test_MerkleTree

- (void)test
{
	NSURL *merkleFilesURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"Merkle Files" withExtension:nil];
	
	NSDirectoryEnumerator<NSURL *> *enumerator =
	  [[NSFileManager defaultManager] enumeratorAtURL: merkleFilesURL
	                       includingPropertiesForKeys: nil
	                                          options: NSDirectoryEnumerationSkipsSubdirectoryDescendants
	                                     errorHandler: nil];
	
	for (NSURL *fileURL in enumerator)
	{
		NSData *fileData = [NSData dataWithContentsOfURL:fileURL];
		NSDictionary *fileDict = [NSJSONSerialization JSONObjectWithData:fileData options:0 error:nil];
		
		XCTAssert(fileDict != nil, @"Error reading/parsing fileURL: %@", fileURL);
		
		NSError *error = nil;
		ZDCMerkleTree *merkleTree = [ZDCMerkleTree parseFile:fileDict error:&error];
		
		XCTAssert(merkleTree != nil, @"Error parsing fileDict: %@", error);
		
		BOOL success = [merkleTree hashAndVerify:&error];
		
		if (success)
		{
		//	NSLog(@"File(%@) => Root(%@)", [fileURL lastPathComponent], [merkleTree rootHash]);
		}
		else
		{
			XCTAssert(NO, @"Error verifying merkleTree file: %@: %@", [fileURL lastPathComponent], error);
		}
	}
}

@end
