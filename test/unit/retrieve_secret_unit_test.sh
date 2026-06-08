#!/bin/bash

# Load the retrieve_secret.sh script
export PARAM_TEST_MODE="true"
source /conjur-circleci-orb/src/scripts/retrieve_secret.sh

export PATH="./test/mocks:$PATH"
export CONJUR_CERTIFICATE="dummy-cert"
export CONJUR_ACCOUNT="testaccount"
export token="fake-token"
export PARAM_APPLIANCE_URL="https://fake-conjur.com"
export PARAM_ALLOW_INSECURE_HTTP="false"
export ALLOW_INSECURE_HTTP="false"
export PARAM_ACCOUNT="my-account"
export PARAM_SERVICE_ID="my-service"
export PARAM_SECRETS_ID="secret1|MY_SECRET"

# oneTimeSetup for mock
oneTimeSetUp() {
  mkdir -p ./test/mocks

  cat > ./test/mocks/curl <<EOF
#!/bin/bash
echo "mocked-response"
EOF
  chmod +x ./test/mocks/curl
}

oneTimeTearDown() {
  rm -rf ./test/mocks
}

assertContains() {
  local string="$1"
  local substring="$2"

  echo "${string}" | grep -qF -- "${substring}"
  local status=$?

  if [[ ${status} -ne 0 ]]; then
    echo "Expected to find '${substring}' in '${string}'"
    return 1
  fi
}

assertNotContains() {
  local string="$1"
  local substring="$2"
  local message="${3:-}"

  echo "${string}" | grep -qF -- "${substring}"
  local status=$?

  if [[ ${status} -eq 0 ]]; then
    if [[ -n "${message}" ]]; then
      echo "${message}"
    else
      echo "Expected NOT to find '${substring}' in '${string}'"
    fi
    return 1
  fi
}

assertIntegerEquals() {
  local expected=$1
  local actual=$2
  
  if ! [[ "${expected}" =~ ^-?[0-9]+$ ]]; then
    echo "FAIL: Expected value '${expected}' is not an integer."
    return 1
  fi

  if ! [[ "${actual}" =~ ^-?[0-9]+$ ]]; then
    echo "FAIL: Actual value '${actual}' is not an integer."
    return 1
  fi

  if [[ "${expected}" -ne "${actual}" ]]; then
    echo "FAIL: Expected '${expected}', but got '${actual}'"
    return 1
  fi
  
  return 0
}

assertRegex() {
 local actual=""
 local pattern=""
 local message=""
 # Handle optional message parameter
 if [[ $# -eq 3 ]]; then
   actual="$1"
   pattern="$2"
   message="$3"
 elif [[ $# -eq 2 ]]; then
   actual="$1"
   pattern="$2"
 else
   fail "assertRegex requires 2 or 3 arguments"
   return "${SHUNIT_FALSE}"
 fi
 # Test if actual matches pattern
 if [[ "${actual}" =~ ${pattern} ]]; then
   return "${SHUNIT_TRUE}"
 else
   if [[ -n "${message}" ]]; then
     _shunit_assertFail "${message}: expected regex [${pattern}] but was [${actual}]"
   else
     _shunit_assertFail "expected regex [${pattern}] but was [${actual}]"
   fi
   return "${SHUNIT_FALSE}"
 fi
}

test_InstallJq_download_linux() {
  export JQ_PATH="./jq_mock"

  # Mock 'command' to be state-aware
  command() {
    local cmd_name="$1"

    if [[ "$cmd_name" == "jq" ]]; then
      # If the file exists (downloaded), return success (0)
      if [[ -f "$JQ_PATH" ]]; then
        return 0 
      else
        return 1 # Not found yet
      fi
    fi
    return 0 # return 0 for curl or other commands
  }
  
  # Mock uname
  uname() { echo "Linux"; }
  
  # Mock curl to create the file
  curl() {
    if [[ "$*" == *"/jq-linux32"* ]]; then
      echo "Downloaded Linux version" > "$JQ_PATH"
      chmod +x "$JQ_PATH"
    fi
  }
  
  # Run function
  InstallJq
  local status=$?
  
  # Check content
  local content
  if [[ -f "$JQ_PATH" ]]; then
      content=$(cat "$JQ_PATH")
  fi
  
  rm -f "$JQ_PATH"
  unset -f command uname curl
  
  assertEquals 0 $status
  assertContains "$content" "Downloaded Linux version"
}

test_InstallJq_download_darwin() {
  export JQ_PATH="./jq_mock_mac"

  # Mock 'command' to be state-aware
  command() {
    local cmd_name="$1"

    if [[ "$cmd_name" == "jq" ]]; then
      # If the file exists (downloaded), return success (0)
      if [[ -f "$JQ_PATH" ]]; then
        return 0 
      else
        return 1 # Not found yet
      fi
    fi
    return 0
  }
  
  # Mock uname
  uname() { echo "Darwin Kernel Version"; }
  
  # Mock curl
  curl() {
    if [[ "$*" == *"/jq-osx-amd64"* ]]; then
      echo "Downloaded OSX version" > "$JQ_PATH"
      chmod +x "$JQ_PATH"
    fi
  }
  
  InstallJq
  local status=$?
  
  local content
  if [[ -f "$JQ_PATH" ]]; then
      content=$(cat "$JQ_PATH")
  fi

  rm -f "$JQ_PATH"
  unset -f command uname curl
  
  assertEquals 0 $status
  assertContains "$content" "Downloaded OSX version"
}

test_InstallJq_missing_curl_fail() {
  # Mock curl being missing
  command() {
    if [[ "$2" == "curl" ]]; then return 1; fi
    if [[ "$2" == "jq" ]]; then return 1; fi
  }
  
  output=$(InstallJq 2>&1)
  status=$?
  
  unset -f command
  
  assertEquals 1 $status
  assertContains "$output" "CONJUR ORB ERROR: CURL is required"
}

# Mock the network_client
mock_network_client_success() {
  token="mocked_token_value"
}

mock_network_client_failure() {
  token=""
}

mock_network_client_multiple_secrets() {
  result='{"db/password": "1234", "api/key": "abcd"}'
}


# Test the `network_client` function
test_network_client_post() {
  unset token
  network_client "POST" "https://fake-conjur.com/authn" "jwt=fake-jwt"
  assertContains "$token" "mocked-response"
}

test_network_client_get() {
  export token="existing-token"
  network_client "GET" "https://fake-conjur.com/secrets"
  assertContains "$result" "mocked-response"
}

test_network_client_unsupported_method() {
  output=$(network_client "PUT" "https://fake-conjur.com" 2>&1)
  status=$?

  assertEquals 1 $status
  assertContains "$output" "Unsupported HTTP method"
}

# Test the `authenticate` function
test_authenticate_success() {
  export CIRCLE_OIDC_TOKEN_V2="mocked_jwt"
  export CONJUR_APPLIANCE_URL="https://fake-conjur.com"
  export CONJUR_ACCOUNT="my-account"
  export CONJUR_SERVICE_ID="my-service"

  network_client() { mock_network_client_success "$@"; }

  output=$(authenticate 2>&1)
  status=$?

  assertEquals 0 $status
  assertContains "$output" "Authentication Successful."
}

test_authenticate_failure() {
  export CIRCLE_OIDC_TOKEN_V2="mocked_jwt"
  export CONJUR_APPLIANCE_URL="https://fake-conjur.com"
  export CONJUR_ACCOUNT="my-account"
  export CONJUR_SERVICE_ID="my-service"

  network_client() { mock_network_client_failure "$@"; }

  output=$(authenticate 2>&1)
  status=$?

  assertEquals 1 $status
  assertContains "$output" "Authentication Failed."
}

# Test the `multiple_secrets_fetch` function
test_multiple_secrets_fetch_success() {
  export CONJUR_APPLIANCE_URL="https://fake-conjur.com"
  secrets_string="db/password,api/key"

  network_client() { mock_network_client_multiple_secrets "$@"; }

  multiple_secrets_fetch

  expected_output="db/password=1234,api/key=abcd"

  assertContains "$secretsVal" "$expected_output"
}

test_multiple_secrets_fetch_empty_result() {
  export CONJUR_APPLIANCE_URL="https://fake-conjur.com"
  secrets_string="db/password,api/key"

  network_client() { result='{}'; }

  multiple_secrets_fetch

  assertContains "$secretsVal" ""
}

# Test the `single_secret_fetch` function
test_single_secret_fetch_success() {
  declare -A secretMulti
  secretMulti=( ["good-secret"]=MY_SECRET )
  echo "secretMulti: ${secretMulti[*]}"

  network_client() {
    result="my-secret-value"
  }
  output=$(single_secret_fetch 2>&1)

  assertContains "${output}" "As the job will be marked as unsuccessful"
}

test_single_secret_fetch_empty_secret() {
  declare -A secretMulti
  secretMulti=( ["missing-secret"]=MY_SECRET )
  echo "secretMulti: ${secretMulti[*]}"

  network_client() {
    result="Variable missing-secret is empty or not found"
  }

  output=$(single_secret_fetch 2>&1)

  assertContains "$output" "Secret(s) are empty or not found :: missing-secret,"
}

test_single_secret_fetch_malformed_token() {
  declare -A secretMulti
  secretMulti=( ["bad-token"]=MY_SECRET )
  echo "secretMulti: ${secretMulti[*]}"

  network_client() {
    result="Malformed authorization token"
  }
  output=$(single_secret_fetch 2>&1)

  assertContains "$output" "::error::Malformed authorization token"
}

# Test validate_appliance_url
test_validate_appliance_url_rejects_http() {
  output=$(validate_appliance_url "http://conjur.internal.example" "false" 2>&1)
  status=$?

  assertEquals 1 "${status}"
  assertContains "${output}" "uses http://"
  assertContains "${output}" "allow_insecure_http"
}

test_validate_appliance_url_accepts_https() {
  validate_appliance_url "https://conjur.example.com" "false"
  assertEquals 0 $?
}

test_validate_appliance_url_accepts_https_with_insecure_flag_no_warning() {
  output=$(validate_appliance_url "https://conjur.example.com" "true" 2>&1)
  status=$?

  assertEquals 0 "${status}"
  assertEquals "" "${output}"
}

test_validate_appliance_url_rejects_empty_url() {
  output=$(validate_appliance_url "" "false" 2>&1)
  status=$?

  assertEquals 1 "${status}"
  assertContains "${output}" "must use https://"
}

test_validate_appliance_url_rejects_whitespace() {
  output=$(validate_appliance_url "https://conjur.example.com/path with space" "false" 2>&1)
  status=$?

  assertEquals 1 "${status}"
  assertContains "${output}" "must not contain whitespace"
}

test_validate_appliance_url_allow_insecure_warns() {
  output=$(validate_appliance_url "http://conjur.internal.example" "true" 2>&1)
  status=$?

  assertEquals 0 "${status}"
  assertContains "${output}" "::warning::allow_insecure_http is enabled"
}

test_validate_appliance_url_rejects_non_http_scheme() {
  output=$(validate_appliance_url "ftp://conjur.internal.example" "true" 2>&1)
  status=$?

  assertEquals 1 "${status}"
  assertContains "${output}" "must use https://"
}

test_validate_appliance_url_resolved_env_http_rejected() {
  export ORB_TEST_HTTP_URL='http://resolved-insecure.example'
  ALLOW_INSECURE_HTTP="false"
  CONJUR_APPLIANCE_URL="$(resolve_param_value '${ORB_TEST_HTTP_URL}')"
  output=$(validate_appliance_url "${CONJUR_APPLIANCE_URL}" "${ALLOW_INSECURE_HTTP}" 2>&1)
  status=$?

  unset ORB_TEST_HTTP_URL
  assertEquals 1 "${status}"
  assertContains "${output}" "uses http://"
}

test_main_rejects_http_appliance_url() {
  export CIRCLE_OIDC_TOKEN_V2="valid-oidc-token"
  export PARAM_APPLIANCE_URL="http://conjur.internal.example"
  export PARAM_ALLOW_INSECURE_HTTP="false"

  output=$(main 2>&1)
  status=$?

  assertEquals 1 "${status}"
  assertContains "${output}" "uses http://"
  assertNotContains "${output}" "Authenticate via Authn-JWT" "main must fail before authentication"
}

test_network_client_enforces_https_curl_options() {
  CONJUR_APPLIANCE_URL="https://fake-conjur.com"
  ALLOW_INSECURE_HTTP="false"
  export token="existing-token"
  CURL_INVOCATION=()

  curl() {
    CURL_INVOCATION=("$@")
    echo "mocked-response"
  }

  network_client "GET" "https://fake-conjur.com/secrets"
  unset -f curl

  assertContains "${CURL_INVOCATION[*]}" "--proto https"
  assertContains "${CURL_INVOCATION[*]}" "--proto-redir https"
  assertContains "${CURL_INVOCATION[*]}" "--ssl-reqd"
  assertContains "${CURL_INVOCATION[*]}" "-sS"
}

test_network_client_omits_https_curl_options_when_insecure_allowed() {
  CONJUR_APPLIANCE_URL="http://conjur.internal.example"
  ALLOW_INSECURE_HTTP="true"
  export token="existing-token"
  CURL_INVOCATION=()

  curl() {
    CURL_INVOCATION=("$@")
    echo "mocked-response"
  }

  network_client "GET" "http://conjur.internal.example/secrets"
  unset -f curl

  assertNotContains "${CURL_INVOCATION[*]}" "--proto https"
  assertNotContains "${CURL_INVOCATION[*]}" "--ssl-reqd"
}

test_network_client_keeps_https_curl_options_when_flag_true_with_https_url() {
  CONJUR_APPLIANCE_URL="https://conjur.internal.example"
  ALLOW_INSECURE_HTTP="true"
  export token="existing-token"
  CURL_INVOCATION=()

  curl() {
    CURL_INVOCATION=("$@")
    echo "mocked-response"
  }

  network_client "GET" "https://conjur.internal.example/secrets"
  unset -f curl

  assertContains "${CURL_INVOCATION[*]}" "--proto https"
  assertContains "${CURL_INVOCATION[*]}" "--proto-redir https"
  assertContains "${CURL_INVOCATION[*]}" "--ssl-reqd"
}

test_network_client_enforces_https_curl_options_for_http_url_without_flag() {
  CONJUR_APPLIANCE_URL="http://conjur.internal.example"
  ALLOW_INSECURE_HTTP="false"
  export token="existing-token"
  CURL_INVOCATION=()

  curl() {
    CURL_INVOCATION=("$@")
    echo "mocked-response"
  }

  network_client "GET" "http://conjur.internal.example/secrets"
  unset -f curl

  assertContains "${CURL_INVOCATION[*]}" "--proto https"
  assertContains "${CURL_INVOCATION[*]}" "--proto-redir https"
  assertContains "${CURL_INVOCATION[*]}" "--ssl-reqd"
}

# Test the `check_parameter` function
test_check_parameter_missing_value() {
  PARAM_ACCOUNT=""
  result=$(check_parameter "CONJUR_ACCOUNT" "$PARAM_ACCOUNT")
  assertContains "$result" "The CONJUR_ACCOUNT is not found. Please add the CONJUR_ACCOUNT before continuing."
}

test_check_parameter_valid_value() {
  PARAM_ACCOUNT="my_account"
  result=$(check_parameter "CONJUR_ACCOUNT" "$PARAM_ACCOUNT")
  assertContains "$result" ""
}

# resolve_param_value: no command execution for literals containing $(...)
test_resolve_param_value_command_substitution_stays_literal() {
  local resolved
  resolved="$(resolve_param_value 'myacct$(id)')"
  assertEquals 'myacct$(id)' "$resolved"
}

# Exact ${VAR} only: one-level indirect expansion from environment
test_resolve_param_value_indirect_expansion() {
  export ORB_TEST_CONJUR_URL='https://resolved-from-env.example'
  local resolved
  resolved="$(resolve_param_value '${ORB_TEST_CONJUR_URL}')"
  assertEquals 'https://resolved-from-env.example' "$resolved"
  unset ORB_TEST_CONJUR_URL
}

test_resolve_param_value_plain_string_unchanged() {
  local resolved
  resolved="$(resolve_param_value 'https://literal-url.example')"
  assertEquals 'https://literal-url.example' "$resolved"
}

test_resolve_param_value_braced_not_whole_string_unchanged() {
  local resolved
  resolved="$(resolve_param_value 'prefix${VAR}suffix')"
  assertEquals 'prefix${VAR}suffix' "$resolved"
}

# Unset target: indirect expansion yields empty (not fallback to literal ${NAME})
test_resolve_param_value_unset_variable_empty() {
  unset ORB_RESOLVE_PARAM_UNSET_TEST_7f3a2b1c
  local resolved
  resolved="$(resolve_param_value '${ORB_RESOLVE_PARAM_UNSET_TEST_7f3a2b1c}')"
  assertEquals '' "$resolved"
}

# Name must match POSIX identifier after ${ — digit-first is not expanded
test_resolve_param_value_invalid_name_digit_prefix_unchanged() {
  local resolved
  resolved="$(resolve_param_value '${9x}')"
  assertEquals '${9x}' "$resolved"
}

# Only braced whole-token ${VAR} is supported, not unbraced $VAR
test_resolve_param_value_unbraced_unchanged() {
  local resolved
  resolved="$(resolve_param_value '$HOME')"
  assertEquals '$HOME' "$resolved"
}

# Variable set but empty: still empty expansion
test_resolve_param_value_variable_empty_string() {
  export ORB_RESOLVE_EMPTY_STR=''
  local resolved
  resolved="$(resolve_param_value '${ORB_RESOLVE_EMPTY_STR}')"
  assertEquals '' "$resolved"
  unset ORB_RESOLVE_EMPTY_STR
}

# Malformed / empty brace body: no match, passthrough
test_resolve_param_value_empty_braces_unchanged() {
  local resolved
  resolved="$(resolve_param_value '${}')"
  assertEquals '${}' "$resolved"
}

# Test the `urlencode` function
test_urlencode_basic() {
  result=$(urlencode "hello world")
  assertContains "$result" "hello%20world"
}

test_urlencode_special_characters() {
  result=$(urlencode "a+b&c/d?e=f")
  assertContains "$result" "a%2Bb%26c%2Fd%3Fe%3Df"
}

# Test the `InstallJq` function
test_install_jq_existing() {
  command -v jq >/dev/null 2>&1 || touch /usr/bin/jq
  InstallJq
  assertEquals 0 $?
}

# Test the `array_secrets` function
test_array_secrets_single_secret() {
  export CONJUR_SECRETS_ID="my-secret|MY_ENV"
  array_secrets

  assertIntegerEquals 1 "${#SECRETS[@]}"
  assertContains "${SECRETS[0]}" "my-secret|MY_ENV"
}

test_array_secrets_multiple_secrets() {
  export CONJUR_SECRETS_ID="db/password|DB_PASS;api/key|API_KEY"
  array_secrets

  assertIntegerEquals 2 "${#SECRETS[@]}"
  assertContains "${SECRETS[0]}" "db/password|DB_PASS"
  assertContains "${SECRETS[1]}" "api/key|API_KEY"
}

test_array_secrets_no_separator() {
  export CONJUR_SECRETS_ID="plainsecret"
  array_secrets

  assertIntegerEquals 1 "${#SECRETS[@]}"
  assertContains "${SECRETS[0]}" "plainsecret"
}

test_array_secrets_empty_string() {
  export CONJUR_SECRETS_ID=""
  array_secrets

  assertIntegerEquals 0 "${#SECRETS[@]}"
}

test_array_secrets_trailing_semicolon() {
  export CONJUR_SECRETS_ID="secret1|ENV1;"
  array_secrets
  
  assertIntegerEquals 1 "${#SECRETS[@]}" 
  assertContains "${SECRETS[0]}" "secret1|ENV1"
}

# Secret values must not execute shell when BASH_ENV is sourced (report-style payloads).
test_set_environment_var_percent_q_snippet_safe_to_source() {
  local report_payload="x'; export INJECTED_F004=pwned #"
  export BASH_ENV="/tmp/.bash_env_pct_$$"
  rm -f "${BASH_ENV}"
  unset MY_SECRET INJECTED_F004
  malicious_ran=""
  malicious() { malicious_ran=yes; }
  export -f malicious

  # Exact CVE payload on the line we write (printf %q), bypassing jq/comma/= parsing.
  printf 'export %s=%q\n' MY_SECRET "${report_payload}" >>"${BASH_ENV}"
  # shellcheck disable=SC1090
  source "${BASH_ENV}"
  assertEquals "" "${malicious_ran}"
  assertEquals "" "${INJECTED_F004:-}"
  assertEquals "${report_payload}" "${MY_SECRET}"

  # Through set_environment_var: no extra '=' in the value (parser uses equal_split[1] only).
  local integr_payload="x'; export INJECTED_F004; #"
  rm -f "${BASH_ENV}"
  unset MY_SECRET INJECTED_F004
  malicious_ran=""
  secretsVal=("a:MY_SECRET=${integr_payload}")
  declare -A secretMulti
  secretMulti[MY_SECRET]=MY_SECRET
  urlencode() { echo "$1"; }
  set_environment_var
  # shellcheck disable=SC1090
  source "${BASH_ENV}"
  assertEquals "" "${malicious_ran}"
  assertEquals "" "${INJECTED_F004:-}"
  assertEquals "${integr_payload}" "${MY_SECRET}"

  unset MY_SECRET INJECTED_F004
  unset -f malicious urlencode
  rm -f "${BASH_ENV}"
}

# Test the `set_environment_var` function
test_set_environment_var_never_logs_secret_value() {
  secretsVal=("prefix:secret1=value1,prefix:secret2=value2")
  PARAM_INTEGR="true"
  export BASH_ENV="/tmp/.bash_env_no_leak_$$"
  rm -f "${BASH_ENV}"
  declare -A secretMulti
  secretMulti=( ["secret1"]=FIRST_SECRET ["secret2"]=SECOND_SECRET )

  urlencode() {
    echo "$1"
  }

  output=$(set_environment_var 2>&1)

  assertNotContains "${output}" "value1"
  assertNotContains "${output}" "value2"
  assertContains "${output}" "Environment variable FIRST_SECRET set."
  assertContains "${output}" "Environment variable SECOND_SECRET set."
  # shellcheck disable=SC1090
  source "${BASH_ENV}"
  assertEquals "value1" "${FIRST_SECRET}"
  assertEquals "value2" "${SECOND_SECRET}"
  rm -f "${BASH_ENV}"
  unset -f urlencode
}

test_set_environment_var_empty_secrets() {
  secretsVal=()
  export BASH_ENV="/tmp/.bash_env_mock"

  output=$(set_environment_var 2>&1)
  
  assertContains "${output}" ""
}

test_set_environment_var_multiple_secrets() {
  secretsVal=("secret1:MY_SECRET=value1,secret2:MY_SECRET=value2")
  secretMulti=("MY_SECRET"="MY_SECRET")
  export BASH_ENV="/tmp/.bash_env_mock"

  urlencode() {
    echo "$1"
  }

  output=$(set_environment_var 2>&1)

  echo "secretMulti: ${secretMulti[*]}"
  assertContains "${output}" "Secret fetched successfully.  Environment variable MY_SECRET=MY_SECRET set."
}

# Test the `fetch_secret` function
test_fetch_secret_valid_input() {
  SECRETS=("secret1:MY_SECRET=value1,secret2:MY_SECRET=value2")
  CONJUR_ACCOUNT="my_conjur_account"
  secretVal="value1,value2"
  
  urlencode() { echo "$1"; }
  multiple_secrets_fetch() { secretVal="value1,value2"; }
  set_environment_var() { echo "Environment variables set"; }
  
  output=$(fetch_secret 2>&1)
  
  assertContains "$output" "Batch retrieval of secrets succeeded."
  assertContains "$output" "Environment variables set"
}

test_fetch_secret_malformed_token() {
  SECRETS=("secret1:MY_SECRET=value1")
  CONJUR_ACCOUNT="my_conjur_account"
  secretVal="Malformed authorization token"
  
  urlencode() { echo "$1"; }
  multiple_secrets_fetch() { secretVal="Malformed authorization token"; }
  set_environment_var() { echo "Environment variables set"; }

  output=$(fetch_secret 2>&1)
  
  assertContains "$output" "::error::Malformed authorization token"
}

test_fetch_secret_no_secrets() {
  SECRETS=()
  CONJUR_ACCOUNT="my_conjur_account"
  secretVal="value1,value2"
  
  urlencode() { echo "$1"; }
  multiple_secrets_fetch() { secretVal="value1,value2"; }
  set_environment_var() { echo "Environment variables set"; }

  output=$(fetch_secret 2>&1)

  
  assertContains "${output}" "Batch retrieval of secrets succeeded."
  assertContains "${output}" "Environment variables set"
}

test_main_empty_oidc_token() {
  export CIRCLE_OIDC_TOKEN_V2=""
  
  output=$(main 2>&1)
  
  assertContains "$output" "OIDC Token cannot be found. A CircleCI context must be specified."
}

test_main_provided_oidc_token() {
  export CIRCLE_OIDC_TOKEN_V2="valid-oidc-token"

  output=$(main 2>&1)

  assertContains "$output" "::debug Authenticate via Authn-JWT"
}

test_multiple_secrets_fetch_empty_or_not_found() {
  multiple_secrets_fetch() { secretsVal="Variable secret1 is empty or not found"; }
  single_secret_fetch() { echo "single_secret_fetch called"; }
  
  output=$(fetch_secret 2>&1)
  
  assertContains "$output" "Batch retrieval failed, falling to single secret fetch"
  assertContains "$output" "single_secret_fetch called"
}

test_default_version_no_changelog() {
  output="$(get_telemetry_header 2>&1)"

  assertRegex "${output}" '^[A-Za-z0-9_-]+$' "Output must be URL-safe base64"
  assertNotContains "${output}" "=" "Output must not contain padding"
  [[ -n "${output}" ]] || fail "Output must not be empty"
}

test_extracts_version_from_changelog() {

  output="$(get_telemetry_header 2>&1)"

  decoded="$(echo "${encoded}" | base64 --decode 2>/dev/null)"
  assertContains "${decoded}" "iv=0.0.3" "Version mismatch"
  assertContains "${decoded}" "in=CircleCI"
}

test_takes_first_version_only() {
  output="$(get_telemetry_header 2>&1)"

  decoded="$(echo "${encoded}" | base64 --decode)"
  assertContains "${decoded}" "iv=0.0.3"
  assertNotContains "${decoded}" "iv=0.0.2"
}

test_decoded_fields_structure() {
  output="$(get_telemetry_header 2>&1)"

  decoded="$(echo "${encoded}" | base64 --decode)"
  assertContains "${decoded}" "in=CircleCI"
  assertContains "${decoded}" "it=CI/CD"
  assertContains "${decoded}" "iv=0.0.0-default"
  assertContains "${decoded}" "vn=CircleCI"
}

# Load 
. /usr/bin/shunit2
