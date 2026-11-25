#!/usr/bin/env python3
"""Test Flutter's device JSON for a mobile platform without relying on spacing."""

import argparse
import json
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("platform", choices=("android", "ios", "mobile"))
    args = parser.parse_args()
    try:
        devices = json.load(sys.stdin)
        if not isinstance(devices, list) or any(
            not isinstance(device, dict) for device in devices
        ):
            raise ValueError("expected a list of device objects")
    except (ValueError, OSError) as error:
        print(f"Cannot read Flutter device JSON: {error}", file=sys.stderr)
        return 2

    for device in devices:
        platform = device.get("targetPlatform")
        if not isinstance(platform, str):
            continue
        android = platform == "android" or platform.startswith("android-")
        ios = platform == "ios" or platform.startswith("ios-")
        if (
            args.platform == "android" and android
            or args.platform == "ios" and ios
            or args.platform == "mobile" and (android or ios)
        ):
            return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
