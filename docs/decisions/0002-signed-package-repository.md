# 0002: Signed project package repository

## Status

Accepted.

## Context

The optional Marble profile needs reviewed native packages and update behavior. Client authorization
cannot depend on CI output, mutable upstream content or transport security alone.

## Decision

The required release build runs once in a clean environment under an unprivileged builder and is
independently read back before signing. A separate A+B byte comparison remains advisory. Signing
runs only in an isolated no-network boundary: the authorized Release `snapshot`/`finalize` jobs or
the separately authorized host recovery launcher. A minimized public certificate bootstraps
one certification primary and one approved signing subkey. Pacman requires package and database
signatures with `TrustedOnly`. GitHub Pages deploys only a verified signed immutable snapshot.

## Consequences

Build artifacts remain unsigned inputs and cannot authorize installation. Only the two Release
signing jobs receive the signing-only subkey; other jobs have no signing authority. Package changes
require exact source checksums, payload allowlists, reviewed signing, strict-client acceptance and
immutable release assets. Publication stops if mandatory signing or verification gates fail.
The [release process](../release-process.md) defines the current 14/18-file acceptance boundaries.
