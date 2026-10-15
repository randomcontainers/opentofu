# opentofu

Container images with [OpenTofu](https://opentofu.org/), an open-source infrastructure as code tool. Its command, `tofu`, reads configuration written in the OpenTofu language, works out the changes needed to bring cloud resources and other infrastructure in line with it, and applies them through providers. `tofu` is compiled from the release tag with a current Go release on Ubuntu and Alpine, for `linux/amd64` and `linux/arm64`. The images are rebuilt when OpenTofu publishes a release, when the pinned Go release is raised and when the base image changes. The default image adds Git, which `tofu init` needs for modules from the OpenTofu registry and from Git repositories, and the OpenSSH client for Git over SSH.

This is an unofficial build, not affiliated with or endorsed by the OpenTofu project or the Linux Foundation. Report problems with the image in this repository and problems with OpenTofu itself [upstream](https://github.com/opentofu/opentofu/issues).

## Quick start

Save this as `main.tf`:

```hcl
terraform {
  required_providers {
    random = {
      source = "hashicorp/random"
    }
  }
}

resource "random_pet" "name" {}

output "name" {
  value = random_pet.name.id
}
```

Download the provider, look at the plan, then apply it:

```sh
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/work" ghcr.io/randomcontainers/opentofu init
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/work" ghcr.io/randomcontainers/opentofu plan
docker run --rm -it --user "$(id -u):$(id -g)" -v "$PWD:/work" ghcr.io/randomcontainers/opentofu apply
```

`tofu apply` asks for confirmation, hence `-it`; in CI pass `-auto-approve` instead, or apply a saved plan. `init` writes the provider to `.terraform/` and its checksums to `.terraform.lock.hcl`, and `apply` writes the state to `terraform.tfstate`, all in your directory. Commit the lock file, not `.terraform/`. A few more commands:

```sh
# Save a plan and apply exactly that plan
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/work" ghcr.io/randomcontainers/opentofu \
  plan -input=false -out=tfplan
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/work" ghcr.io/randomcontainers/opentofu \
  apply -input=false tfplan

# Check the formatting of every file below the current directory
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/work" ghcr.io/randomcontainers/opentofu \
  fmt -check -recursive

# Run the tests in tests/
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/work" ghcr.io/randomcontainers/opentofu test
```

Without arguments the image prints `tofu --help`. In CI, pin a major version tag such as `1` or a digest. A minor version tag such as `1.13` stops getting updates once the next minor release is built (see [Tags](#tags)).

## Credentials and settings

`tofu` and its providers take credentials from environment variables. `-e NAME` without a value passes the variable from your shell:

```sh
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/work" \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN -e AWS_REGION \
  ghcr.io/randomcontainers/opentofu plan
```

In the container `HOME` is not your home directory (it is `/` for a UID without a user in the image), so `~/.tofurc`, the credentials that `tofu login` saves and files such as `~/.aws/credentials` are not there. Mount what you need read-only and point to it:

- `-v "$HOME/.aws:/aws:ro" -e AWS_SHARED_CREDENTIALS_FILE=/aws/credentials -e AWS_CONFIG_FILE=/aws/config` for the AWS provider and the S3 backend.
- `-e TF_CLI_CONFIG_FILE=/work/.tofurc` for a CLI configuration file in your directory, which can set a provider mirror or credentials.
- `-e TF_TOKEN_app_terraform_io`, one variable per host, for the API tokens of private registries and remote backends.

## Providers and the plugin cache

`tofu init` downloads providers from the OpenTofu registry and checks each download against the checksum from the registry and, once `.terraform.lock.hcl` has an entry for it, against the lock file. The images contain no providers. They go into `.terraform/providers` in your directory, so later commands in new containers find them there.

To download each provider version only once for several projects, keep a plugin cache in a volume:

```sh
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/work" \
  -v tofu-plugins:/cache -e TF_PLUGIN_CACHE_DIR=/cache \
  ghcr.io/randomcontainers/opentofu init
```

With a cache, `.terraform/providers` holds links to `/cache`, so mount the same volume at `/cache` for every later command in that directory. Without it the links lead nowhere, and `tofu plan` asks you to run `tofu init` again.

Providers are separate programs that `tofu` starts. Most providers in the registry are static Go binaries, which run on the Alpine images too; a provider that needs glibc runs only on the Ubuntu images.

## Modules and Git

`tofu init` fetches modules from Git repositories by running `git`, and modules from the OpenTofu registry are Git repositories too: the registry points `tofu` to the repository and commit of each module version. The default image has Git and the OpenSSH client, so sources such as `git::https://example.com/infra/modules.git//network?ref=v1.2.0` and `git::ssh://git@github.com/example/modules.git?ref=v1.2.0` work as well. For SSH, pass your ssh-agent and a `known_hosts` file:

```sh
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/work" \
  -v "$SSH_AUTH_SOCK:/agent.sock" -e SSH_AUTH_SOCK=/agent.sock \
  -v "$HOME/.ssh/known_hosts:/ssh/known_hosts:ro" \
  -e GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=/ssh/known_hosts" \
  ghcr.io/randomcontainers/opentofu init
```

On Docker Desktop, mount `/run/host-services/ssh-auth.sock` instead of `$SSH_AUTH_SOCK`.

`ssh` works for any UID given with `--user`; [randomcontainers/openssh-client](https://github.com/randomcontainers/openssh-client) explains how. `slim` has no Git, so there `tofu init` cannot install modules from the registry or from Git; local paths, archives over HTTPS and OCI registries still work.

## What is in the image

| | slim | default |
|---|---|---|
| `tofu` in `/usr/local/bin`, built without cgo, so it is statically linked and loads no libraries | yes | yes |
| Git, for modules from the registry and `git::` sources | no | yes |
| The OpenSSH client (`ssh`, `scp`, `ssh-keygen` and the other client tools), for Git over SSH | no | yes |

Not included: providers, cloud command-line tools such as the AWS CLI or `kubectl`, and Terraform. Git is the distro's `git` package. The OpenSSH client is the [randomcontainers/openssh-client](https://github.com/randomcontainers/openssh-client) build.

The Go version, the commit and every Go module with its version and checksum are in `/usr/local/share/randomcontainers/opentofu/buildinfo`.

## Default or slim

Use the default image (`latest`) for general work: modules from the registry and from Git repositories need Git, and Git over SSH needs `ssh`. `slim` has `tofu` alone. Use it as the base for your own image, or for configurations that use providers and local modules only.

The default image includes Git, which is licensed under the GNU General Public License (GPL-2.0-only). Use `slim` if your policy excludes GPL software. The default image is also published as `ghcr.io/randomcontainers/opentofu-openssh-client`, built in the [opentofu-openssh-client](https://github.com/randomcontainers/opentofu-openssh-client) repository with the same contents and a different digest.

## Tags

`<version>` is an OpenTofu release such as `1.13.1`. `<minor>` and `<major>` are its shorter forms, `1.13` and `1`. They follow the newest release in their series while that series is the newest one. Once 1.14.0 is built, `1.13` stays on the last 1.13 image and is no longer rebuilt: OpenTofu keeps publishing patch releases for older series, and only the newest release is built (see [Updates](#updates)).

| Default (with Git and the OpenSSH client) | Slim | Base |
|---|---|---|
| `latest`, `<version>`, `<minor>`, `<major>` | `slim`, `<version>-slim`, `<minor>-slim`, `<major>-slim` | Ubuntu |
| `ubuntu`, `<version>-ubuntu`, `<minor>-ubuntu`, `<major>-ubuntu` | `slim-ubuntu`, `<version>-slim-ubuntu`, `<minor>-slim-ubuntu`, `<major>-slim-ubuntu` | Ubuntu |
| `<version>-ubuntu26.04` | `<version>-slim-ubuntu26.04` | Ubuntu 26.04 |
| `alpine`, `<version>-alpine`, `<minor>-alpine`, `<major>-alpine` | `slim-alpine`, `<version>-slim-alpine`, `<minor>-slim-alpine`, `<major>-slim-alpine` | Alpine |
| `<version>-alpine3.24` | `<version>-slim-alpine3.24` | Alpine 3.24 |

The images are currently built on Ubuntu 26.04 and Alpine 3.24. Tags without a distro version move to the next distro release when the project does; tags ending in `ubuntu26.04` or `alpine3.24` stay on that release and are no longer rebuilt once the project moves to the next one. Every tag of the current OpenTofu version, including the exact version, is rebuilt in place (see [Updates](#updates)), so pin a digest when you need the same bytes every time.

## Platforms

`linux/amd64` and `linux/arm64`, for both Ubuntu and Alpine. Both are compiled natively on GitHub-hosted runners, without emulation.

## Files and permissions

The working directory is `/work`. The image runs as UID 1000, and any other UID works too: `HOME` is then `/`, and `/cache` can be written by anyone. `tofu` writes nothing there unless you turn on the [plugin cache](#providers-and-the-plugin-cache) with `TF_PLUGIN_CACHE_DIR=/cache`. How to get output files owned by you depends on how you run containers:

| Runtime | Flag |
|---|---|
| Docker on Linux (rootful), GitHub Actions | `--user "$(id -u):$(id -g)"` |
| Rootless Podman | `--userns=keep-id` |
| Rootless Docker | `--user 0:0` (root in the container is your user on the host) |
| Docker Desktop on macOS or Windows | none, file ownership is mapped for you |

`tofu` writes `.terraform/`, `.terraform.lock.hcl`, saved plans and, with the default local backend, `terraform.tfstate` into the working directory. A state file holds every attribute of your resources in plain text, secrets included, unless you configure [state encryption](https://opentofu.org/docs/language/state/encryption/).

## Extending the slim image

Use a `slim` tag as the base for your own image. `slim`, `slim-ubuntu` and `slim-alpine` move to each new OpenTofu release and are rebuilt when the base image changes. Switch to root to install more, then back. This adds `jq`, for reading the output of `tofu output -json` in a pipeline:

```dockerfile
FROM ghcr.io/randomcontainers/opentofu:slim-ubuntu@sha256:...
USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends jq \
 && rm -rf /var/lib/apt/lists/*
USER 1000:1000
```

On Alpine, start from `slim-alpine` and use `apk add --no-cache jq`. The entrypoint is `["tini", "--", "tofu"]`; set your own `ENTRYPOINT` if your image runs something else. To pick up new OpenTofu releases and base image fixes, let Dependabot or Renovate update the digest in your `FROM` line.

Everything the image adds is under `/usr/local`. `/usr/local/share/randomcontainers/opentofu/` holds the version, the source links, the build details, the license files, the MPL-2.0 module sources and `runtime-deps`, the list of distro packages `tofu` needs at run time beyond those in the base image (none).

## Verifying

Each image has a build provenance attestation from this repository's GitHub Actions run, signed by the shared build workflow in `randomcontainers/ci`:

```sh
gh attestation verify oci://ghcr.io/randomcontainers/opentofu:latest \
  --repo randomcontainers/opentofu --signer-repo randomcontainers/ci
```

Images from `ghcr.io/randomcontainers/opentofu-openssh-client` are built in that repository, so verify them with `--repo randomcontainers/opentofu-openssh-client` and the same `--signer-repo`.

Each platform image also carries an SPDX SBOM that lists every distro package with its version:

```sh
docker buildx imagetools inspect ghcr.io/randomcontainers/opentofu:latest --format '{{ json .SBOM }}'
```

OpenTofu publishes prebuilt binaries but no source tarball, and its tags are not signed, so each version is pinned to the commit of its tag. The build clones the `v<version>` tag of [opentofu/opentofu](https://github.com/opentofu/opentofu) and stops unless the tag points to the commit recorded in `package.yml`. The Go toolchain is downloaded from Go's release server (dl.google.com, as linked from go.dev/dl) and checked against the SHA-256 in the Dockerfile, and the Go modules come from the Go module proxy and are checked against OpenTofu's `go.sum`. The binary records the commit it was built from, and `buildinfo` lists it with the Go modules.

## Updates

The project checks the releases of [opentofu/opentofu](https://github.com/opentofu/opentofu/releases) every 15 minutes. A release is picked up once it is 24 hours old; pre-releases are skipped, and so are patch releases of an older series, such as 1.12.8 after 1.13.1. The new version and the commit of its tag are then committed to `package.yml` and the images are rebuilt. Only the newest release is built; tags of older versions stay as they were last built.

The Go toolchain is pinned in the Dockerfiles and raised by hand when Go publishes a security release, and each raise rebuilds the images of the current version. OpenTofu often raises the Go version its `go.mod` requires in a patch release, and such a release does not build until the pin is at least that version.

The images of the current version are also rebuilt when the Ubuntu or Alpine base image changes, the default ones when a new OpenSSH client image is published, and all of them at least every 7 days, so distro security fixes reach the current tags.

## Building

```sh
docker build -f Dockerfile.ubuntu --target slim \
  --build-arg VERSION=<version> \
  --build-arg SOURCE_COMMIT=<commit from package.yml> \
  -t opentofu:local .
```

Use `Dockerfile.alpine` for the Alpine image. `--build-arg JOBS=<n>` limits the number of packages Go builds in parallel. The build downloads a few hundred megabytes of Go modules. The default image is generated from the `combos` entry in `package.yml` by [randomcontainers/ci](https://github.com/randomcontainers/ci).

## Licenses

OpenTofu is released under the [Mozilla Public License 2.0](https://github.com/opentofu/opentofu/blob/main/LICENSE). Its `internal/ipaddr` package holds code from Go's `net` package (BSD-3-Clause). The binary also contains:

- the Go standard library (BSD-3-Clause);
- the Go modules OpenTofu depends on, under Apache-2.0, MIT, BSD-3-Clause, BSD-2-Clause, ISC and MPL-2.0, among them HashiCorp's libraries, OpenTofu's fork of HCL and the OpenBao API client under MPL-2.0;
- the Unicode data in go-textseg versions 15 (Unicode-DFS-2016) and 17 (Unicode-3.0).

The image's license label is `MPL-2.0 AND Apache-2.0 AND MIT AND BSD-3-Clause AND BSD-2-Clause AND ISC AND Unicode-DFS-2016 AND Unicode-3.0`. The license files are in `/usr/local/share/randomcontainers/opentofu/licenses/`, with one directory per Go module. The directory of `github.com/opencontainers/go-digest` also has its `LICENSE.docs` (CC-BY-SA-4.0), which covers go-digest's documentation. The documentation is not compiled into `tofu`, so CC-BY-SA-4.0 is not in the label.

The default image adds Git from Ubuntu or Alpine (GPL-2.0-only) and the OpenSSH client (`SSH-OpenSSH AND MIT`); see [randomcontainers/openssh-client](https://github.com/randomcontainers/openssh-client#licenses) for the OpenSSH sources and license files. Git and the other packages from Ubuntu or Alpine keep their own licenses. The SBOM lists them.

MPL-2.0, and the GPL for Git in the default image, require whoever distributes a binary to make its source available to its recipients. The source code for each image:

- OpenTofu: every version has a GitHub release in this repository, named `v<version>`, with `opentofu-<version>.tar.gz`, an archive of the commit its tag points to. The build applies no patches.
- Go modules under MPL-2.0: the module zips in `/usr/local/share/randomcontainers/opentofu/mpl-sources/`, downloaded from the Go module proxy and checked against `go.sum`. `/usr/local/share/randomcontainers/opentofu/source` lists the OpenTofu commit, these zips and the release.
- Build scripts: this repository at the commit in the image's `org.opencontainers.image.revision` label. The Dockerfiles hold every build flag.
- Ubuntu packages, including Git in the default image: the source packages on [Launchpad](https://launchpad.net/ubuntu) for the versions listed in the SBOM. `apt-get source <package>=<version>` fetches a version that is still in the Ubuntu archive.
- Alpine packages, including Git in the default image: Alpine has no source packages. For the versions listed in the SBOM, the source is the APKBUILD and patches in [aports](https://gitlab.alpinelinux.org/alpine/aports/-/tree/3.24-stable), branch `3.24-stable`, and the archives on [distfiles.alpinelinux.org](https://distfiles.alpinelinux.org/distfiles/v3.24/).

The files in this repository are available under the MIT license, see [LICENSE](LICENSE).

## Requesting a tool

To suggest another tool, use the [Request a tool](https://github.com/randomcontainers/.github/issues/new?template=tool-request.yml) form.
