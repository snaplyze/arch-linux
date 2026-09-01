# 0002: Signed project package repository

## Status

Accepted.

## Context

The optional Marble profile needs reviewed native packages and update behavior. Client authorization
cannot depend on CI output, mutable upstream content or transport security alone.

## Decision

Project packages are built reproducibly twice in clean environments, compared byte-for-byte and
signed only in a separate network-disabled environment. A minimized public certificate bootstraps
one certification primary and one approved signing subkey. Pacman requires package and database
signatures with `TrustedOnly`. GitHub Pages deploys only a verified signed immutable snapshot.

## Consequences

CI artifacts remain unsigned inputs and cannot authorize installation. Package changes require exact
source checksums, payload allowlists, offline review/signing, strict-client acceptance and immutable
release assets. Publication stops if signing, backup or public readback gates cannot be proved.
