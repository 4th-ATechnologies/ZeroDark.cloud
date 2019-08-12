/**
 * ZeroDark.cloud
 * 
 * Homepage      : https://www.zerodark.cloud
 * GitHub        : https://github.com/4th-ATechnologies/ZeroDark.cloud
 * Documentation : https://zerodarkcloud.readthedocs.io/en/latest/
 * API Reference : https://4th-atechnologies.github.io/ZeroDark.cloud/
 **/

#import "ZDCPasswordStrengthCalculator.h"

#import "ZDCLogging.h"
#import "ZeroDarkCloud.h"

#import "BBEntropyCenter.h"
#import "BBDictionaryMatcher.h"
#import "BBL33tMatcher.h"
#import "BBSpatialMatcher.h"
#import "BBRepeatMatcher.h"
#import "BBSequenceMatcher.h"
#import "BBDigitsMatcher.h"
#import "BBYearMatcher.h"
#import "BBEntropyCenter.h"
#import "BBPattern.h"

static const int DISPLAY_DIGITS = 3;

static const double SINGLE_GUESS = .010;
static const int ATTACKER_COUNT = 100;
static const double SECOND_PER_GUESS = SINGLE_GUESS / ATTACKER_COUNT;


// Log Levels: off, error, warn, info, verbose
// Log Flags : trace
#if DEBUG
  static const int zdcLogLevel = ZDCLogLevelWarning;
#else
  static const int zdcLogLevel = ZDCLogLevelWarning;
#endif
#pragma unused(zdcLogLevel)

@interface ZDCPasswordStrength ()

@property (nonatomic, assign, readwrite) double entropy;
@property (nonatomic, assign, readwrite) double crackTime;
@property (nonatomic, copy, readwrite) NSString *password;
@property (nonatomic, copy, readwrite) NSArray *matchSequence;
@property (nonatomic, copy, readwrite) NSString *crackTimeDisplay;

@end

@implementation ZDCPasswordStrength

+ (double)getNumberFromArray:(NSArray *)array atIndex:(NSInteger)index {
	if (index < 0 || index >= array.count) {
		return 0;
	}
	
	NSNumber *number = [array objectAtIndex:index];
	return number.doubleValue;
}

+ (void)setNumber:(double)number InArray:(NSMutableArray *)array atIndex:(int)index {
	if (index < 0 || index >= array.count) {
		return;
	}
	
	[array replaceObjectAtIndex:index withObject:[NSNumber numberWithDouble:number]];
}

+ (double)round:(double)number toDigits:(int)digits {
	return round(number * pow(10, digits)) / pow(10, digits);
}

- (void)scoreMinimumEntropyWithMatches:(NSArray *)matches {
	int bruteforceCardinality = self.bruteforceCardinality;
	double lgBruteforceCardinality = log2(bruteforceCardinality);
	NSMutableArray *minimumEntropyUpToK = [NSMutableArray arrayWithCapacity:self.password.length];
	NSMutableArray *backPointers = [NSMutableArray array];
	
	for (int i = 0; i < self.password.length; i++) {
		[minimumEntropyUpToK addObject:[NSNumber numberWithInt:0]];
	}
	
	for (int k = 0; k < self.password.length; k++) {
		double previousEntropy = [ZDCPasswordStrength getNumberFromArray:minimumEntropyUpToK atIndex:k - 1];
		[ZDCPasswordStrength setNumber:previousEntropy + lgBruteforceCardinality InArray:minimumEntropyUpToK atIndex:k];
		
		[backPointers addObject:[NSNull null]];
		
		for (BBPattern *match in matches) {
			if (match.end == k) {
				double entropyUpToBegin = [ZDCPasswordStrength getNumberFromArray:minimumEntropyUpToK atIndex:match.begin - 1];
				double candidateEntropy = [[BBEntropyCenter defaultCenter] entropyOf:match] + entropyUpToBegin;
				
				if (candidateEntropy < [ZDCPasswordStrength getNumberFromArray:minimumEntropyUpToK atIndex:k]) {
					[ZDCPasswordStrength setNumber:candidateEntropy InArray:minimumEntropyUpToK atIndex:k];
					[backPointers replaceObjectAtIndex:k withObject:match];
				}
			}
		}
	}
	
	NSMutableArray *matchSequence = [NSMutableArray array];
	NSInteger k = self.password.length - 1;
	while (k >= 0) {
		BBPattern *match = [backPointers objectAtIndex:k];
		if (match == (BBPattern *)[NSNull null]) {
			k -= 1;
		} else {
			[matchSequence addObject:match];
			k = match.begin - 1;
		}
	}
	
	NSEnumerator *reversedEnumerator = matchSequence.reverseObjectEnumerator;
	NSMutableArray *newSequence = [NSMutableArray array];
	BBPattern *match;
	k = 0;
	while ((match = reversedEnumerator.nextObject)) {
		if (match.begin - k > 0) {
			[newSequence addObject:[self bruteforceMatchFrom:k to:match.begin - 1]];
		}
		k = match.end + 1;
		[newSequence addObject:match];
	}
	if (k < self.password.length) {
		[newSequence addObject:[self bruteforceMatchFrom:k to:self.password.length - 1]];
	}
	matchSequence = newSequence;
	
	double minimumEntropy = self.password.length ? [ZDCPasswordStrength getNumberFromArray:minimumEntropyUpToK atIndex:self.password.length - 1] : 0;
	self.entropy = [ZDCPasswordStrength round:minimumEntropy toDigits:DISPLAY_DIGITS];
	self.crackTime = 0.5 * pow(2, minimumEntropy) * SECOND_PER_GUESS;
	self.matchSequence = matchSequence;
}

- (int)bruteforceCardinality {
	return [BBEntropyCenter bruteforceCardinalityOfString:self.password];
}

- (BBPattern *)bruteforceMatchFrom:(NSUInteger)begin to:(NSUInteger)end {
	BBPattern *match = [[BBPattern alloc] init];
	match.type = BBPatternTypeBruteforce;
	match.begin = begin;
	match.end = end;
	match.token = [self.password substringWithRange:NSMakeRange(begin, end - begin + 1)];
	match.entropy = log2(pow(self.bruteforceCardinality, end - begin + 1));
	match.userInfo = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:self.bruteforceCardinality] forKey:BBBruteforcePatternUserInfoKeyCardinality];
	return match;
}

//- (NSString *)crackTimeDisplay {
//	if (!_crackTimeDisplay) {
//		long long minute = 60, hour = minute * 60, day = hour * 24, month = day * 31, year = month * 12, century = year * 100;
//
//		if (self.crackTime < minute) {
//			_crackTimeDisplay = @"no time";
//		} else if (self.crackTime < hour) {
//			_crackTimeDisplay = [NSString stringWithFormat:@"%d minutes", (int)(self.crackTime / minute) + 1];
//		} else if (self.crackTime < day) {
//			_crackTimeDisplay = [NSString stringWithFormat:@"%d hours", (int)(self.crackTime / hour) + 1];
//		} else if (self.crackTime < month) {
//			_crackTimeDisplay = [NSString stringWithFormat:@"%d days", (int)(self.crackTime / day) + 1];
//		} else if (self.crackTime < year) {
//			_crackTimeDisplay = [NSString stringWithFormat:@"%d months", (int)(self.crackTime / month) + 1];
//		} else if (self.crackTime < century) {
//			_crackTimeDisplay = [NSString stringWithFormat:@"%d years", (int)(self.crackTime / year) + 1];
//		} else {
//			_crackTimeDisplay = @"centuries";
//		}
//	}
//	return _crackTimeDisplay;
//}

/*!
 0: very weak
 1: weak
 2: so-so
 3: good
 4: great
 */
- (NSUInteger)score {
	if (self.crackTime < pow(10, 2)) {
		return 0;
	} else if (self.crackTime < pow(10, 4)) {
		return 1;
	} else if (self.crackTime < pow(10, 6)) {
		return 2;
	} else if (self.crackTime < pow(10, 8)) {
		return 3;
	}
	return 4;
}

 

- (NSString *)scoreLabel {
	if (self.score == 0) return  NSLocalizedString(@"Very Weak", comment: @"Very Weak");
		else if (self.score == 1) return NSLocalizedString(@"Weak", comment: @"Weak");
		else if (self.score == 2) return NSLocalizedString(@"Fair", comment: @"Fair");
		else if (self.score == 3) return NSLocalizedString(@"Good", comment: @"Good");
		else if (self.score == 4) return NSLocalizedString(@"Strong", comment: @"Strong");
		else NSAssert(NO, @"Invalid score");
	return @"Unknown";
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation ZDCPasswordStrengthCalculator

static NSArray *dictionaryMatchers = nil;
static NSDictionary *adjacencyGraphs = nil;

+ (void)loadDictionaryMatchers
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		
		NSMutableArray *matchers = [NSMutableArray array];
		
		NSString *jsonPath = [[ZeroDarkCloud frameworkBundle] pathForResource:@"frequency_lists" ofType:@"json"];
		NSData *jsonData = [NSData dataWithContentsOfFile:jsonPath];
		NSDictionary *dicts = (NSDictionary *)[NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
		
		for (NSString *dictName in dicts)
		{
			NSArray *list = dicts[dictName];
			
			BBDictionaryMatcher *matcher = [[BBDictionaryMatcher alloc] initWithDictionaryName:dictName andList:list];
			if (matcher) {
				[matchers addObject:matcher];
			}
		}
		
		dictionaryMatchers = matchers;
	});
}

+ (void)loadAdjacencyGraphs
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		
		NSString *jsonPath = [[ZeroDarkCloud frameworkBundle] pathForResource:@"adjacency_graphs" ofType:@"json"];
		NSData *jsonData = [NSData dataWithContentsOfFile:jsonPath];
		adjacencyGraphs = (NSDictionary *)[NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil];
		
		[BBEntropyCenter initializeWithAdjacencyGraphs: adjacencyGraphs];
	});
}

+ (NSArray *)match:(NSString *)password
{
	NSMutableArray *result = [NSMutableArray array];
	
	for (BBDictionaryMatcher *matcher in dictionaryMatchers) {
		[result addObjectsFromArray:[matcher match:password]];
	}
	
	BBL33tMatcher *l33tMatcher = [[BBL33tMatcher alloc] initWithDictionaryMatchers:dictionaryMatchers];
	[result addObjectsFromArray:[l33tMatcher match:password]];
	
	BBSpatialMatcher *spatialMatcher = [[BBSpatialMatcher alloc] initWithAdjacencyGraphs:adjacencyGraphs];
	[result addObjectsFromArray:[spatialMatcher match:password]];
	
	BBRepeatMatcher *repeatMatcher = [[BBRepeatMatcher alloc] init];
	[result addObjectsFromArray:[repeatMatcher match:password]];
	
	BBSequenceMatcher *sequenceMatcher = [[BBSequenceMatcher alloc] init];
	[result addObjectsFromArray:[sequenceMatcher match:password]];
	
	BBDigitsMatcher *digitsMatcher = [[BBDigitsMatcher alloc] init];
	[result addObjectsFromArray:[digitsMatcher match:password]];
	
	BBYearMatcher *yearMatcher = [[BBYearMatcher alloc] init];
	[result addObjectsFromArray:[yearMatcher match:password]];
	
	return result;
}

+ (ZDCPasswordStrength*)strengthForPassword:(NSString*)password
{
	[self loadDictionaryMatchers];
	[self loadAdjacencyGraphs];
	
	ZDCPasswordStrength *pws = [[ZDCPasswordStrength alloc] init];
	pws.password = password;
	
	NSArray *matches = [self match:password];
	[pws scoreMinimumEntropyWithMatches:matches];
	
	return pws;
}

@end
