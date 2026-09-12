# Honest Face ID

A native macOS SwiftUI demonstration of a Face ID-inspired flow that is explicit
about its limits. It detects face rectangles with Vision to guide positioning,
then hands identity confirmation to `LocalAuthentication`; it never performs
face recognition or stores camera frames.

## Run

```sh
swift test
swift run
```

When packaging this executable in Xcode, add `NSCameraUsageDescription` to the
target's Info settings (the app also explains camera privacy in its UI).

The engine uses a generation token to ignore late camera/Vision/authentication
callbacks after a session stops or restarts. The camera stream is in-memory only.
The Settings sheet includes a reduce-motion preference and the interface uses
accessibility labels and frequent-update traits for status changes.
