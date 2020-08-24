Screenshot Gallery Buildkite Plugin
===================================

A [Buildkite plugin](https://buildkite.com/docs/agent/plugins) that collects screenshots from a build, and makes it available as a gallery HTML+images bundle viewable from the triggering pull request and Buildkite build, with comparisons to screenshots from previous builds.

This relies on a little bit of setup, mostly an `aws-assume-role`, and some parameters to tell the plugin how to identify the screenshots and where to upload the screenshots to.


Example
-------

```yml
steps:
  - name: "Publish the screenshot gallery"
    plugins:
      - cultureamp/aws-assume-role#v0.1.0:
          role: "arn:aws:iam::123456789012:role/example/build/role/for/uploading"
      - cultureamp/screenshot-gallery:
          canonical_repo_and_branch: "murmur/master"
          bucket_name: "example-screenshot-gallery"
          base_url: "http://s3.amazonaws.com/example-screenshot-gallery"
          github_org: "cultureamp"
          github_repo: "example-repo"
          screenshot_pattern: "screenshot_*.png"
    # ... and other config fields as usual, eg. agents.
```

If your gallery is being triggered by a another pipeline's build (eg. murmur triggering a build of 'example-repo', with example-repo's build generating a gallery via this plugin), then the triggering build (eg. murmur) will need to provide a couple of environment variables so we know what branch and commit SHA it's for, eg.

In the triggering pipeline (the one that kicks off the second build):

```yml
  - trigger: "example-repo"
    label: "Kick off the example-repo sub-build"
    async: true
    build:
      message: "$BUILDKITE_MESSAGE"
      env:
        BUILDKITE_TRIGGERED_FROM_COMMIT: "$BUILDKITE_COMMIT"
        BUILDKITE_TRIGGERED_FROM_BRANCH: "$BUILDKITE_BRANCH"
        BUILDKITE_TRIGGERED_FROM_GITHUB_ORG: "cultureamp"
        BUILDKITE_TRIGGERED_FROM_GITHUB_REPO: "murmur"
```

Options
-------

See [plugin.yml](./plugin.yml) for a description of all options.

Environment
-----------

In order to have access to AWS S3 to upload+download screenshots, the `AWS_...` environment variables provided by [aws-assume-role](https://github.com/cultureamp/aws-assume-role-buildkite-plugin) must be available.

To have GitHub statuses appear on builds, either `GITHUB_ACCESS_TOKEN` (API token) or `GITHUB_ACCESS_TOKEN_PARAM_PATH` (the Parameter Store path that will contain the API token, eg. `/visual-tests/GITHUB_ACCESS_TOKEN`) need to be set.

To have the build correctly handle the case where it is triggered by another repository's build (eg. murmur build triggering example-repo's test+screenshot steps), the following variables must be set: `BUILDKITE_TRIGGERED_FROM_GITHUB_ORG`, `BUILDKITE_TRIGGERED_FROM_GITHUB_REPO`, `BUILDKITE_TRIGGERED_FROM_COMMIT`, `BUILDKITE_TRIGGERED_FROM_BRANCH`. (See the [example](#example) at the top of the README.)


Development
-----------

Tests are written using bats with bats-mock and a docker compose file is provided to simplify testing.

To run tests: `docker-compose run tests`


License
-------

MIT (see [LICENSE](LICENSE))
