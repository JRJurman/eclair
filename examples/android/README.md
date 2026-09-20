# android/

The Android test harness.

This is intended to run on a connected device, and provides controls for triggering the different API methods. Note - this uses `harness.c` to call the c methods. There is no native java API.

## Building

```sh
./examples/android/build.sh          # build only
./examples/android/build.sh --run    # build, install and launch
./examples/android/build.sh --abi=x86_64
```
