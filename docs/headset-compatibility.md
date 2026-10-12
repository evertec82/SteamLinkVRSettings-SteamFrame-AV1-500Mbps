# Headset compatibility

The experimental 25-500 Mbps AV1 option in this fork is for the supported Steam Frame build only. It is a requested encoder budget, not verified 500 Mbps throughput.

The PC bitrate and settings controls may apply to other headsets using Valve's `driver_vrlink`, subject to the installed driver and client. The paired AV1/H.264 session is different: it requires the dedicated Frame dongle, SteamOS Devkit SSH pairing, the exact Frame client fingerprint, and the matching Linux kernel decoder module. It does not negotiate AV1 with Android Steam Link clients.

## Galaxy XR

Samsung lists AV1 among Galaxy XR's supported codecs, but that does not demonstrate Steam Link VR's AV1 receiver support. This fork does not currently enable AV1 on Galaxy XR, Quest, PICO, or HTC headsets. The Frame kernel module and client patch cannot be installed on Galaxy XR's Android client.

A Galaxy XR port needs the exact Steam Link APK version (and source or patch project when available), its codec negotiation/packet format, and an Android AV1 receiver using MediaCodec. The receiver must support the stream's resolution, profile, level and rate. Host refresh-rate and packed-image restrictions also need to match the Galaxy XR client rather than reuse Frame's 90/120 Hz and 1536x6144 assumptions. End-to-end validation needs hardware tests with encoder output, decoded frames, latency and decoder faults measured together.

References:
- [Samsung Galaxy XR specifications](https://news.samsung.com/us/introducing-galaxy-xr-opening-new-worlds/)
- [Frame codec requirements](codec-modes.md)

The Windows CI workflow builds the PC adapter and runs software regression tests. It does not test a headset or supply a complete codec-enabled app release.
