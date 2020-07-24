#!/usr/bin/env bash
set -e # exit on unhandled error
set -u # exit if variables undefined

script_dir=$(unset CDPATH && cd "$(dirname "$0")" >/dev/null && pwd)


### Import+define functions

# shellcheck source=src/github_status.sh
source "${script_dir}/src/github_status.sh"

# For Buildkite logs.
section() { echo "--- $1"; }


### Script variables

# NOTE: Please declare anything that relies on external environment variables in this
# section. If a variable is missing, the `set -u` will make bash exit *here* instead
# of in the middle of uploading or something.

# 'triggering build', as in:
# - a system-tests custom branch build (eg. system-tests running a build for
#   system-tests branch my/branch/name), or
# - a system-tests master branch build being triggered by a murmur custom branch build
#   (eg. system-tests master being run for murmur branch my/branch/name), or
# - a system-tests master branch build being triggered by murmur master
#   (ie. system-tests master and murmur master).
export triggering_buildkite_slug="${BUILDKITE_TRIGGERED_FROM_BUILD_PIPELINE_SLUG:-$BUILDKITE_PIPELINE_SLUG}"
export triggering_commit="${BUILDKITE_TRIGGERED_FROM_COMMIT:-$BUILDKITE_COMMIT}"
export triggering_repo_and_commit="${triggering_buildkite_slug}/${triggering_commit}"
export triggering_repo_and_branch="${triggering_buildkite_slug}/${BUILDKITE_TRIGGERED_FROM_BRANCH:-$BUILDKITE_BRANCH}"
export triggering_commit_images_dir="./${triggering_repo_and_commit}"

# 'canonical branch' meaning the repo+branch you want any builds to be compared against.
# We treat Murmur's master branch as the 'latest known good' thing to compare the
# triggering build with, displaying its images inline along with diffs.
export canonical_repo_and_branch="${CANONICAL_REPO_AND_BRANCH}" # eg. murmur/master
export canonical_branch_images_dir="./${canonical_repo_and_branch}"

export screenshot_pattern="${SCREENSHOT_PATTERN:-*.png}"

export buildkite_pipeline_name="${BUILDKITE_PIPELINE_NAME}"

export gallery_filename="index.html"
export gallery_bucket_name="$GALLERY_BUCKET_NAME"
export gallery_index_url="${GALLERY_BASE_URL}/${triggering_repo_and_commit}/${gallery_filename}"
export gallery_url_base="/"


### Download the 'current master' gallery, if available.

if
  [ "$triggering_repo_and_branch" != "$canonical_repo_and_branch" ] && \
  aws s3 ls "s3://${gallery_bucket_name}/${canonical_repo_and_branch}/${gallery_filename}"
then
  section "Download '${canonical_repo_and_branch}' branch gallery"
  aws s3 sync --delete \
    "s3://${gallery_bucket_name}/${canonical_repo_and_branch}" "$canonical_branch_images_dir"
  ls -lh
fi


### Prepare and upload gallery

# ... for the current commit:

section "Gather screenshots for current build"
mkdir -p "$triggering_commit_images_dir"
buildkite-agent artifact download "${screenshot_pattern}" "${triggering_commit_images_dir}/"

section "Build screenshot gallery .html"
docker-compose run \
  -e buildkite_pipeline_name \
  -e triggering_commit -e triggering_repo_and_branch -e canonical_repo_and_branch \
  -e triggering_commit_images_dir -e canonical_branch_images_dir -e gallery_url_base \
  -v "$PWD:/app" -w /app \
  generate-gallery \
  "/app/gallery/src/gallery.rb" "${triggering_commit_images_dir}/${gallery_filename}"

section "Upload screenshots + .html to ${gallery_bucket_name}"
aws s3 sync --delete --acl public-read \
  "$triggering_commit_images_dir" "s3://${gallery_bucket_name}/${triggering_repo_and_commit}"


# ... for murmur/master, if applicable:

if [ "$triggering_repo_and_branch" == "$canonical_repo_and_branch" ]; then
  mkdir -p "$canonical_branch_images_dir"
  cp -a "${triggering_commit_images_dir}/"* "${canonical_branch_images_dir}/"

  section "Update '${canonical_repo_and_branch}' branch gallery"
  aws s3 sync --delete --acl public-read \
    "$canonical_branch_images_dir" "s3://${gallery_bucket_name}/${canonical_repo_and_branch}"
fi


### Create "redirect" artifact

# This is just a page that gets picked up by the build, and makes it easier to
# reach the gallery if you're on the buildkite.com page instead of the GitHub PR.
section "Create redirect-to-gallery.html artifact"
cat > "redirect-to-gallery.html" <<-EOF
  <meta http-equiv="refresh" content="0;url=${gallery_index_url}" />
EOF
buildkite-agent artifact upload "redirect-to-gallery.html"


### Post-build notifications

# Post a GitHub Status to the system-tests with the preview.
post_status_to_current_github_pr "success" "$gallery_index_url" "Screenshot gallery"

# Post a GitHub Status to the Murmur PR that kicked off this build, if applicable.
post_status_to_triggering_github_pr "success" "$gallery_index_url" "Screenshot gallery"
