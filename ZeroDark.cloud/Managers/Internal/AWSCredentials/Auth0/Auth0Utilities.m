#import "Auth0Utilities.h"

#import "Auth0API.h"
#import "AWSRegions.h"
#import "S3Request.h"
#import "ZDCConstants.h"

#import "NSError+Auth0API.h"


@implementation Auth0Utilities

/**
 * See header file for description.
 */
+ (NSString *)firstAvailableAuth0IDFromProfiles:(NSDictionary *)profiles
{
	__block NSString *result = nil;

	// Just get the first non-recovery connection.
	//
	// Note:
	//   Every profile has an internal "recovery" connection that's reserved
	//   for resetting login access to an account. (User still needs their private key to decrypt data.)
	//   Since this recovery connection isn't a real connection, we ignore it here.
	//
	[profiles enumerateKeysAndObjectsUsingBlock:^(NSString* auth0_userID, NSDictionary* profile, BOOL* stop) {

		if (![Auth0Utilities isRecoveryProfile:profile])
		{
			result = auth0_userID;
			*stop = YES;
		}
	}];

	return result;
}

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
+ (BOOL)isRecoveryIdentity:(A0UserIdentity *)identity
{
	BOOL result = [identity.connection isEqualToString:kAuth0DBConnection_Recovery];
	return result;
}

/**
 * See header file for description.
 */
+ (BOOL)isUserAuthIdentity:(A0UserIdentity *)identity
{
	BOOL result = [identity.connection isEqualToString:kAuth0DBConnection_UserAuth];
	return result;
}

/**
 * See header file for description.
 */
+ (BOOL)isRecoveryProfile:(NSDictionary *)profile
{
	NSString *connection = profile[@"connection"];
	if ([connection isKindOfClass:[NSString class]])
	{
		return ([connection isEqualToString:kAuth0DBConnection_Recovery]);
	}
	
	return NO;
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
+ (NSString *)correctDisplayNameForA0Strategy:(NSString *)strategy profile:(NSDictionary *)profile
{
	NSString *displayName = nil;

	displayName = profile[@"displayName"];
	if(!displayName)
	{
		displayName = [Auth0Utilities correctUserNameForA0Strategy: strategy
														   profile: profile];

	}
	if (!displayName)
	{
		displayName = profile[@"email"];
		if (displayName)
		{
			if ([Auth0Utilities is4thAEmail:displayName]) {
				displayName = [Auth0Utilities usernameFrom4thAEmail:displayName];
			}
			else if ([Auth0Utilities is4thARecoveryEmail:displayName]) {
				displayName = kAuth0DBConnection_Recovery;
			}
		}
	}

	if (!displayName)
		displayName = profile[@"nickname"];

	if (!displayName)
		displayName= @"<Unknown>";
	
	return displayName;
}

/**
 * See header file for description.
 */
+ (NSString *)correctPictureForAuth0ID:(NSString *)auth0ID
                           profileData:(NSDictionary *)profileData
                                region:(AWSRegion)aws_region
                                bucket:(NSString *)aws_bucket
{
	NSParameterAssert(auth0ID != nil);
	
	if ([self isRecoveryProfile:profileData]) {
		return nil;
	}
	
	NSArray *comps = [auth0ID componentsSeparatedByString:@"|"];
	if (comps.count != 2) {
		return nil;
	}
	
	NSString* provider 		= comps[0];
	NSString* providerID 	= comps[1];
	
	if ([provider isEqualToString:A0StrategyNameAuth0]
	  && (aws_bucket.length > 0)
	  && (aws_region != AWSRegion_Invalid))
	{
		NSString *avatarPath = [NSString stringWithFormat:@"avatar/%@", providerID];

		NSMutableURLRequest *request =
		  [S3Request getObject: avatarPath
		              inBucket: aws_bucket
		                region: aws_region
		      outUrlComponents: nil];
		
		return request.URL.absoluteString;
	}
	else
	{
		NSString *picture = profileData[@"picture"];
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
			for (NSURLQueryItem * item in components.queryItems)
			{
				if ([item.name isEqualToString:@"d"])
				{
					NSString* str = item.value;
					if ([str containsString:@"cdn.auth0.com/avatars"])
					{
						return nil;
					}
				}
			}
		}
		
		// Do fixes for various providers
		
		if ([provider isEqualToString:@"bitbucket"])
		{
			// bitbucket needs icon size fix
			return [picture stringByReplacingOccurrencesOfString:@"/32/" withString:@"/128/"];
		}
		else if ([provider isEqualToString:@"facebook"])
		{
			return [NSString stringWithFormat:@"https://graph.facebook.com/%@/picture", providerID];
		}
		else
		{
			return picture;
		}
	}
}

+(NSDictionary*)excludeRecoveryProfile:(NSDictionary*)profilesIn
{
    NSMutableDictionary* profiles = NSMutableDictionary.dictionary;
    
    [profilesIn enumerateKeysAndObjectsUsingBlock:^(NSString* auth0_userID, NSDictionary* profile, BOOL* stop) {
        
        BOOL isRecoveryId =  [Auth0Utilities isRecoveryProfile:profile];
        
        if(!isRecoveryId)
           [profiles setObject:profile forKey:auth0_userID];

    }];
    
    return profiles;
}

@end
