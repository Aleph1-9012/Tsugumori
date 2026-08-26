# Quickshare

Open the Control Center with `SUPER + Tab`, then select **Quickshare**.

## Send a file

Send mode opens Yazi so you can choose a file. Quickshare then creates a local
download link and QR code. A temporary Cloudflare tunnel can be used when the
other device is not on the same local network.

The request-header deadline is 15 seconds and the download deadline is five
minutes by default. Advanced users can change the download deadline with
`qshare send --transfer-timeout SECONDS`.

## Receive files

Receive mode displays a QR code. Scanning it opens Tsugumori's upload page on
the other device.

The default limits are:

- 1 GiB per request
- 4 GiB for the complete session
- 32 files per request
- 128 files per session
- 16 active connections
- 15 seconds to finish request headers
- Five minutes for an upload

Run `qshare recv --help` to see the flags that change these limits.

## Safety

Local transfers use HTTP and should only be used on a trusted network. Tunnel
mode uses HTTPS, but its temporary URL acts as a bearer token: anyone with the
URL can use it while the session is active.
