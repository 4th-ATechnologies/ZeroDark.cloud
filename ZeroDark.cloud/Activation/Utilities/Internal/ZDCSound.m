//
//  ZDCSoundManager.m
//  ZeroDarkCloud
//
//  Created by vinnie on 3/13/19.
//

#import "ZDCSound.h"
#import "ZeroDarkCloud.h"
#import <AudioToolbox/AudioServices.h>

@implementation ZDCSound

static SystemSoundID _beepSoundID;

+ (void)initialize
{
	static BOOL initialized = NO;
	if (!initialized)
	{
		initialized = YES;

		NSString *beepSoundPath = [[ZeroDarkCloud frameworkBundle] pathForResource:@"beep" ofType:@"m4a"];
		NSURL *beebSoundURL = [NSURL fileURLWithPath:beepSoundPath isDirectory:NO];

		AudioServicesCreateSystemSoundID((__bridge CFURLRef)beebSoundURL, &_beepSoundID);
 	}
}

+ (void)playBeepSound
{
	AudioServicesPlaySystemSound(_beepSoundID);
}


@end
