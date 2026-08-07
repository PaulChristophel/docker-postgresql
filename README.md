# PostgreSQL images for CloudNativePG

This repository builds PostgreSQL standard images from upstream source for use
with [CloudNativePG](https://cloudnative-pg.io/). Each PostgreSQL release is
built on five maintained Linux distributions, providing a practical range of
compiler and system-library versions without relying on Linux releases that
are already near the end of their support life.

Published images are available from
[`docker.io/pcm0/postgres`](https://hub.docker.com/r/pcm0/postgres).

## Motivation

The primary goal is to build and test PostgreSQL with a diverse set of GCC
toolchains while keeping every resulting image on an operating system that can
reasonably be maintained.

One way to obtain different GCC versions would be to use consecutive Fedora
releases—for example, Fedora 44 and Fedora 43. That creates unnecessary
maintenance churn: the older Fedora release reaches end of service sooner, so
the image must be rebased simply to retain operating-system support. Using
current releases from different distribution families provides compiler,
library, and packaging diversity while giving the longer-lived distributions
useful maintenance horizons.

The current bases are:

- Fedora 44, representing a fast-moving distribution and newer toolchain.
- Photon OS 5, representing VMware's compact, container-oriented distribution.
- Rocky Linux 10 and AlmaLinux 10, representing enterprise Linux toolchains
  and lifecycles.
- Azure Linux 3, representing Microsoft's compact container-focused
  distribution.

This is useful both for finding compiler-sensitive PostgreSQL problems and for
offering operators a choice of supported base environments. It is not intended
to make the images byte-for-byte identical; the common contract is the
PostgreSQL feature set and CloudNativePG compatibility.

## Image matrix

The release workflow currently builds 60 images: six PostgreSQL release lines
across five operating systems, each with standard and untrusted variants.

- PostgreSQL 14 through 18 are published through the stable catalogs.
- PostgreSQL 19 beta releases are published through separate preview catalogs.
- Each OS has a standard variant and a corresponding `-untrusted` variant.
- Images currently target `linux/amd64`.

`images.json` is the source of truth for PostgreSQL versions, source checksums,
extension revisions, image variants, and stable or preview channel assignment.

## Included features

PostgreSQL is compiled from the official upstream source archive rather than
installed from a distribution PostgreSQL package. Every build runs the
PostgreSQL `check-world` test suite and an image-level smoke test.

The final images are assembled `FROM scratch`. Their runtime filesystems are
created by the selected distribution's package manager, including the resolved
dependency closure, CA certificates, time-zone data, OS identity, and RPM
database. PostgreSQL and its extensions are then copied from their build
stages. This keeps the runtime images focused while preserving the package
metadata used by vulnerability scanners.

The images include the capabilities expected from a CloudNativePG standard
image, including:

- ICU, LDAP, GSSAPI, PAM, OpenSSL, XML, XSLT, LLVM, LZ4, Zstandard, and
  `uuid-ossp` support;
- `pg_cron`;
- `pgvector`;
- `pgaudit`;
- the full set of PostgreSQL programs installed by `install-world-bin`.

PostgreSQL 18 and later are additionally built with libcurl integration.
Fedora, Rocky Linux, AlmaLinux, and Azure Linux also enable liburing; Photon OS
does not currently provide it.

The default variants deliberately omit the Perl, Python, and Tcl runtimes and
their untrusted procedural languages. Tags ending in `-untrusted` add
`plperl`, `plpython3u`, and `pltcl` for workloads that require them.

## Tags

Tags combine a PostgreSQL version with the image variant. For example:

```text
18.4-standard-photon5
18-standard-fedora44
18-standard-rocky10-untrusted
```

Full-version tags identify a particular PostgreSQL release. Major-version tags
move when a new minor release is published. The `latest` tag follows the
current PostgreSQL 18 Photon OS standard image.

For production deployments, prefer the immutable digests recorded in the
CloudNativePG catalogs under `image-catalogs/`.

## Using a catalog with CloudNativePG

Apply the catalog for the desired OS and trust profile:

```sh
/opt/homebrew/bin/kubectl apply \
  -f image-catalogs/catalog-standard-photon5.yaml
```

Reference it from a CloudNativePG cluster by catalog name and PostgreSQL major
version:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres
spec:
  instances: 3
  imageCatalogRef:
    apiGroup: postgresql.cnpg.io
    kind: ClusterImageCatalog
    major: 18
    name: postgresql-standard-photon5
```

Preview catalogs have names ending in `-preview` and should be treated as
preproduction images. Select the matching `-untrusted` catalog only when the
cluster requires Perl, Python, or Tcl untrusted procedural languages.

## Building locally

The Dockerfiles accept the same build arguments used by the release workflow.
Their defaults currently build PostgreSQL 18.4 with pg_cron 1.6.7, pgvector
0.8.6, and pgAudit 18.0. For a local Photon build using those defaults:

```sh
/opt/homebrew/bin/podman build \
  --platform linux/amd64 \
  -f photon.dockerfile \
  -t localhost/postgres:standard-photon5 .
```

Use another distribution's Dockerfile to build its corresponding variant. Add
`--build-arg WITH_UNTRUSTED_LANGUAGES=true` for an untrusted-language image.

## Release process

The GitHub Actions release workflow runs for relevant changes on `main`, every
Monday, and on manual dispatch. It expands `images.json` into a PostgreSQL ×
image-variant build matrix, then builds and publishes every image to Docker
Hub. Each publication includes a BuildKit SBOM and a separate GitHub-generated
provenance attestation.

After every matrix build succeeds, the workflow records the registry digests,
regenerates the CloudNativePG catalogs with immutable image references, and
opens an automatically merged catalog update pull request.

Base images and downloaded source archives are digest- or checksum-pinned.
Updating a PostgreSQL release, extension revision, or image variant should
therefore begin in `images.json`; base-image updates belong in the relevant
Dockerfile.
