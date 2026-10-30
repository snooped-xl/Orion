# Orion Privacy Policy

**Last updated: October 30, 2026**

Orion is a desktop application. Orion does not operate an account system or a
telemetry/analytics service, and Orion does not collect, receive, or sell your
personal data. Orion does not send your workspace, scripts, settings, crash
reports, or device identifiers to Orion or its maintainers.

## Data stored on your device

Orion stores its workspace locally: scripts and other files you open or save,
editor tabs and recovery state, preferences, themes, and related workspace
metadata. By default, the workspace is `~/orion` on Linux and your actual
Documents folder's `orion` directory on Windows. Orion also uses application
support/cache directories for application-specific local data. The workspace
can be removed by you from your file manager; deleting it removes its contents,
so keep your own backups if needed. Orion does not promise that local files are
encrypted.

On Linux and Windows, optional crash capture is **off by default**. If you turn
it on, Orion writes sanitized error details to a local application-support
file. It does not upload that report. You can review it in Settings and choose
to open a prefilled GitHub issue draft; Orion opens the draft only after your
confirmation. You decide whether to submit it. GitHub may receive the report,
network metadata, and account information when you visit or submit there, under
[GitHub's privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-privacy-statement).
Turning crash capture off removes Orion's stored consent marker and pending
crash report.

## Network connections

Orion has no automatic analytics, advertising, or telemetry requests. Network
access is limited to application distribution/runtime services and these
product features (some of which Orion starts automatically):

- Script Hub sends HTTPS requests for listings and script source to
  RobloxScripts (`robloxscripts.com`), ScriptBlox (`scriptblox.com`), HaxHell
  (`haxhell.com`), and Rscripts (`rscripts.net`). Search may start when the app
  opens and can request all four providers unless you select one. Search terms
  and pagination parameters are included when relevant. The provider receives
  the connection and may observe your IP address, request time, requested
  content, and ordinary network metadata under its own privacy practices.
- **Orion does not spoof Script Hub API requests.** It identifies requests
  with the application User-Agent `Orbit/1.0 ScriptHub`, requests JSON, and
  sends the provider homepage as the Referer. It does not forge browser headers,
  rotate User-Agent values, or impersonate a user's device, account, browser,
  or another client. Orion does not add a hardware ID, MAC
  address, advertising ID, or Orion account identifier to Script Hub requests.
  Network infrastructure and the provider can still see ordinary connection
  information such as your public IP address; Orion does not mask or proxy it.
- Script thumbnails and images may be loaded from the image hosts supplied by
  those script providers. Loading an image connects your device to that host.
- When you load a raw script URL or open a provider page, Orion connects to
  the destination you selected. Review third-party code before using it; Orion
  is not responsible for the destination's data practices.
- Orion Bridge and optional Relapse support communicate with software on your
  own device over loopback or a local Unix socket. If you execute a script,
  Orion sends it to the client or local Relapse session you selected; that is
  local device-to-device communication, not a request to Orion's maintainers.
- Downloading Orion or its Linux Flatpak runtime, checking releases, opening
  links, or choosing to review/submit a crash report involves the relevant
  distribution, hosting, desktop, or GitHub services. Those services have
  their own privacy policies.

Remote script providers and other services are independent third parties. Orion
does not control what they log, how long they retain request data, or how they
use it. Using their services is subject to their terms and privacy policies.

## Your choices

You can use Orion's editor and local workspace offline. Remote search requires
network access; crash capture is optional and local; external links and issue
submission require your action. You can restrict Orion's network access using
your operating system or network firewall, noting that remote search and
release downloads will then be unavailable.

## Changes and contact

This policy may be updated when Orion's behavior changes. The current version
is maintained in the [Orion source repository](https://github.com/snooped-xl/Orion).
For privacy questions or corrections, open an issue in the repository. Do not
include private workspace files, scripts, crash reports, or other sensitive
data unless you have reviewed them and intentionally choose to share them.
