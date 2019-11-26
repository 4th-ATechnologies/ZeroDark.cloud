#import "Auth0Utilities.h"

#import "AWSRegions.h"
#import "S3Request.h"
#import "ZDCConstants.h"

#import "NSError+Auth0API.h"


@implementation Auth0Utilities

/**
 * See header file for description.
 */
+ (BOOL)isValid4thAUsername:(NSString *)username
{
	BOOL validChars = NO;
	BOOL validLength = NO;
	
	NSString *email = [self create4thAEmailForUsername:username];
	if (email)
	{
		NSString *regExPattern = @"[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\\.[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+)*@(?:[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?\\.)+[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?";
		
		validChars = [[NSPredicate predicateWithFormat:@"SELF MATCHES %@", regExPattern] evaluateWithObject:email];
		if (validChars)
		{
			username = [email componentsSeparatedByString:@"@"][0];
			
			validLength = (username.length > 2) && (username.length < 129);
		}
	}
	
	return validLength && validLength;
}

/**
 * See header file for description.
 */
+ (NSString *)create4thAEmailForUsername:(NSString *)username
{
	NSString *sanitizedUsername =
	[username stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	
	if (sanitizedUsername.length == 0) {
		return nil;
	}
	
	NSString *email = [NSString stringWithFormat:@"%@@%@", sanitizedUsername, kAuth04thAUserDomain];
	return email;
}

/**
 * See header file for description.
 */
+ (BOOL)isUserAuthIdentity:(ZDCUserIdentity *)identity
{
	BOOL result = [identity.connection isEqualToString:kAuth0DBConnection_UserAuth];
	return result;
}

/**
 * See header file for description.
 */
+ (BOOL)isUserAuthProfile:(NSDictionary *)profile
{
	NSString *connection = profile[@"connection"];
	if ([connection isKindOfClass:[NSString class]])
	{
		return ([connection isEqualToString:kAuth0DBConnection_UserAuth]);
	}
	
	return NO;
}

/**
 * See header file for description.
 */
+ (BOOL)is4thAEmail:(NSString *)email
{
	NSArray *components = [email componentsSeparatedByString:@"@"];
	
	return ((components.count > 1) && [components[1] isEqualToString:kAuth04thAUserDomain]);
}

/**
 * See header file for description.
 */
+ (BOOL)is4thARecoveryEmail:(NSString *)email
{
	NSArray *components = [email componentsSeparatedByString:@"@"];
	
	return ((components.count > 1) && [components[1] isEqualToString:kAuth04thARecoveryDomain]);
}

/**
 * Extracts the username component from an email.
 *
 * E.g.:
 * - email    : alice@users.4th-a.com
 * - username : alice
**/
+ (NSString *)usernameFrom4thAEmail:(NSString *)email
{
	NSString *username = nil;
	NSArray *components = [email componentsSeparatedByString:@"@"];
	
	if ((components.count > 1) && [components[1] isEqualToString:kAuth04thAUserDomain])
	{
		username = components[0];
	}
	
	return username;
}

/**
 * Extracts the username component from an email.
 *
 * E.g.:
 * - email    : alice@recovery.4th-a.com
 * - username : alice
 */
+ (nullable NSString *)usernameFrom4thARecoveryEmail:(NSString *)email
{
	NSString *username = nil;
	NSArray *components = [email componentsSeparatedByString:@"@"];
	
	if (components.count > 1 && [components[1] isEqualToString:kAuth04thARecoveryDomain])
	{
		username = components[0];
	}
	
	return username;
}

/**
 * Handles weird providers (like wordpress)
 *
 * The term 'strategy' comes from the constants in Auth0's Lock framework.
 * E.g. `A0StrategyNameWordpress`
 */
+ (NSString *)correctUserNameForA0Strategy:(NSString *)strategy profile:(NSDictionary *)profile
{
	NSString *result = nil;
	NSString *name = profile[@"name"];

	// process dictionary issues
	if ([name isKindOfClass:[NSNull class]]) {
		name = nil;
	}

	if ([strategy isEqualToString:A0StrategyNameWordpress])
	{
		// wordpress uses the term display_name
		
		NSString *display_name = profile[@"display_name"];
		if ([display_name isKindOfClass:[NSNull class]]) {
			display_name = nil;
		}

		if (!result && display_name.length) {
			result = display_name;
		}
	}
	else if ([strategy isEqualToString:A0StrategyNameEvernote])
	{
		// evernote has a username
		
		NSString *username = profile[@"username"];
		if ([username isKindOfClass:[NSNull class]]) {
			username = nil;
		}
		
		if (!result && username.length) {
			result = username;
		}
	}
	else if ([strategy isEqualToString:kAuth0DBConnection_UserAuth])
	{
		// Auth0 database connections use the term "username"
		
		NSString *display_name = profile[@"username"];
		if ([display_name isKindOfClass:[NSNull class]]) {
			display_name = nil;
		}

		if (!result && display_name.length) {
			result = display_name;
		}
	}
	else
	{
		result = name;
	}

	return result;
}

/**
 * See header file for description.
 */
+ (nullable NSURL *)pictureUrlForIdentity:(ZDCUserIdentity *)identity
                                   region:(AWSRegion)aws_region
                                   bucket:(NSString *)aws_bucket
{
	if (identity == nil) {
		return nil;
	}
	if (identity.isRecoveryAccount) {
		return nil;
	}
	
	NSString *provider_name   = identity.provider;
	NSString *provider_userID = identity.userID;
	
	if ([provider_name isEqualToString:A0StrategyNameAuth0])
	{
		if (aws_region == AWSRegion_Invalid || aws_bucket.length == 0)
		{
			return nil;
		}
		
		NSString *avatarPath = [NSString stringWithFormat:@"avatar/%@", provider_userID];

		NSMutableURLRequest *request =
		  [S3Request getObject: avatarPath
		              inBucket: aws_bucket
		                region: aws_region
		      outUrlComponents: nil];
		
		return request.URL;
	}
	else
	{
		NSString *picture = identity.profileData[@"picture"];
		if (![picture isKindOfClass:[NSString class]]) {
			return nil;
		}
		
		// Must be a valid URL
		NSURL *url = [NSURL URLWithString:picture];
		if (url == nil) {
			return nil;
		}
		
		// Filter out the default auth0 URL
		NSURLComponents *components = [[NSURLComponents alloc] initWithURL:url resolvingAgainstBaseURL:NO];
		if ([components.host containsString:@"gravatar.com"])
		{
			for (NSURLQueryItem* item in components.queryItems)
			{
				if ([item.name isEqualToString:@"d"])
				{
					NSString *str = item.value;
					if ([str containsString:@"cdn.auth0.com/avatars"])
					{
						return nil;
					}
				}
			}
		}
		
		// Do fixes for various providers
		
		if ([identity.provider isEqualToString:@"bitbucket"])
		{
			// bitbucket needs icon size fix
			picture = [picture stringByReplacingOccurrencesOfString:@"/32/" withString:@"/128/"];
			url = [NSURL URLWithString:picture];
		}
		else if ([identity.provider isEqualToString:@"facebook"])
		{
			picture = [NSString stringWithFormat:@"https://graph.facebook.com/%@/picture", provider_userID];
			url = [NSURL URLWithString:picture];
		}
		
		return url;
	}
}

@end
