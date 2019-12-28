#import "ActivityDescriptions.h"


/**
 * Shared utilities for Activity Monitor on macOS & iOS.
**/
@implementation ActivityDescriptions

+ (NSString *)descriptionForNetworkThroughput:(NSNumber *)number
{
	int64_t const KiB = 1024;
	int64_t const MiB = 1024 * KiB;
	int64_t const GiB = 1024 * MiB;
	int64_t const TiB = 1024 * GiB;
	
	int64_t bytesPerSecond = [number longLongValue];
	NSString *description = nil;
	
	if (bytesPerSecond < (KiB / 2))
	{
		description = [NSString stringWithFormat:@"%lld B/s", bytesPerSecond];
	}
	else if (bytesPerSecond < MiB)
	{
		double kilobytesPerSecond = (double)bytesPerSecond / (double)KiB;
		
		description = [NSString stringWithFormat:@"%.1f KiB/s", kilobytesPerSecond];
	}
	else if (bytesPerSecond < GiB)
	{
		double megabytesPerSecond = (double)bytesPerSecond / (double)MiB;
		
		description = [NSString stringWithFormat:@"%.1f MiB/s", megabytesPerSecond];
	}
	else if (bytesPerSecond < TiB)
	{
		double gigabytesPerSecond = (double)bytesPerSecond / (double)GiB;
		
		description = [NSString stringWithFormat:@"%.1f GiB/s", gigabytesPerSecond];
	}
	else
	{
		double terabytesPerSecond = (double)bytesPerSecond / (double)TiB;
		
		description = [NSString stringWithFormat:@"%.1f TiB/s", terabytesPerSecond];
	}
	
	return description;
}

+ (NSString *)descriptionForTimeRemaining:(NSNumber *)number
{
	NSTimeInterval remaining = [number doubleValue];
	NSString *description = nil;
	
	if (remaining < 60) // under a minute
	{
		int seconds = (int)remaining;
		
		description = [NSString stringWithFormat:@"0:%02d", seconds];
	}
	else if (remaining < (60 * 60)) // under an hour
	{
		int minutes = (int)(remaining / 60);
		int seconds = (int)remaining % 60;
		
		description = [NSString stringWithFormat:@"%d:%02d", minutes, seconds];
	}
	else // 1+ hours
	{
		int hours   = (int)(remaining / (60 * 60));
		int leftover = (int)remaining - (hours * 60 * 60);
		
		int minutes = (int)(leftover / 60);
		int seconds = (int)leftover % 60;
		
		description = [NSString stringWithFormat:@"%d:%02d:%02d", hours, minutes, seconds];
	}
	
	return description;
}

@end
