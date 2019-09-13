# GPII Version Updater

This repo contains a Docker image for tracking components to be deployed to GPII infrastructure. It works as a bridge between the independent CI projects that build, test, and upload Docker images (e.g. [GPII universal](https://github.com/GPII/universal/)) and the [gpii-infra repo](https://github.com/gpii-ops/gpii-infra/), which manages the infrastructure for operating and deploying GPII components.

For more about the general CI/CD picture, see [Continuous Integration / Continuous Delivery in gpii-infra](https://github.com/gpii-ops/gpii-infra/blob/master/CI-CD.md).

This module contains:
* `Rakefile`, the primary entry point.
* `sync_images.rb`, which calculates the latest sha256 for each component, uploads the image to our production Google Container Registry, and writes `shared/versions.yml` in the [gpii-infra repo](https://github.com/gpii-ops/gpii-infra/).
* `sync_images_wrapper`, a script that runs `sync_images` in a loop, committing and pushing `shared/versions.yml` if it changes.
   * This requires commit and push privileges on `gpii-infra`. These privileges are provided via an ssh key and some configuration of [Github](https://github.com/gpii-ops/gpii-infra/blob/master/CI-CD.md#configure-github).
* `Dockerfile`, to build a Docker image that runs `sync_images_wrapper`.
   * A container based on this Docker image is deployed to `i46` and managed by an [Ansible role](https://github.com/idi-ops/ansible-gpii-version-updater) and a [wrapper playbook](https://github.com/inclusive-design/ops/blob/master/ansible/config_host_gpii_version_updater.yml).

## Installing on host

1. Follow the [gpii-infra instructions for installing packages.](https://github.com/gpii-ops/gpii-infra/blob/master/gcp/README.md#install-packages).
1. Install the `bundler` gem, e.g. with `gem install bundler` or with your system's package manager.
1. Clone this repo.
1. `cd gpii-version-updater`
1. `rake install`
   * To clean up: `rake uninstall`

## Running on host

* `rake sync` to run `sync_images.rb`
   * You can override some defaults: `rake sync"[./my_versions.yml, gcr.io/gpii2test-common-stg]"`
* `rake clean_cache` to destroy the Docker `/var/lib/docker` cache volume. The volume and cache will be re-created on the next run.
* `rake test` to run unit tests

## Running in a container

This workflow is a little cumbersome and is probably best for debugging version-udpater itself.

1. `docker pull gpii/version-updater`
1. Run the container in interactive mode: `docker run --privileged --rm -it -v version-updater-docker-cache:/var/lib/docker gpii/version-updater sh`
   * If you want to read and write the versions.yml automatically (e.g. by running `sync_images_wrapper`), you must provide a directory containing a `id_rsa.gpii-ci` usable for pulling and pushing to the gpii-infra repo.
      * Add to the command line: `-v $(pwd)/fake-gpii-ci-ssh:/root/.ssh:ro,Z`
   * If you want to upload images (i.e. `push_to_gcr` is set to `true` -- this is the default for `sync_images_wrapper`), you must provide credentials with write access to the production GCR instance (or to the GCR instance you specified).
      * Add to the command line: `-v $(pwd)/creds.json:/home/app/creds.json:ro,Z`
   * Omit `version-updater-docker-cache` if you want to re-pull the Docker images whenever you restart the container. Otherwise, clean up afterwards with `rake clean_cache`.
1. Inside the container, start dockerd in the background: `dockerd &`
1. `rake sync"[/path/to/versions.yml]"`, etc.

## Generating `shared/versions.yml` manually

`sync_images` can be useful for local GPII development. See [gpii-infra: I want to test my local changes to GPII components in my cluster](https://github.com/gpii-ops/gpii-infra/blob/master/gcp/README.md#i-want-to-test-my-local-changes-to-gpii-components-in-my-cluster).

## Adding or modifying a component

`sync_images` reads a specified `versions.yml` file.

Each top-level key is a `component`. The component's name is arbitrary, but should correlate with a gpii-infra module since gpii-infra will populate environment variables like `TF_VAR_<component_name>_(repository|tag|sha)` based on data under the component key in `versions.yml`.

`sync_images` pulls the image specified by the component's `upstream.image` and `upstream.tag` keys, optionally processes the image further (e.g. pushing it to GCR), then populates the component's `generated` key with caluclated values.

### To add a new component

1. Add a new top-level key, `my_component`.
   * Use `snake_case`, not `kebab-case`.
1. Add a key underneath `my_component` called `repository`. Its value is the upstream location of the image, e.g. `mrtyler/universal` or `couchdb`.
1. Add a key underneath `my_component` called `tag`. Its value is the tag on the upstream repository, e.g. `latest` or `2.3`.
1. `rake sync"[/path/to/gpii-infra/shared/versions.yml, my_component]"`
   * `desired_components` (the `my_component` arg) accepts multiple, pipe-separated values: `flowmanager|preferences|dataloader`
1. Review the changes made to `versions.yml` and commit.

### To modify a component

1. Find the component, e.g. `your_component`.
1. Modify `repository` and `tag`.
1. Ignore everything under `generated`; it will be re-generated.
1. `rake sync"[/path/to/gpii-infra/shared/versions.yml, your_component]"`
1. Review the changes made to `versions.yml` and commit.

## Clearing the cache
1. For local development: `rake clean_cache`
1. For the production instance on i46: this machine does not provide a helpful development environment (no rake, no git) so it may be easier to:
   * `docker kill` the running `version-updater` container
   * Manually run the commands in the Rakefile's `task :clean_cache`
