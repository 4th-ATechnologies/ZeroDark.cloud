#import "Auth0ProviderManager.h"
#import "ZeroDarkCloudPrivate.h"

#import "Auth0Utilities.h"
#import "S3Request.h"
#import "ZDCConstantsPrivate.h"
#import "ZDCDirectoryManager.h"
#import "ZDCLogging.h"

// Categories
#import "NSData+S4.h"
#import "NSDate+ZeroDark.h"
#import "NSURL+ZeroDark.h"
#import "NSURLResponse+ZeroDark.h"
#import "OSImage+ZeroDark.h"

// Libraries
#import <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#import <MobileCoreServices/MobileCoreServices.h>
#else
#import <Cocoa/Cocoa.h>
#endif

#import <YapDatabase/YapCache.h>
#import <ZipZap/ZZArchive.h>
#import <ZipZap/ZZArchiveEntry.h>
#import <ZipZap/ZZConstants.h>
#import <ZipZap/ZZError.h>

#import <stdatomic.h>


// Log Levels: off, error, warn, info, verbose
// Log Flags : trace
#if DEBUG
  static const int zdcLogLevel = ZDCLogLevelWarning;
#else
  static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)

#define PROVIDER_TABLE_UPDATE_MAX_INTERVAL (30 * 86400)


/* extern */ NSString *const Auth0ProviderManagerErrorDomain = @"Auth0ProviderManager";
/* extern */ NSString *const Auth0ProviderManagerDidUpdateNotification = @"Auth0ProviderManagerDidUpdateNotification";

NSString *const kAuth0ProviderInfo_Key_ID           = @"id";
NSString *const kAuth0ProviderInfo_Key_Type         = @"type";
NSString *const kAuth0ProviderInfo_Key_DisplayName  = @"displayName";

NSString *const kAuth0ProviderInfo_Key_SigninURL     = @"signin";
NSString *const kAuth0ProviderInfo_Key_64x64URL     = @"64x64";
NSString *const kAuth0ProviderInfo_Key_SigninEtag   = @"eTag_signin";
NSString *const kAuth0ProviderInfo_Key_64x64Etag    = @"eTag_64x64";


@implementation Auth0ProviderManager
{
	dispatch_queue_t cacheQueue;
    void *IsOnCacheQueueKey;

    NSDictionary*  _providersInfo;        // must be accessed from within cacheQueue
    NSArray*       _ordererdProviderKeys;
	NSArray  <NSString*> * _supportedProviderKeys;

    YapCache        *iconCache;          // must be accessed from within cacheQueue

@private
	__weak ZeroDarkCloud *zdc;
}

@dynamic providersInfo;
@dynamic ordererdProviderKeys;

static Auth0ProviderManager *sharedInstance = nil;

- (instancetype)init
{
	return nil; // To access this class use: ZeroDarkCloud.auth0ProviderManager
}

- (instancetype)initWithOwner:(ZeroDarkCloud *)inOwner
{
	if ((self = [super init]))
	{
		zdc = inOwner;

		cacheQueue     = dispatch_queue_create("Auth0ProviderManager.cacheQueue", DISPATCH_QUEUE_SERIAL);

		IsOnCacheQueueKey = &IsOnCacheQueueKey;
		dispatch_queue_set_specific(cacheQueue, IsOnCacheQueueKey, IsOnCacheQueueKey, NULL);

		NSUInteger iconCacheSize = 64;
		_supportedProviderKeys = nil;

		iconCache = [[YapCache alloc] initWithCountLimit:iconCacheSize];
		iconCache.allowedKeyClasses = [NSSet setWithObject:[NSString class]];
		iconCache.allowedObjectClasses = [NSSet setWithObject:[OSImage class]];

		NSError * error     = nil;

		NSURL *smiURL = [ZDCDirectoryManager smiCacheDirectoryURL];
		NSURL* smiJSONURL = [smiURL URLByAppendingPathComponent:@"socialmediaproviders.json"];

		if(![NSFileManager.defaultManager fileExistsAtPath:smiJSONURL.path])
		{
			[self decompressIconFileWithError:&error];

			if (error) {
				ZDCLogError(@"%@: Error decompressing icon files: %@", THIS_METHOD, error);
			}
		}

		if(!error)
		{

			NSDictionary* dict = nil;
			NSArray* keys = nil;

			[self makeProviderInfoFromURL:smiURL
							 providerDict:&dict
									 keys:&keys
									error:&error];
			if(!error)
			{
				_providersInfo = dict;
				_ordererdProviderKeys = keys;
				//               [iconCache removeAllObjects];
			}
		}
	}
	return self;
}



#if TARGET_OS_IPHONE
- (void)didReceiveMemoryWarning:(NSNotification *)notification
{
	dispatch_sync(cacheQueue, ^{
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		 
		[iconCache removeAllObjects];
		 
	#pragma clang diagnostic pop
	});
}
#endif

#pragma mark - accessors

- (BOOL)isUpdated
{
	__block BOOL hasKeys = NO;

	dispatch_sync(cacheQueue, ^{
	#pragma clang diagnostic push
	#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		
		hasKeys = _supportedProviderKeys != nil;
		
	#pragma clang diagnostic pop
	});
	
	return hasKeys;
}

-(NSArray*)ordererdProviderKeys
{
    __block NSArray* keys = nil;

    dispatch_sync(cacheQueue, ^{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-retain-self"
        keys = _ordererdProviderKeys;
#pragma clang diagnostic pop
    });

    return keys;
}

-(NSDictionary*)providersInfo
{
    __block NSDictionary* info = nil;

    dispatch_sync(cacheQueue, ^{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-retain-self"
        info = _providersInfo;
#pragma clang diagnostic pop
    });

    return info;
}



- (NSString *)keyPrefixForIconSignin:(NSString *)provider
{
	return [NSString stringWithFormat:@"signin:%@", provider];
}

- (NSString *)keyPrefixForIcon64x64:(NSString *)provider
{
	return [NSString stringWithFormat:@"64x64:%@", provider];
}


- (OSImage *)iconForProvider:(NSString *)provider type:(Auth0ProviderIconType)type
{
	__block OSImage *thumbnail = nil;

	NSString *cacheKey = nil;
	NSString *urlKey = nil;
	
	switch (type) {
		case Auth0ProviderIconType_64x64:
			cacheKey = [self keyPrefixForIcon64x64:provider];
			urlKey = kAuth0ProviderInfo_Key_64x64URL;
			break;

		case Auth0ProviderIconType_Signin:
			cacheKey = [self keyPrefixForIconSignin:provider];
			urlKey = kAuth0ProviderInfo_Key_SigninURL;
			break;

		default:
			ZDCLogError(@"%@: Invalid Auth0ProviderIconType requested: %ld", THIS_METHOD, (long)type);
			return nil;
	}

    dispatch_sync(cacheQueue, ^{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-retain-self"
        thumbnail = [iconCache objectForKey:cacheKey];
#pragma clang diagnostic pop
    });

	if (thumbnail == nil)
	{
		__block NSDictionary* dict = nil;
		dispatch_sync(cacheQueue, ^{
		#pragma clang diagnostic push
		#pragma clang diagnostic ignored "-Wimplicit-retain-self"
			
			dict = _providersInfo[provider];
			
		#pragma clang diagnostic pop
		});
		
		NSURL *url = dict ? dict[urlKey] : nil;
		NSData *data = url ? [NSData dataWithContentsOfURL:url] : nil;
		
		thumbnail = data ? [OSImage imageWithData:data] : nil;
		if (thumbnail)
		{
			dispatch_sync(cacheQueue, ^{
			#pragma clang diagnostic push
			#pragma clang diagnostic ignored "-Wimplicit-retain-self"
				
				[iconCache setObject:thumbnail forKey:cacheKey];
				
			#pragma clang diagnostic pop
			});
		}
	}

	return thumbnail;
}

- (NSString *)displayNameForProvider:(NSString *)provider
{
	NSString *displayName = nil;

	NSDictionary *providerInfo = _providersInfo[provider];
	if (providerInfo)
	{
		displayName = providerInfo[kAuth0ProviderInfo_Key_DisplayName];
	}

	if (displayName.length > 0) {
		return displayName;
	} else {
		return provider;
	}
}

#pragma mark - unpack and load cache

-(BOOL) decompressIconFileWithError:(NSError** _Nullable)errorOut
{
    NSError  *error = NULL;
	BOOL 	 success = NO;

    NSFileManager* fm = NSFileManager.defaultManager;

	NSURL *smiURL = [ZDCDirectoryManager smiCacheDirectoryURL];
	NSURL *outputUrl = [ZDCDirectoryManager generateTempURL];

    // Unzip the socialmediaicons from resource bundle
    NSURL *iconsZipURL = [[ZeroDarkCloud frameworkBundle] URLForResource:@"socialmediaicons" withExtension:@"zip"];

    [iconsZipURL decompressToDirectory:outputUrl error:&error];
	if (error) goto done;


    // copy SMI unziped files to cache folder
    {
        NSURL* tempSMIURL = [outputUrl URLByAppendingPathComponent:@"socialmediaicons"];
        NSArray * fileNames =  [fm contentsOfDirectoryAtPath:tempSMIURL.path error:&error];
		if (error) goto done;

        for(NSString* name in fileNames)
        {
            if([fm fileExistsAtPath:[smiURL URLByAppendingPathComponent:name].path])
                [fm removeItemAtPath:[smiURL URLByAppendingPathComponent:name].path error:nil];

            [fm moveItemAtURL: [tempSMIURL URLByAppendingPathComponent:name]
                            toURL:[smiURL URLByAppendingPathComponent:name]
                            error:&error];
        }
    }

done:

    if(errorOut)
        *errorOut = error;

	success = !error;
	return success;
}



#pragma mark - create Provider dictionary

- (void)fetchSupportedProviders:(void (^)(NSArray<NSString*> *_Nullable providerKeys,
                                          NSError *_Nullable error))completionBlock
{

	__block NSArray* supportedKeys =  nil;

	dispatch_sync(cacheQueue, ^{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-retain-self"
		supportedKeys =_supportedProviderKeys;
#pragma clang diagnostic pop
	});

	if(supportedKeys.count)
	{
		 completionBlock(supportedKeys, NULL);
	}
	else
	{
		[zdc.restManager fetchConfigWithCompletionQueue: dispatch_get_main_queue()
		                                completionBlock:^(NSDictionary * _Nullable config, NSError * _Nullable error)
		{
			if (error)
			{
				completionBlock(NULL, error);
				return;
			}

 			 NSMutableArray* keys = [NSMutableArray arrayWithArray: self.ordererdProviderKeys];
			 NSMutableArray* supportedKeys = NSMutableArray.array;
			 NSArray<NSDictionary *> *availableProviders = [config objectForKey:kSupportedConfigurations_Key_Providers];


			 // filter out any missing strategies
			 for(NSString* key in keys)
			 {
				 BOOL found = NO;

				 for(NSDictionary* providerInfo in availableProviders)
				 {
					 NSString* providerID = providerInfo[@"id"];

					 if([providerID isEqualToString:key])
					 {
						 found = YES;
						 break;
					 }
				 }
				 if(found)
					 [supportedKeys addObject:key];
			 }

			 if(supportedKeys.count)
			 {
				 dispatch_sync(self->cacheQueue, ^{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-retain-self"
					 _supportedProviderKeys = supportedKeys;
#pragma clang diagnostic pop
				 });
			 }

			 completionBlock(supportedKeys, NULL);

 		 }];
	}
}

-(BOOL) makeProviderInfoFromURL:(NSURL*)smiURL
                   providerDict:(NSDictionary**) providerDictOut
                           keys:(NSArray**) keysOut
                          error:(NSError** _Nullable)errorOut
{
    __block NSError* error = nil;
	BOOL  success = NO;

    NSArray* keys = nil;
    NSDictionary* providerDict = nil;

    NSURL* smpFileURL   = [smiURL URLByAppendingPathComponent:@"socialmediaproviders.json"];
    NSData* data =  nil;
    NSArray* json = nil;

    data = [NSData dataWithContentsOfURL: smpFileURL options:0 error:&error];
	if (error) goto done;

    json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
	if (error) goto done;


    providerDict = [self makeProviderDict:json
                                  smiBase:smiURL
                             updatedEtags:nil];

    keys = [self makeOrderedProviderArray:json providerDict:providerDict];


done:

    if(keysOut)
        *keysOut = keys;

    if(providerDictOut)
        *providerDictOut = providerDict;

    if(errorOut)
        *errorOut = error;

	success = !error;
	return success;
};


-(NSArray*) makeOrderedProviderArray:(NSArray <NSDictionary*> *)providerInfo
                        providerDict:(NSDictionary*)providerDict
{
    // Walk the providerInfo, extract the "id" key and see if there is a resultant key in the providerDict

    NSArray* preferedKeys = @[@"auth0" /*, A0StrategyNameGooglePlus, A0StrategyNameFacebook, A0StrategyNameLinkedin, A0StrategyNameTwitter */ ];

    NSMutableArray* array =  NSMutableArray.array;
    NSMutableArray* sortedProviders = NSMutableArray.array;

    for(NSDictionary* entry in providerInfo)
    {
        NSString* providerID    = entry[@"id"];
        if([providerDict objectForKey:providerID])
            [array addObject:providerID];
    }

    // put preferedKeys in front, remove from array
    for(NSString* key in preferedKeys)
    {
        [sortedProviders addObject:key];
        [array removeObject:key];
    }

    // sort alpha
    [array sortUsingComparator:^NSComparisonResult(NSDictionary *item1, NSDictionary *item2) {

        NSDictionary* dict1 = providerDict[item1];
        NSDictionary* dict2 = providerDict[item2];

        NSString* id1 = dict1[kAuth0ProviderInfo_Key_DisplayName];
        NSString* id2 = dict2[kAuth0ProviderInfo_Key_DisplayName];

        return [id1 localizedCaseInsensitiveCompare:id2];
    }];

    // take the rest
    [sortedProviders addObjectsFromArray:array];

    return sortedProviders;
}


-(NSDictionary*) makeProviderDict:(NSArray <NSDictionary*> *)providerInfo
                          smiBase:(NSURL*)smiBase
                     updatedEtags:(NSDictionary*)eTags
{

    NSMutableDictionary* newDict = NSMutableDictionary.dictionary;

    for(NSDictionary* entry in providerInfo)
    {
        NSString* providerID    = entry[kAuth0ProviderInfo_Key_ID];
        NSString* displayName   = entry[kAuth0ProviderInfo_Key_DisplayName];
        NSNumber* providerType  = entry[kAuth0ProviderInfo_Key_Type];
        NSString* eTag_signin   = entry[kAuth0ProviderInfo_Key_SigninEtag];
        NSString* eTag_64x64    = entry[kAuth0ProviderInfo_Key_64x64Etag];

        NSString* filename  = [providerID stringByAppendingPathExtension:@"png"];

        NSString* keySignin = [@"signin" stringByAppendingPathComponent:filename];
        NSString* key64x64 = [@"64x64" stringByAppendingPathComponent:filename];

        NSString* newTag_signin = [eTags objectForKey:keySignin];
        NSString* newTag_64x64 = [eTags objectForKey:key64x64];

        if(newTag_signin.length) eTag_signin= newTag_signin;
        if(newTag_64x64.length) eTag_signin= newTag_64x64;

        if(!eTag_signin.length) eTag_signin= @"";
        if(!eTag_64x64.length) eTag_64x64= @"";

        NSURL* urlSignin    = [smiBase URLByAppendingPathComponent:keySignin];
        NSURL* url64x64     = [smiBase URLByAppendingPathComponent:key64x64];

        newDict[providerID] = @{
                                kAuth0ProviderInfo_Key_ID:          providerID,
                                kAuth0ProviderInfo_Key_DisplayName: displayName,
                                kAuth0ProviderInfo_Key_Type :       providerType,
                                kAuth0ProviderInfo_Key_SigninURL:   urlSignin,
                                kAuth0ProviderInfo_Key_64x64URL:    url64x64,
                                kAuth0ProviderInfo_Key_SigninEtag:  eTag_signin,
                                kAuth0ProviderInfo_Key_64x64Etag:   eTag_64x64,
                                };
    }

    return newDict;
};

#pragma  mark - update ProviderCache From Web

#if !TARGET_EXTENSION
- (void)updateProviderCache:(BOOL)forceUpdate
{
	__weak typeof(self) weakSelf = self;
	
	
	NSDate* lastUpdate = zdc.internalPreferences.lastProviderTableUpdate;
	
	BOOL needsUpdate = !lastUpdate || forceUpdate;
	if(!needsUpdate)
	{
		NSTimeInterval elapsed = - [lastUpdate timeIntervalSinceNow];
		if(elapsed >  PROVIDER_TABLE_UPDATE_MAX_INTERVAL)
			needsUpdate = YES;
	}
	
	if(needsUpdate)
	{
		NSURL* webResourceURL = [NSURL URLWithString:@"https://s3-us-west-2.amazonaws.com/com.4th-a.resources"];
		NSURL *smiURL = [ZDCDirectoryManager smiCacheDirectoryURL];
		
		[self updateProviderCacheFromURL:webResourceURL
										  smiURL:smiURL
							  completionBlock:^(NSDictionary *dict, NSArray* keys, NSError *error)
		 {
			 
			 __strong typeof(self) strongSelf = weakSelf;
			 if(!strongSelf) return;
			 
			 if(!error)
			 {
				 dispatch_sync(strongSelf->cacheQueue, ^{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wimplicit-retain-self"
					 _providersInfo = dict;
					 _ordererdProviderKeys = keys;
					 [iconCache removeAllObjects];
#pragma clang diagnostic pop
				 });
				 
				 strongSelf->zdc.internalPreferences.lastProviderTableUpdate = NSDate.date;
				 
				 [[NSNotificationCenter defaultCenter] postNotificationName:Auth0ProviderManagerDidUpdateNotification
																					  object:self
																					userInfo: nil];
			 }
		 }];
	}
}
#endif


-(void) updateProviderCacheFromURL:(NSURL*)webURL
                            smiURL:(NSURL*)smiURL
                   completionBlock:(void (^)(NSDictionary* providerDict, NSArray* keys,  NSError*))completionBlock
{
    NSURL* smiWebURL    = [webURL URLByAppendingPathComponent:@"socialmediaicons"];

    void (^InvokeCompletionBlock)(NSDictionary*, NSArray*, NSError*) =
    ^(NSDictionary* providerDict, NSArray* keys, NSError *error)
    {
        if (completionBlock)
        {
            completionBlock(providerDict, keys, error);
        }
    };

	[zdc.restManager fetchConfigWithCompletionQueue: dispatch_get_main_queue()
	                                completionBlock:^(NSDictionary * _Nullable config, NSError * _Nullable error)
	{
		 if(!error)
		 {
			 NSArray<NSDictionary *> *availableProviders = [config objectForKey:kSupportedConfigurations_Key_Providers];

			[self makeProviderCacheWithInfo:availableProviders
								   smiWebURL:smiWebURL
									 smiBase:smiURL
							 completionBlock:^(NSDictionary *providerDict, NSArray* keys, NSError *error)
			  {
				  InvokeCompletionBlock(providerDict,keys,error);
			  }];;

		 }
		 else
		 {
          	InvokeCompletionBlock(nil,nil,error);
		 }

	 }];
}

-(void) makeProviderCacheWithInfo:(NSArray <NSDictionary*> *)providerInfo
                        smiWebURL:(NSURL*)smiWebURL
                          smiBase:(NSURL*)smiBase
                  completionBlock:(void (^)(NSDictionary* providerDict, NSArray* keys,  NSError*))completionBlock
{
    NSArray* missingFiles = nil;
    NSArray* removedKeys = nil;

    NSError* error = nil;

    void (^InvokeCompletionBlock)(NSDictionary*, NSArray*, NSError*) =
    ^(NSDictionary* providerDict, NSArray* keys, NSError *error)
    {
        if (completionBlock)
        {
            completionBlock(providerDict, keys, error);
        }
    };

    // Create an list of missing or outdated icons
    missingFiles = [self checkEtagsWithJSON:providerInfo
                                    baseURL:smiBase
                                      error:&error];
    if(error)
    {
        InvokeCompletionBlock(nil, nil, error);
        return;
    }

    removedKeys = [self removeFilesWithJSON:providerInfo
                                    baseURL:smiBase];
    if(removedKeys.count)
    {
        NSMutableArray* newInfo = NSMutableArray.array;
        for(NSDictionary* entry in providerInfo)
        {
            NSString* providerID    = entry[@"id"];

            if(![removedKeys containsObject:providerID])
                [newInfo addObject:entry];
        }
        providerInfo = newInfo;
    }

    if(missingFiles.count == 0)
    {
        NSDictionary* providerDict = [self makeProviderDict:providerInfo
                                                    smiBase:smiBase
                                               updatedEtags:nil
                                      ];

        NSArray* keys = [self makeOrderedProviderArray:providerInfo providerDict:providerDict];

        InvokeCompletionBlock(providerDict, keys,  nil);
        return;
    }

    [self downloadMediaIcons:missingFiles
                   smiWebURL:smiWebURL
                     smiBase:smiBase
             completionBlock:^(NSDictionary* eTags, NSError * error)
     {

         NSDictionary* providerDict = [self makeProviderDict:providerInfo
                                                     smiBase:smiBase
                                                updatedEtags:eTags];

         NSArray* keys = [self makeOrderedProviderArray:providerInfo providerDict:providerDict];

         InvokeCompletionBlock(providerDict, keys,  nil);
     }];

};


-(void) downloadMediaIcons:(NSArray*)missingFiles
                 smiWebURL:(NSURL*)smiWebURL
                   smiBase:(NSURL*)smiBase
           completionBlock:(void (^)(NSDictionary* eTags, NSError*))completionBlock
{
    __block atomic_uint pendingCount = 0;
    __block NSError * error  = nil;

    __block NSMutableDictionary* eTagDict = NSMutableDictionary.dictionary;

    void *IsOnDictQueueKey;

    dispatch_queue_t dictQueue = dispatch_queue_create("downloadMediaIcons.dictQueue", DISPATCH_QUEUE_SERIAL);
    IsOnDictQueueKey = &IsOnDictQueueKey;
    dispatch_queue_set_specific(dictQueue, IsOnDictQueueKey, IsOnDictQueueKey, NULL);

    dispatch_block_t downloadCompleteBlock = ^{

        if (atomic_fetch_sub(&pendingCount, 1)  != 1)
        {
            // Still waiting for all tasks to complete
            return;
        }
        //      dispatch_release(dictQueue);

        if(completionBlock) completionBlock(eTagDict, error);
    };

    if(missingFiles.count == 0)
    {
        if(completionBlock) completionBlock(nil, nil);
        return;
    }

    pendingCount = missingFiles.count;

	for (NSString *missingFile in missingFiles)
	{
		NSURL *sourceURL = [smiWebURL URLByAppendingPathComponent:missingFile];
		NSURL *destURL   = [smiBase URLByAppendingPathComponent:missingFile];
		
		[zdc.networkTools downloadFileFromURL: sourceURL
		                         andSaveToURL: destURL
		                                eTag: nil
		                     completionQueue: dispatch_get_main_queue()
		                     completionBlock:^(NSString *eTag, NSError *downloadError)
		{
			if (!downloadError && eTag)
			{
				dispatch_sync(dictQueue, ^{
				#pragma clang diagnostic push
				#pragma clang diagnostic ignored "-Wimplicit-retain-self"
					
					[eTagDict setObject:eTag forKey:missingFile];
					
				#pragma clang diagnostic pop
				});
			}
			
			if (downloadError && !error)
				error = downloadError;

			downloadCompleteBlock();
		}];
	}
}



-(NSArray*)removeFilesWithJSON:(NSArray*)json baseURL:(NSURL*)baseURL
{

    NSURL* urlSignin    = [baseURL URLByAppendingPathComponent:@"signin"];
    NSURL* url64x64     = [baseURL URLByAppendingPathComponent:@"64x64"];

    NSMutableArray* removed = NSMutableArray.array;

    for(NSDictionary* dict in json)
    {
        NSString* providerID    = dict[kAuth0ProviderInfo_Key_ID];
        BOOL     shouldDelete    = [dict[@"delete"] boolValue];

        NSString* filename  = [providerID stringByAppendingPathExtension:@"png"];

        if(shouldDelete)
        {
            [NSFileManager.defaultManager removeItemAtURL:[url64x64 URLByAppendingPathComponent:filename] error:NULL];
            [NSFileManager.defaultManager removeItemAtURL:[urlSignin URLByAppendingPathComponent:filename] error:NULL];

            [removed addObject: providerID];
        }
    }

    return removed;
}



-(NSArray*)checkEtagsWithJSON:(NSArray*)json baseURL:(NSURL*)baseURL error:(NSError**)errorOut
{
    NSError* error = nil;

    NSURL* urlSignin    = [baseURL URLByAppendingPathComponent:@"signin"];
    NSURL* url64x64     = [baseURL URLByAppendingPathComponent:@"64x64"];

    NSMutableArray* needsUpdate = NSMutableArray.array;

    for(NSDictionary* dict in json)
    {
        NSError* hashError = nil;

        NSString* providerID    = dict[kAuth0ProviderInfo_Key_ID];
        NSString* eTag_64x64    = dict[kAuth0ProviderInfo_Key_64x64Etag];
        NSString* eTag_signin   = dict[kAuth0ProviderInfo_Key_SigninEtag];
        BOOL     shouldDelete    = [dict[@"delete"] boolValue];

        NSString* filename  = [providerID stringByAppendingPathExtension:@"png"];

        if(shouldDelete) continue;

        // create a list of files that need to be updated.
        NSString* eTag = nil;

        eTag = [self calculateFileEtag: [url64x64 URLByAppendingPathComponent:filename]
                                 error:&hashError];

        if(hashError || ![eTag_64x64 isEqualToString:eTag])
        {
            [needsUpdate addObject:[ @"64x64" stringByAppendingPathComponent:filename]];
        }

        eTag = [self calculateFileEtag: [urlSignin URLByAppendingPathComponent:filename]
                                 error:&hashError];

        if(hashError || ![eTag_signin isEqualToString:eTag])
        {
            [needsUpdate addObject:[ @"signin" stringByAppendingPathComponent:filename]];
        }
    }

done:

    if(errorOut)
        *errorOut = error;

    return needsUpdate;
}

-(NSString*)calculateFileEtag:(NSURL*)url error:(NSError**)errorOut
{
    NSString* eTag = nil;
    NSData* data =  nil;
    NSError* error = nil;
    NSData* hashData = nil;

    data = [NSData dataWithContentsOfURL:url options:0 error:&error];
	if (error) goto done;

	hashData =  [data hashWithAlgorithm:kHASH_Algorithm_MD5 error:&error];
	if (error) goto done;

    eTag = hashData.hexString;

done:
    if(errorOut)
        *errorOut = error;

    return eTag;
}

-(NSUInteger) numberOfMatchingProviders:(NSDictionary*)profile provider:(NSString*)provider
{
	__block NSUInteger count = 0;

	[profile enumerateKeysAndObjectsUsingBlock:^(NSString* key, NSDictionary* profile,
																   BOOL * _Nonnull stop) {

		// skip recovery profile

		NSString* connection = profile[@"connection"];
		if([connection isEqualToString:provider])
			count++;

	}];
	
	return count;
}

@end
