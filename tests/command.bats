#!/usr/bin/env bats

load "$BATS_PATH/load.bash"

@test "is a dummy test" {
  export BUILDKITE_BUILD_NUMBER="123"
  export BUILDKITE_PLUGIN_SCREENSHOT_GALLERY_BUCKET_NAME="example_bucket_name"
  # ... etc.

  # stub aws "s3 ls s3://example_bucket_name/my_repo/my_branch/gallery.html"
  #
  # run "$PWD/hooks/command"
  #
  # assert_output --partial "..."
  # assert_success
  # unstub aws

  echo "TODO"
  assert_success
}
