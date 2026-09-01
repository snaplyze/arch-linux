# 0003: Process-scoped experimental GDM overlay

## Status

Accepted.

## Context

GDM uses GNOME Shell resources and vendor policy shared with package updates. Replacing those files
would cross package ownership, weaken upgrades and risk the login path.

## Decision

Experimental Marble GDM is separately confirmed and uses a project-owned GLib resource overlay plus
an absolute project-owned dconf profile only for the exact GDM Shell service. Activation requires
reviewed GNOME/resource hashes and trusted path ownership. Stock resources and vendor dconf remain
the lower layers; administrator policy wins. No installer or hook restarts GDM.

## Consequences

The feature owns no distribution Shell resource, GDM/PAM file, persistent GDM user state or other
package path. Unknown or changed inputs keep Stock without blocking system updates. Package hooks
must safely remove exact project activation before relevant transactions and revalidate afterward.
