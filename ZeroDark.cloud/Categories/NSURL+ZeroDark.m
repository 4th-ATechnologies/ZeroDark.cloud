//
//  NSURL+ZeroDark.m
//  ZeroDarkCloud
//
//  Created by vinnie on 3/6/19.
//

#import "NSURL+ZeroDark.h"

#import <ZipZap/ZZArchive.h>
#import <ZipZap/ZZArchiveEntry.h>
#import <ZipZap/ZZConstants.h>
#import <ZipZap/ZZError.h>


@implementation NSURL (ZeroDark)


// unzip support to pick up embeded file info

-(BOOL) decompressToDirectory:(NSURL*) outputUrl
						error:(NSError **)errorOut
{
	BOOL    result = NO;
	NSError  *error = NULL;

	// special case, ,rtfd is a directory, we need to zip it.
	NSFileManager *fm  = [NSFileManager defaultManager];

	[fm createDirectoryAtURL:outputUrl
 withIntermediateDirectories:YES
				  attributes:nil
					   error:nil];

	ZZArchive *archive = [ZZArchive archiveWithURL:self error:&error];
	if(error) goto done;

	for (ZZArchiveEntry* entry in archive.entries)
	{
		NSURL* targetPath = [outputUrl URLByAppendingPathComponent:entry.fileName];

		if (entry.fileMode & S_IFDIR)
		{
			// check if directory bit is set
			[fm createDirectoryAtURL:targetPath
		 withIntermediateDirectories:YES
						  attributes:nil
							   error:&error];
			if(error) goto done;
		}

		else
		{
			// Some archives don't have a separate entry for each directory and just
			// include the directory's name in the filename. Make sure that directory exists
			// before writing a file into it.
			[fm createDirectoryAtURL:[targetPath URLByDeletingLastPathComponent]
		 withIntermediateDirectories:YES
						  attributes:nil
							   error:&error];
			if(error) goto done;

			NSData* outData = [entry newDataWithError:&error];
			if(error) goto done;
			
			[ outData writeToURL:targetPath atomically:NO];
		}
	}

done:

	archive = NULL;

	if(errorOut) *errorOut = error;

	return result = !error;
}


@end
