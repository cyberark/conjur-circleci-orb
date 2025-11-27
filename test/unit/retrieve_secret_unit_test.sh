#!/bin/bash

# Load the retrieve_secret.sh script
export PARAM_TEST_MODE="true"
source /conjur-circleci-orb/src/scripts/retrieve_secret.sh

export PATH="./test/mocks:$PATH"
export CONJUR_CERTIFICATE="dummy-cert"
export CONJUR_ACCOUNT="testaccount"
export token="fake-token"

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

  echo "$string" | grep -qF -- "$substring"
  local status=$?

  if [[ $status -ne 0 ]]; then
    echo "Expected to find '$substring' in '$string'"
    return 1
  fi
}

assertIntegerEquals() {
  local expected=$1
  local actual=$2
  
  if ! [[ "$expected" =~ ^-?[0-9]+$ ]]; then
    echo "FAIL: Expected value '$expected' is not an integer."
    return 1
  fi

  if ! [[ "$actual" =~ ^-?[0-9]+$ ]]; then
    echo "FAIL: Actual value '$actual' is not an integer."
    return 1
  fi

  if [[ "$expected" -ne "$actual" ]]; then
    echo "FAIL: Expected '$expected', but got '$actual'"
    return 1
  fi
  
  return 0
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

  network_client() {
    result="my-secret-value"
  }
  output=$(single_secret_fetch 2>&1)

  assertContains "$output" "As the job will be marked as unsuccessful"
}

test_single_secret_fetch_empty_secret() {
  declare -A secretMulti
  secretMulti=( ["missing-secret"]=MY_SECRET )

  network_client() {
    result="Variable missing-secret is empty or not found"
  }

  output=$(single_secret_fetch 2>&1)

  assertContains "$output" "Secret(s) are empty or not found :: missing-secret,"
}

test_single_secret_fetch_malformed_token() {
  declare -A secretMulti
  secretMulti=( ["bad-token"]=MY_SECRET )

  network_client() {
    result="Malformed authorization token"
  }
  output=$(single_secret_fetch 2>&1)

  assertContains "$output" "::error::Malformed authorization token"
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


# Test the `set_environment_var` function
test_set_environment_var_param_integr_true() {
  secretsVal=("secret1:MY_SECRET=value1,secret2:MY_SECRET=value2")
  PARAM_INTEGR="true"
  
  output=$(set_environment_var 2>&1)
  
  assertContains "$output" "Secret fetched successfully. fetched :: value1"
  assertContains "$output" "Secret fetched successfully. fetched :: value2"
}

test_set_environment_var_empty_secrets() {
  secretsVal=()
  PARAM_INTEGR="false"
  export BASH_ENV="/tmp/.bash_env_mock"

  output=$(set_environment_var 2>&1)
  
  assertContains "$output" ""
}

test_set_environment_var_multiple_secrets() {
  secretsVal=("secret1:MY_SECRET=value1,secret2:MY_SECRET=value2")
  PARAM_INTEGR="false"
  secretMulti=("MY_SECRET"="MY_SECRET")
  export BASH_ENV="/tmp/.bash_env_mock"

  urlencode() {
    echo "$1"
  }

  output=$(set_environment_var 2>&1)

  assertContains "$output" "Secret fetched successfully.  Environment variable MY_SECRET=MY_SECRET set."
}

# Test the `fetch_secret` function
test_fetch_secret_valid_input() {
  SECRETS=("secret1:MY_SECRET=value1,secret2:MY_SECRET=value2")
  CONJUR_ACCOUNT="my_conjur_account"
  secretVal="value1,value2"
  PARAM_INTEGR="false"
  
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
  PARAM_INTEGR="false"
  
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
  PARAM_INTEGR="false"
  
  urlencode() { echo "$1"; }
  multiple_secrets_fetch() { secretVal="value1,value2"; }
  set_environment_var() { echo "Environment variables set"; }

  output=$(fetch_secret 2>&1)
  
  assertContains "$output" "Batch retrieval of secrets succeeded."
  assertContains "$output" "Environment variables set"
}

test_main_empty_oidc_token() {
  export PARAM_APPLIANCE_URL="https://fake-conjur.com"
  export PARAM_ACCOUNT="my-account"
  export PARAM_SERVICE_ID="my-service"
  export PARAM_SECRETS_ID="secret1|MY_SECRET"
  export CIRCLE_OIDC_TOKEN_V2=""
  
  output=$(main 2>&1)
  
  assertContains "$output" "OIDC Token cannot be found. A CircleCI context must be specified."
}

test_main_provided_oidc_token() {
  export PARAM_APPLIANCE_URL="https://fake-conjur.com"
  export PARAM_ACCOUNT="my-account"
  export PARAM_SERVICE_ID="my-service"
  export PARAM_SECRETS_ID="secret1|MY_SECRET"
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

# Load shUnit2
. /usr/bin/shunit2
