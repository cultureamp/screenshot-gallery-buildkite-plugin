#!/usr/bin/env bash
set -eu
set -o pipefail

# Are we running as a script that has been 'source'd, eg. 'source ./bin/support/github_status.sh'?
(return 0 2>/dev/null) && IS_SOURCED_SCRIPT=true || IS_SOURCED_SCRIPT=false

# Stub out the notification functions; it's a no-op by default, and only 'activated'
# in the appropriate context (in CI).
post_status_to_current_github_pr(){ true; }
post_status_to_triggering_github_pr(){ true; }

if [ -z "${BUILDKITE:-}" ]; then
  # Not running in CI; either exit completely, or return to the script that's 'source'-ing us.
  "$IS_SOURCED_SCRIPT" && return 0 || exit 0
fi

# ------------------------------------------------------------------

# Private helper used by the post_status_to_...() functions below.
get_github_api_token() {
  # Not set in the environment...?
  if [ -z "${GITHUB_STATUS_ACCESS_TOKEN:-}" ]; then
    # ... Then get GITHUB_STATUS_ACCESS_TOKEN from parameter store.

    if [ -z "${GITHUB_STATUS_ACCESS_TOKEN_PARAM_PATH:-}" ] || ! GITHUB_STATUS_ACCESS_TOKEN="$(
      aws ssm get-parameter --name "${GITHUB_STATUS_ACCESS_TOKEN_PARAM_PATH}" \
        --with-decryption --query=Parameter.Value --output=text
    )"; then
      >&2 echo \
        "A GITHUB_STATUS_ACCESS_TOKEN is required to post status to github." \
        "For local development this can be set as an environment variable." \
        "In the CI account this is pulled from paramater store." \
        "Please set the value of GITHUB_STATUS_ACCESS_TOKEN, or pass a" \
        "GITHUB_STATUS_ACCESS_TOKEN_PARAM_PATH (eg. '/visual-tests/GITHUB_STATUS_ACCESS_TOKEN')" \
        "and ensure your CI step has access to pull ${GITHUB_STATUS_ACCESS_PARAM:-that parameter}" \
        "from parameter store."
        return 1
    fi
  fi
  echo "$GITHUB_STATUS_ACCESS_TOKEN"
}

# Private helper used by the post_status_to_...() functions below.
post_status() {
  local status=$1 # success, pending, failure
  local target_url=$2
  local description=$3
  local sha_url=$4

  local github_api_token
  if ! github_api_token=$(get_github_api_token); then
    return 0 # Silently fail if no token has been found.
  fi

  local context="${BUILDKITE_PIPELINE_NAME}"
  local time_since_start="$((SECONDS / 60)) minutes, $((SECONDS % 60)) seconds" # Uses Bash's $SECONDS global.
  case "$status" in
    pending)
      : "${description:="Build #${BUILDKITE_BUILD_NUMBER} started"}"
      ;;
    success)
      : "${description:="Build #${BUILDKITE_BUILD_NUMBER} passed (${time_since_start})"}"
      ;;
    failure)
      : "${description:="Build #${BUILDKITE_BUILD_NUMBER} failed (${time_since_start})"}"
      ;;
    *)
      echo "Invalid GitHub status: '${status}' (Must be: success, pending or failure)"
      return 1
      ;;
  esac

  curl --fail --silent -request POST --url "$sha_url" \
    --header "authorization: Bearer ${github_api_token}" \
    --header 'content-type: application/json' \
    --data "$(
       echo '{}' | jq \
         --arg state "$status" \
         --arg description "$description" \
         --arg context "$context" \
         --arg target_url "$target_url" \
         ' .
         | .["state"]=$state
         | .["description"]=$description
         | .["context"]=$context
         | .["target_url"]=$target_url' \
    )"
}

post_status_to_current_github_pr() {
  local status=$1 # success, pending, failure
  local target_url=$2
  local description=${3:-}

  # The GitHub API URL we hit to tell GH about the status of the build.
  local sha_url="https://api.github.com/repos/${BUILDKITE_GITHUB_ORG}/${BUILDKITE_GITHUB_REPO}/statuses/${BUILDKITE_COMMIT}"

  echo "--- Setting GitHub status"
  echo "Setting the status '$status' and description '$description' on commit SHA $BUILDKITE_COMMIT with target URL: $target_url"

  post_status "$status" "$target_url" "$description" "$sha_url"
}

post_status_to_triggering_github_pr() {
  local status=$1 # success, pending, failure
  local target_url=$2
  local description=${3:-}

  if [ -z "${BUILDKITE_TRIGGERED_FROM_GITHUB_ORG:-}" ]; then
    return 0 # Not a triggered build.
  fi

  # The GitHub API URL we hit to tell GH about the status of the build.
  local sha_url="https://api.github.com/repos/${BUILDKITE_TRIGGERED_FROM_GITHUB_ORG}/${BUILDKITE_TRIGGERED_FROM_GITHUB_REPO}/statuses/${BUILDKITE_TRIGGERED_FROM_COMMIT}"

  echo "--- Setting GitHub status on triggering build"
  echo "Setting the status '$status' and description '$description' on commit SHA $BUILDKITE_TRIGGERED_FROM_COMMIT with target URL: $target_url"

  post_status "$status" "$target_url" "$description" "$sha_url"
}
