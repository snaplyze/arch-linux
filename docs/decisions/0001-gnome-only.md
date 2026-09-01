# 0001: GNOME-only graphical product

## Status

Accepted.

## Context

A disk installer needs one coherent graphical package, display-manager, session, defaults and
acceptance contract. Multiple desktop paths multiply destructive-install and post-update states and
make runtime proof less reliable.

## Decision

GNOME with GDM and Wayland is the only graphical environment. Minimal TTY is the supported
non-graphical choice. Ptyxis is the desktop terminal, and the Fish plus Starship enhancement is one
optional fixed bundle. Stock GNOME is always the first and default appearance.

## Consequences

Desktop code, configuration and tests use one explicit graphical path. Any change to the supported
desktop, display manager or terminal contract requires a new architecture decision and a complete
safety and QEMU acceptance design; it is not an incremental package addition.
