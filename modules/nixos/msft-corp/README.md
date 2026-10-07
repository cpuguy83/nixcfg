# Corpnet IPv4 routes

`corpnet-vpnc-script` keeps the upstream vpnc-script's tunnel, DNS, VPN-server
route, and IPv6 handling. It invokes `corpnet-vpn hook` for IPv4 split routing.
Both XML sections, incoming server IPv4 split prefixes, and pushed IPv4 DNS
addresses (as managed `/32` includes) are merged and validated before the base
hook receives explicit zero IPv4 split counts. OpenConnect's `INTERNAL_IP4_DNS`
can contain both address families: valid IPv6 entries remain with the base hook
rather than entering the IPv4 policy. The original DNS environment is preserved.

## Import and activation

Keep the VPN disconnected during migration. After installing this configuration,
validate your chosen Azure VPN XML without privileges or writes:

```sh
corpnet-vpn import /path/to/profile.xml --check
```

Import with privileges when ready:

```sh
sudo corpnet-vpn import /path/to/profile.xml
```

The importer reports counts, validates all entries, and atomically replaces
`/etc/msft-vpn/corpnet-routes.json` with a root-owned, mode-0644 versioned policy.
`--output /absolute/path.json` selects a different output for synthetic testing.
Import never activates routes; the next connect or reconnect uses the new file.
Failed validation leaves the previous file intact. Neither private route data
nor profile authentication data belongs in git or the Nix store.

The old `corpnet-routes.txt` remains untouched for rollback, but is never read.
Its old extraction pipeline mixed include and exclude sections; do not reuse it.
Missing or invalid JSON now fails explicitly instead of silently connecting
without the requested route policy.

## Daily automatic refresh

With the Himmelblau stack, `corpnet-profile-update.timer` runs in the configured
user's systemd manager daily, with a two-minute startup catch-up. A real signed-in
user session is required; a lingering user manager alone does not qualify.
A policy imported or refreshed today satisfies that day's refresh. The current
non-lingering user manager starts on login, so missed days are caught up then.
If lingering is enabled later, timer startup no longer follows each login.

The timer requests the fixed system service `corpnet-profile-update.service`.
The download runs as the configured user, using the existing session broker and
Edge client ID to obtain a SharePoint token silently. Only the final validated
policy installation runs as root. Narrow polkit authorization permits that user
to start this one service without a password; it grants no arbitrary commands.

The short link is resolved without credentials. Authorization is sent only to
the expected SharePoint file API, without following redirects. Tokens and the
downloaded XML stay in memory; only route JSON enters the private temporary
runtime directory. Authentication, network, or validation failures are reported
and leave the last installed policy untouched. Background updates never prompt
for sign-in, reconnect the VPN, or modify live routes. The next connection or
reconnection loads the new saved policy.

After activating the system configuration, inspect scheduling and failures with:

```sh
systemctl --user list-timers corpnet-profile-update.timer
journalctl -u corpnet-profile-update.service
```

To request a refresh manually (subject to the same daily freshness check):

```sh
systemctl start corpnet-profile-update.service
```

If silent authentication fails, sign in normally and retry. This integration
depends on tenant policy continuing to permit the broker's Edge/SharePoint token
flow; it does not bypass Conditional Access or manage token caches itself.

## Routing contract

Original prefixes are installed without aggregation or subtraction. Linux
longest-prefix matching applies: a more-specific include wins over a broader
exclusion, and a more-specific exclusion wins over a broader include. Existing
more-specific normal LAN routes remain effective inside broad exclusions.
For exact-prefix conflicts between the downloaded profile and the connected
gateway, the gateway's explicit include/exclude rule wins. Unequal overlapping
prefixes are unchanged and still use longest-prefix matching. Contradictory
rules within the profile or within the gateway's own rules are rejected.
Synthesized DNS host routes do not override remaining explicit `/32` exclusions.
There is no implicit full-tunnel fallback. Explicit full-tunnel `0.0.0.0/0`
includes, including server-pushed defaults, are unsupported: they conflict with
the existing normal default instead of replacing it.

Microsoft documents exclusions as bypassing the VPN, not blocking traffic.
Its documentation does not establish overlapping-prefix precedence in the
closed-source Azure client. This integration's native Linux semantics are an
explicit contract, not a claim of verified Azure client equivalence.

An exclusion uses the most-specific current normal main-table route covering
its entire prefix, then the lowest metric. Gateway, device, source, metric,
scope, and on-link flag are preserved. Connected routes and defaults are supported.
Routes marked `linkdown` or `dead` are not selected as normal next hops; those
informational flags are ignored when matching ownership for cleanup.
Unsupported fields or flags (including multipath routes), ambiguous next hops,
or missing covering routes fail with entry/route ordinals rather than guessing
or logging private prefixes. Policy routing outside the IPv4 main table is not
managed. IPv6 retains upstream behavior and is not covered by this ownership
mechanism.

## Ownership and recovery

Only one corpnet connection is supported. A root-owned mode-0700 `/run/msft-vpn`
directory holds the session lock and mode-0600 recovery state. The hook requires
a valid, live **supplied `VPNPID`** and `TUNDEV`; it does not guess the VPN process
from its parent. Older clients that omit `VPNPID` need to supply it correctly
before using this hook. Ownership includes the process start time and boot ID
to distinguish reused PIDs.

Routes are added, never replaced. An equivalent preexisting exact route is
borrowed without ownership; an incompatible exact route fails before managed
route mutation. Protocol **242** is reserved for this integration in the IPv4
main table; an unrecorded route using it is a collision and prevents installation.
Do not assign that protocol to other software.

The controller snapshots normal routes before calling the base connect or
reconnect hook, excluding the tunnel and protocol 242. Reconnect refreshes
exclusion next hops after ordinary network, gateway, or source changes. State is
written before bounded route batches, and installation is verified. New
exclusions are installed before includes; obsolete includes are removed before
obsolete exclusions. Old exceptions remain until the new policy is installed
unless an exact-prefix replacement requires their earlier removal.

Failures roll back managed changes; rollback failures are reported separately
and retain recovery state. On the next connect/reconnect, an interrupted
transaction is recovered by cleaning only its still-matching recorded routes,
then reconciling against a fresh normal baseline, not reinstalling obsolete
gateways. Recovery failures remain explicit and retain ownership records.
Failed initial connects always invoke base disconnect cleanup, even if managed
rollback fails, preserving the original error or exit status. Reconnect failures
do not tear down upstream tunnel/DNS configuration.

Disconnect does not read the policy file and removes only recorded exact routes
that still match. Foreign replacements are preserved. Base cleanup runs even
when custom cleanup or state validation fails. The shared services' `ExecStopPost`
also runs `corpnet-vpn cleanup` while retaining the existing indicator hook.
This command removes a dead owner's routes, including pending additions after
an interrupted batch, but refuses to clean a live owner. It can also be run
manually as root after the VPN process has exited. Invalid state is reported
and retained for inspection, never replaced with broad route deletion.

## Implementation and synthetic tests

`corpnet-vpn` is one executable with `import`, `hook`, `cleanup`, `eligible`,
`fetch`, and `install` subcommands. All Go source and tests live in one
root-level `package main` in the standard-library-only `packages/corpnet-vpn`
module. No legacy command aliases are installed.

Existing version-1 policy and recovery JSON remains readable without reimport
or migration. The Nix wrapper supplies the configured desktop user and base
vpnc-script path, supplies the UPN when Himmelblau is enabled, and provides
`ip`, `busctl`, and `loginctl` on PATH. Intune-only route configuration does not
require a broker UPN.
The internal vpnc shell adapter invokes `corpnet-vpn hook`; system services use
the same command's `cleanup`, `eligible`, `fetch`, and `install` subcommands.
Existing service/timer names and policy/runtime paths remain unchanged.

No VPN, network login, privileges, or real profile is needed:

```sh
export TMPDIR="$(mktemp -d "$TMPDIR/nixcfg-corpnet-tests.XXXXXX")"
export GOCACHE="$TMPDIR/go-cache"
cd packages/corpnet-vpn
go test ./...
go vet ./...
go build -o "$TMPDIR/corpnet-vpn" .
```

Tests use disposable Go test directories, mock kernel and broker operations,
and use documentation-only prefixes and synthetic profiles. No authentication
or profile download occurs. The Nix package also runs `go test ./...` before
installing the single `corpnet-vpn` executable.
