# Galaxy XR AV1 experimental candidate

This untested Android VR adaptation uses the standard APK bundled with the inspected SteamVR installation: Steam Link VR **2.0.24**, version code **5002389**. It has not been installed or streamed on a Galaxy XR. It bypasses the Steam Frame companion, dongle, SSH and kernel module.

## Changes and evidence

The recipe checks the entire original APK and AArch64 `libvrlink_scene.so` SHA256, then changes its unique `video/hevc` MIME selector to `video/av01`. Four bytes change; string length and executable instructions stay intact. Both `AMediaCodec_createDecoderByType` and MediaFormat MIME reference it in `QSVLCodecNDK::Init`. `SubmitFrameForDecode` queues encoded payloads through MediaCodec. This supports a test candidate, not proof of a working stream or AV1 renderer.

The separate Remote Play decoder is untouched. Every other APK application entry is preserved. Repacking removes original signatures; align and sign the candidate with a local key. No Valve APK, native library or signing key is committed to this repository. Unknown APK fingerprints are refused.

The separate PC launcher requests 25-500 Mbps AV1 at 72/90/120 Hz. Packed image remains limited to 1536x6144 by the current adapter. Above 480 Mbps selects level 6.2/high tier; hardware acceptance is unverified. The normal Frame GUI still supports 90/120 Hz and does not launch this Android session.

## Try the candidate

1. Keep the original `SteamVR\drivers\vrlink\resources\android-steamlinkvr-release.apk` for rollback. Disconnect the headset stream and close PC SteamVR and the settings app.
2. Install the signed experimental APK using your usual headset APK installer. It keeps package name `com.valvesoftware.steamlinkvr` but has a different signing certificate. Android may require uninstalling the original first, which removes saved pairing/settings. Pair again afterward. This APK expects AV1; do not connect it to a stock HEVC stream.
3. Extract the PC candidate ZIP, including `Backend`, and use **PowerShell 7**:

   ```powershell
   pwsh -File .\Start-GalaxyAv1.ps1 -Mbps 100 -Fps 72
   ```

4. Wait for the PC adapter installed message, then connect the patched APK. Start at 100 Mbps. Only raise the target after checking picture, decoded frame rate, latency and errors. `-Mbps 500` requests that budget without guaranteeing throughput. Do not use the Frame GUI codec switcher for this session.
5. The launcher verifies fresh PC AV1 counters and identity, not headset decode. Failed connection, black picture or decoder errors require more investigation and restoration.

The launcher keeps an exact settings backup/receipt before editing PC settings. It does not patch the installed PC driver on disk. The adapter lasts only for the running vrserver process. Settings remain until restored. A failure after starting SteamVR requires closing SteamVR and running Restore.

## Restore

Disconnect and close PC SteamVR, then run:

```powershell
pwsh -File .\Start-GalaxyAv1.ps1 -Mode Restore
```

Restore verifies the original backup and refuses to overwrite settings edited since the trial. In that case merge manually from the backup path in the error. Reinstall Valve's original APK, removing the experimental APK first if signatures differ. Restart SteamVR without the launcher to use the stock PC encoder.

## Reproduce

```powershell
python Android\prepare_av1_apk.py ORIGINAL.apk candidate-unsigned.apk
zipalign -p 4 candidate-unsigned.apk candidate-aligned.apk
apksigner sign --ks YOUR_LOCAL_KEYSTORE --out candidate-signed.apk candidate-aligned.apk
apksigner verify --verbose candidate-signed.apk
```

Build the updated adapter with `Native\AV1Lab\build.ps1 -OutputDirectory artifacts\CodecLab\Backend`. Later APK builds require fresh inspection, not a guessed patch. CI checks the recipe, restoration/refusal behavior and native compilation; no headset acceptance is implied.
