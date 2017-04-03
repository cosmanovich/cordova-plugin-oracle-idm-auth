/**
 * Copyright (c) 2016, Oracle and/or its affiliates.
 * The Universal Permissive License (UPL), Version 1.0
 */
#import "IdmAuthentication.h"
#import "AuthViewController.h"
#import "IDMMobileSDKv2Library.h"

NS_ASSUME_NONNULL_BEGIN

#define NO_AUTH_CONTEXT_ERR_CODE @"P1010"
#define UNSUPPORTED_CHALLENGE_ERR_CODE @"P1003"
#define UNTRUSTED_SERVER_ERR_CODE @"P1002"
#define INVALID_REDIRECT_ERR_CODE @"P1001"
#define SESSION_TIMEOUT @"SESSION_TIMEOUT"
#define IDLE_TIMEOUT @"IDLE_TIMEOUT"
#define OK @"OK"
#define TIMEOUT_TYPE_KEY @"TimeoutType"
#define TIME_LEFT_TO_TIMEOUT_KEY @"TimeLeftToTimeout"
#define AUTH_VIEW @"AuthView"
#define AUTH_WEB_VIEW @"AuthWebView"


#ifdef DEBUG
#  define IdmLog(...) NSLog(__VA_ARGS__)
#else
#  define IdmLog(...)
#endif

@interface IdmAuthentication()

/**
 * Authentication properties used for creating the OMMSS instance.
 */
@property (nonatomic, copy) NSDictionary<NSString *, NSObject *> *properties;

/**
 * OMMSS instance.
 */
@property (nonatomic, strong, nullable) OMMobileSecurityService *ommss;

/**
 * Callback details for returning the result for login or logout to javascript layer.
 */
@property (nonatomic, strong, nullable) CDVCommandDelegateImpl  *loginLogoutCommandDelegate;
@property (nonatomic, copy, nullable) NSString                  *loginLogoutCallbackId;

/**
 * Callback details for returning the result for timeout to javascript layer.
 */
@property (nonatomic, strong, nullable) CDVCommandDelegateImpl  *timeoutCommandDelegate;
@property (nonatomic, copy, nullable) NSString                  *timeoutCallbackId;

/**
 * Base view controller used for launching the webview view controller
 * for webview based authentications.
 */
@property (nonatomic, weak, nullable) UIViewController          *baseViewController;

/**
 * Webview view controller used for webview based authentications.
 */
@property (nonatomic, weak, nullable) AuthViewController        *authViewController;

/**
 * The login or logout challenge object.
 */
@property (nonatomic, weak, nullable) OMAuthenticationChallenge *challenge;

/**
 * If the current challenge being processed is a webview based challenge or not.
 */
@property (atomic, assign) BOOL                                 isWebViewLaunched;

/**
 * Boolean to indicate if app wants to use WkWebView.
 */
@property (nonatomic, assign) BOOL                              isWkWebViewEnabled;

@end

@implementation IdmAuthentication

/**
 * Create a new instance of IdmAuthentication using the specified configuration properties.
 * Throws and error if the specified configuration properties are not valid
 * or if there was an error while creating the OMMSS instance
 *
 * @param properties: the configuration properties to use
 * @param baseVc: the base view controller.
 */
-(nullable instancetype) initWithProperties:(NSDictionary<NSString *, NSObject *> *) properties
                         baseViewController:(nonnull UIViewController *)baseVc
                         error:(NSError **) error {
  if (self = [super init]) {
    self.properties = properties;
    self.baseViewController = baseVc;

    NSMutableDictionary* authProps = [NSMutableDictionary dictionaryWithDictionary:properties];
    NSSet* scopeSet = [self extractScopeSet:properties];

    if (scopeSet) {
      authProps[OM_PROP_OAUTH_SCOPE] = scopeSet;
    }

    self.isWkWebViewEnabled = (BOOL) authProps[OM_PROP_ENABLE_WKWEBVIEW];
    self.ommss = [[OMMobileSecurityService alloc] initWithProperties:authProps delegate:self error:error];
    self.isWebViewLaunched = NO;
  }
  return self;
}

/**
 * Starts the login process on the OMMSS instance.
 * If an error occurs, the error code is communicated back to the javascript layer.
 *
 * @param commandDelegate: callback
 * @param callbackId: callback id
 */
-(void) startLogin:(CDVCommandDelegateImpl*) commandDelegate
        withCallbackId: (NSString*) callbackId {
  IdmLog(@"startLogin invoked");
  self.loginLogoutCommandDelegate = commandDelegate;
  self.loginLogoutCallbackId = callbackId;
  NSError* error = [self.ommss startAuthenticationProcess:nil];

  if (error != nil) {
    IdmLog(@"startLogin error invoking ommss startAuthenticationProcess %@", error);
    [self throwErrorCodeToLoginCallback:[@(error.code) stringValue]];
  }

  IdmLog(@"startLogin completed");
}

/**
 * Finish the login process on the OMMSS instance. This method is invoked after
 * collecting required credentials from the user at the javascript layer.
 * If an error occurs, the error code is communicated back to the javascript layer.
 *
 * @param commandDelegate: callback
 * @param callbackId: callback id
 * @param challengeFields: The filled up challenge fields map.
 */
-(void) finishLogin:(CDVCommandDelegateImpl *)commandDelegate
        withCallbackId:(NSString *)callbackId
        challengeResult: (NSDictionary*) challengeFields {
  IdmLog(@"Finish login received %@", challengeFields);
  self.loginLogoutCommandDelegate = commandDelegate;
  self.loginLogoutCallbackId = callbackId;
  self.challenge.authChallengeHandler(challengeFields, OMProceed);
  IdmLog(@"Finish login completed.");
}

/**
 * Query OMMSS instance to find out if the user is currently authenticated or not.
 * If an error occurs, the error code is communicated back to the javascript layer.
 *
 * @param commandDelegate: callback
 * @param callbackId: callback id
 * @param properties: extra properties if any
 */
- (void) isAuthenticated: (CDVCommandDelegateImpl*) commandDelegate
         withCallbackId: (NSString*) callbackId
         withProperties: (NSDictionary*) properties {
  IdmLog(@"isAuthenticated invoked");
  if ([properties isKindOfClass:[NSNull class]]) {
    properties = nil;
  }

  OMAuthenticationContext* context = [self.ommss authenticationContext];
  BOOL isValid = NO;
  BOOL refreshExpiredTokens = NO;
  NSSet* scopeSet = nil;

  if (properties) {
    scopeSet = [self extractScopeSet:properties];
    refreshExpiredTokens = [(NSNumber*) properties[@"refreshExpiredTokens"] boolValue];
  }

  if (context != nil) {
    if (scopeSet) {
      isValid = [[self.ommss authenticationContext] isValidForScopes:scopeSet refreshExpiredToken:refreshExpiredTokens];
    } else {
      isValid = [[self.ommss authenticationContext] isValid];
    }
  }

  CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary: @{@"isAuthenticated" : [NSNumber numberWithBool:isValid]}];
  [commandDelegate sendPluginResult:result callbackId:callbackId];
  IdmLog(@"isAuthenticated completed: %d", isValid);
}

/**
 * Query OMMSS instance for authentication headers (if any).
 * If an error occurs, the error code is communicated back to the javascript layer.
 *
 * @param commandDelegate: callback
 * @param callbackId: callback id
 * @param fedAuthSecuredUrl: The secured URL for which cookies and headers have to be retrieved. Applicable only for Federated Auth usecase.
 */
- (void) getHeaders: (CDVCommandDelegateImpl*) commandDelegate
         withCallbackId: (NSString*) callbackId
         withFedAuthSecuredUrl: (NSString*) fedAuthSecuredUrl {
  IdmLog(@"getHeaders invoked");
  OMAuthenticationContext* context = [self.ommss authenticationContext];

  if (context == nil) {
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:NO_AUTH_CONTEXT_ERR_CODE];
    [commandDelegate sendPluginResult:result callbackId:callbackId];
    return;
  }

  if ([fedAuthSecuredUrl isKindOfClass:[NSNull class]]) {
    fedAuthSecuredUrl = nil;
  }

  NSString* authType = (NSString*) self.properties[OM_PROP_AUTHSERVER_TYPE];
  NSMutableDictionary* returnHeaders;
  BOOL isMcsSamlFlow = [OM_PROP_AUTHSERVER_FED_AUTH isEqualToString:authType]
  && [(NSNumber*) self.properties[OM_PROP_PARSE_TOKEN_RELAY_RESPONSE] boolValue] == YES;
  BOOL isSecuredUrlSpecifiedWithoutFedAuthFlow = ![OM_PROP_AUTHSERVER_FED_AUTH isEqualToString:authType]
  && fedAuthSecuredUrl;

  // If fedAuthSecuredUrl is specified for non Fed auth cases or for fed auth with MCS SAML case, we ignore it.
  if (isSecuredUrlSpecifiedWithoutFedAuthFlow || isMcsSamlFlow) {
    IdmLog(@"Federated auth secured URL passed for non federated auth case or MCS SAML case. The parameter will be ignored.");
    fedAuthSecuredUrl = nil;
  }

  if (fedAuthSecuredUrl) {
    NSDictionary* cookiesAndHeader = [context requestParametersForURL:fedAuthSecuredUrl includeHeaders:YES];
    returnHeaders = [NSMutableDictionary dictionaryWithDictionary:cookiesAndHeader];
  } else if ([OM_PROP_AUTHSERVER_HTTPBASIC isEqualToString:authType]) {
    returnHeaders  = [[NSMutableDictionary alloc] init];
    NSDictionary* credentials = [context credentialInformationForKeys:@[OM_PROP_CREDENTIALS]];
    NSString* userName = credentials[OM_PROP_CREDENTIALS_USERNAME];
    NSString* password = credentials[OM_PROP_CREDENTIALS_PASSWORD];
    NSDictionary* headers = credentials[OM_CUSTOM_HEADERS_MOBILE_AGENT];
    if (headers) {
      [returnHeaders addEntriesFromDictionary:headers];
    }

    if (userName != nil && password != nil) {
      NSString *authorization = [NSString stringWithFormat:@"%@:%@", userName, password];
      NSData *nsdata = [authorization dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:NO];
      NSString *base64EncodedAuthHeader = [nsdata base64EncodedStringWithOptions:0];
      NSString *authHeader = [NSString stringWithFormat:@"Basic %@", base64EncodedAuthHeader];
      returnHeaders[OM_AUTHORIZATION] = authHeader;
    }
  } else if ([OM_PROP_OAUTH_OAUTH20_SERVER isEqualToString:authType] || isMcsSamlFlow) {
    NSDictionary* accessTokens = [context credentialInformationForKeys:@[OM_OAUTH_ACCESS_TOKEN]];
    returnHeaders = [NSMutableDictionary dictionaryWithDictionary:accessTokens];
    NSDictionary* headers = returnHeaders[OM_CUSTOM_HEADERS_MOBILE_AGENT];

    if (headers) {
      [returnHeaders removeObjectForKey:OM_CUSTOM_HEADERS_MOBILE_AGENT];
      [returnHeaders addEntriesFromDictionary:headers];
    }
  }

  CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:returnHeaders];
  [commandDelegate sendPluginResult:result callbackId:callbackId];
  IdmLog(@"getHeaders completed headers");
}

/**
 * Logout.
 * If an error occurs, the error code is communicated back to the javascript layer.
 *
 * @param commandDelegate: callback
 * @param callbackId: callback id
 */
-(void) logout:(CDVCommandDelegateImpl *)commandDelegate
withCallbackId:(NSString *)callbackId {
  IdmLog(@"logout invoked");
  self.loginLogoutCommandDelegate = commandDelegate;
  self.loginLogoutCallbackId = callbackId;
  [_ommss logout:NO];
  IdmLog(@"logout completed");
}

/**
 * This method is used to set a timeout callback during the OMMSS instance creation.
 * If this timeout callback is set, OMMSS callbacks during session timeout and idle timeout
 * will be passed along to this to the javascript layer.
 * If an error occurs, the error code is communicated back to the javascript layer.
 *
 * @param commandDelegate: callback
 * @param callbackId: callback id
 */
- (void) addTimeoutCallback: (CDVCommandDelegateImpl*) commandDelegate
         withCallbackId: (NSString*) callbackId {
  IdmLog(@"addTimeoutCallback invoked");
  self.timeoutCommandDelegate = commandDelegate;
  self.timeoutCallbackId = callbackId;
  IdmLog(@"addTimeoutCallback completed");
}

/**
 * This method is used to reset the idle timeout.
 * If an error occurs, the error code is communicated back to the javascript layer.
 *
 * @param commandDelegate: callback
 * @param callbackId: callback id
 */
- (void) resetIdleTimeout: (CDVCommandDelegateImpl*) commandDelegate
         withCallbackId: (NSString*) callbackId {
  IdmLog(@"resetIdleTimeout invoked");
  OMAuthenticationContext* context = [self.ommss authenticationContext];
  if (context == nil) {
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:NO_AUTH_CONTEXT_ERR_CODE];
    [commandDelegate sendPluginResult:result callbackId:callbackId];
    return;
  }

  [context resetTimer:OMIdleTimer];
  CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:OK];
  [commandDelegate sendPluginResult:result callbackId:callbackId];
  IdmLog(@"resetIdleTimeout completed");
}

/**
 * OMMobileSecurityServiceDelegate protocol implementation
 */
-(void) mobileSecurityService:(OMMobileSecurityService *)mss
        didReceiveAuthenticationChallenge:(OMAuthenticationChallenge *)challenge {
  IdmLog(@"didReceiveAuthenticationChallenge received %@", challenge.authData);
  self.challenge = challenge;
  NSMutableDictionary *fields = [NSMutableDictionary dictionaryWithDictionary:self.challenge.authData];
  NSError* error = fields[@"mobileSecurityException"];

  if (error) {
    fields[@"errorCode"] = [@(error.code) stringValue];
    [fields removeObjectForKey:OM_MOBILESECURITY_EXCEPTION];
  }

  IdmLog(@"Fields from challenge: %@", fields);
  if (challenge.challengeType == OMChallengeUsernamePassword) {
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:@{@"challengeFields": fields}];
    [self.loginLogoutCommandDelegate sendPluginResult:result callbackId:self.loginLogoutCallbackId];
    IdmLog(@"Sending challenge back to user to fill up.");
    return;
  } else if (challenge.challengeType == OMChallengeEmbeddedBrowser) {
    self.challenge = challenge;
    IdmLog(@"Launching webview and redirecting user to login web page.");
    [self launchAndGetWebView:^(NSObject* webView) {
      [fields setValue:webView forKey:OM_PROP_AUTH_WEBVIEW];
      challenge.authChallengeHandler(fields, OMProceed);
    }];
  } else if (challenge.challengeType == OMChallengeInvalidRedirect) {
    NSString* authType = (NSString*) self.properties[OM_PROP_AUTHSERVER_TYPE];
    if ([OM_PROP_OAUTH_OAUTH20_SERVER isEqualToString:authType]) {
      NSString* redirectEndPoint = (NSString*) self.properties[OM_PROP_OAUTH_REDIRECT_ENDPOINT];
      if ([@"http://localhost" isEqualToString:redirectEndPoint]) {
        IdmLog(@"Invalid redirect challenge for redirect end point http://localhost. The challenge will be accepted transparently.");
        challenge.authChallengeHandler(nil, OMProceed);
      } else {
        IdmLog(@"Invalid redirect challenge received. Throwing error to callback");
        [self throwErrorCodeToLoginCallback:INVALID_REDIRECT_ERR_CODE];
      }
    } else {
      IdmLog(@"Invalid redirect challenge received. Throwing error to callback");
      [self throwErrorCodeToLoginCallback:INVALID_REDIRECT_ERR_CODE];
    }
  } else if (challenge.challengeType == OMChallengeServerTrust) {
    IdmLog(@"Untrusted server challenge received. Throwing error to callback");
    [self throwErrorCodeToLoginCallback:UNTRUSTED_SERVER_ERR_CODE];
  } else {
    IdmLog(@"Unsupported challenge %lu.", (unsigned long)challenge.challengeType);
    [self throwErrorCodeToLoginCallback:UNSUPPORTED_CHALLENGE_ERR_CODE];
  }
}

/**
 * OMMobileSecurityServiceDelegate protocol implementation
 */
-(void) mobileSecurityService:(OMMobileSecurityService *)mss
        didFinishAuthentication:(OMAuthenticationContext *)context
        error:(NSError *)error {
  [self dismissAuthWebViewIfNeeded];

  if (error) {
    IdmLog(@"didFinishAuthentication error %@", error);
    [self throwErrorCodeToLoginCallback:[@(error.code) stringValue]];
  } else {
    // In case of iOS the context delegate has to be assigned after login.
    // In case of Android context delegate is assigned before login.
    // The plugin lifecycle is designed with timeout callback registration during init.
    // Retain that and for iOS assign the context delegate after login.
    if (self.timeoutCallbackId != nil) {
      context.delegate = self;
    }
    IdmLog(@"didFinishAuthentication success");
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:OK];
    [self.loginLogoutCommandDelegate sendPluginResult:result callbackId:self.loginLogoutCallbackId];
  }
  [self clearCallbackState];
}

/**
 * OMMobileSecurityServiceDelegate protocol implementation
 */
-(void) mobileSecurityService:(OMMobileSecurityService *)mss
        didReceiveLogoutAuthenticationChallenge:(OMAuthenticationChallenge *)challenge {
  IdmLog(@"didReceiveLogoutAuthenticationChallenge received %@", challenge.authData);
  if (challenge.challengeType == OMChallengeEmbeddedBrowser) {
    self.challenge = challenge;
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionaryWithDictionary:challenge.authData];
    [self launchAndGetWebView:^(NSObject* webView) {
      [dictionary setValue:webView forKey:OM_PROP_AUTH_WEBVIEW];
      challenge.authChallengeHandler(dictionary, OMProceed);
    }];
  }
  IdmLog(@"didReceiveLogoutAuthenticationChallenge complete..");
}

/**
 * OMMobileSecurityServiceDelegate protocol implementation
 */
-(void) mobileSecurityService:(OMMobileSecurityService *)mss
        didFinishLogout:(NSError *)error {
  [self dismissAuthWebViewIfNeeded];

  if (error) {
    IdmLog(@"didFinishLogout error %@", error);
    [self throwErrorCodeToLoginCallback:[@(error.code) stringValue]];
  } else {
    IdmLog(@"didFinishLogout success");
    CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:OK];
    [self.loginLogoutCommandDelegate sendPluginResult:result callbackId:self.loginLogoutCallbackId];
  }
  [self clearCallbackState];
}

/**
 * OMAuthenticationContextDelegate protocol implementation
 */
- (void) authContext:(OMAuthenticationContext *)context
         timeoutOccuredForTimer:(OMTimerType)timerType
         remainingTime:(NSTimeInterval)duration {
  IdmLog(@"timeoutOccuredForTimer invoked");
  NSString* timerTypeStr;
  if (timerType == OMIdleTimer) {
    timerTypeStr = IDLE_TIMEOUT;
  } else if (timerType == OMSessionTimer) {
    timerTypeStr = SESSION_TIMEOUT;
  }
  CDVPluginResult* result = [CDVPluginResult  resultWithStatus:CDVCommandStatus_OK messageAsDictionary:@{TIMEOUT_TYPE_KEY: timerTypeStr, TIME_LEFT_TO_TIMEOUT_KEY: [@(duration) stringValue] }];
  [result setKeepCallback:[NSNumber numberWithBool:YES]];
  [self.timeoutCommandDelegate sendPluginResult:result callbackId:self.timeoutCallbackId];
}

/**
 * Method to add error sting as result of the loginLogoutCommandDelegate.
 */
- (void) throwErrorCodeToLoginCallback:(NSString *) err {
  CDVPluginResult* result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:err];
  [self.loginLogoutCommandDelegate sendPluginResult:result callbackId:self.loginLogoutCallbackId];
}

/**
 * Method to launch the webview view controller.
 */
- (void) launchAndGetWebView:(void(^)(NSObject* webView)) completionCallback {
  IdmLog(@"launchAndGetWebView invoked");

  if ([NSThread currentThread] != [NSThread mainThread]) {
    IdmLog(@"Attempt to launch webview from non main thread...");
  }

  dispatch_async(dispatch_get_main_queue(), ^{
    NSObject* webView = nil;
    UIStoryboard *mainStoryboard = [UIStoryboard storyboardWithName:AUTH_WEB_VIEW bundle:nil];
    self.authViewController = (AuthViewController*) [mainStoryboard instantiateViewControllerWithIdentifier:AUTH_VIEW];
    [self.authViewController setAuthenticationInstance:self.ommss];
    [self.authViewController isWkWebViewEnabled:self.isWkWebViewEnabled];
    [self.baseViewController presentViewController:self.authViewController animated:YES completion:^{
      NSObject* webView = nil;
      if (self.isWkWebViewEnabled && [OMMobileSecurityConfiguration isWKWebViewAvailable]) {
        webView = self.authViewController.wkWebView;
      } else {
        webView = self.authViewController.authWebView;
      }

      if (webView == nil) {
        IdmLog(@"Launching webview has failed.");
      } else {
        IdmLog(@"launchAndGetWebView completed");
        self.isWebViewLaunched = YES;
      }

      completionCallback(webView);
    }];
  });
}


/**
 * Method to dismiss the webview view controller.
 */
- (void) dismissAuthWebViewIfNeeded {
  if (!self.isWebViewLaunched) {
    return;
  }

  IdmLog(@"dismissAuthWebView invoked");

  dispatch_async(dispatch_get_main_queue(), ^{
    [self.authViewController dismissViewControllerAnimated:YES completion:nil];
    self.authViewController = nil;
    self.isWebViewLaunched = NO;
  });

  IdmLog(@"dismissAuthWebView completed");
}

/**
 * Method used to clear the login / logout callback and the challenge references.
 */
- (void) clearCallbackState {
  self.loginLogoutCommandDelegate = nil;
  self.loginLogoutCallbackId = nil;
  self.challenge = nil;
}

/**
 * Extract scope set from authentication properties dictionary.
 * @param authProps: authentication properties - not null
 * @return NSSet* of scope set.
 */
- (NSSet*) extractScopeSet:(NSDictionary*) authProps {
  NSSet* scopeSet = nil;
  NSArray* scope = authProps[OM_PROP_OAUTH_SCOPE];
  if (scope) {
    scopeSet = [NSSet setWithArray:scope];
  }
  return scopeSet;
}
@end
NS_ASSUME_NONNULL_END