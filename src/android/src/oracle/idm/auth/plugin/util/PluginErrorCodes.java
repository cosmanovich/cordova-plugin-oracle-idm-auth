package oracle.idm.auth.plugin.util;

public interface PluginErrorCodes {
  String INVALID_REDIRECT_CHALLENGE = "P1001";
  String UNTRUSTED_CHALLENGE = "P1002";
  String UNSUPPORTED_CHALLENGE = "P1003";
  String IDLE_TIMEOUT_RESET_FAILED = "P1004";
  String NULL_ARGS_FOR_INIT = "P1005";
  String NULL_ARGS_FOR_CHALLENGE = "P1006";
  String NULL_ARGS = "P1007";
  String NULL_AUTH_FLOW_KEY = "P1008";
  String INVALID_AUTH_FLOW_KEY = "P1009";
  String NO_AUTH_CONTEXT = "P1010";
  String UNUSED_AND_DEPRECATED_ERR_CODE = "P1011";
  String EXTERNAL_BROWSER_LAUNCH_FAILED = "P1012";
  String SETUP_ERROR = "10015"; // Reuse existing code from IDM SDK
  String AUTHENTICATION_FAILED = "10408"; // Reuse existing code from IDM SDK
  String AUTHENTICATION_CANCELLED = "10029"; // Reuse existing code from IDM SDK
  String INCORRECT_CURRENT_AUTHDATA = "70009"; // Reuse code from iOS SDK

  // Local auth related
  String LOCAL_AUTHENTICATOR_NOT_FOUND = "70001";
  String NO_LOCAL_AUTHENTICATORS_ENABLED = "P1013";
  String UNKNOWN_LOCAL_AUTH_TYPE = "P1014";
  String ONGOING_TASK = "P1015";
  String ENABLE_FINGERPRINT_PIN_NOT_ENABLED = "P1016";
  String DISABLE_PIN_FINGERPRINT_ENABLED = "P1017";
  String ERROR_ENABLING_AUTHENTICATOR = "P1018";
  String FINGERPRINT_NOT_ENABLED = "P1019";
  String CHANGE_PIN_WHEN_PIN_NOT_ENABLED = "P1020";
  String GET_ENABLED_AUTHS_ERROR = "P1021";
}