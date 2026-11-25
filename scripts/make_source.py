"""Writes source.json, the SideStore/AltStore source that points at this build's release."""
import json
import os
from datetime import datetime, timezone

repo = os.environ["REPO"]                  # e.g. YaqoubYousef/FocusFeed
version = os.environ["VERSION"]            # e.g. 1.0.12  (matches CFBundleShortVersionString)
build = os.environ["BUILD"]                # e.g. 12      (matches CFBundleVersion)
notes = (os.environ.get("COMMIT_MSG") or "New build").strip().splitlines()[0]

owner = repo.split("/")[0]
releases = f"https://github.com/{repo}/releases"
raw = f"https://raw.githubusercontent.com/{repo}/main"

source = {
    "name": "FocusFeed",
    "identifier": f"io.github.{owner.lower()}.focusfeed.source",
    "subtitle": "Instagram without the Reels scroll",
    "sourceURL": f"{releases}/latest/download/source.json",
    "iconURL": f"{raw}/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png",
    "apps": [
        {
            "name": "FocusFeed",
            "bundleIdentifier": "com.focusfeed.app",
            "developerName": owner,
            "subtitle": "Feed and DMs, no Reels scrolling",
            "localizedDescription": (
                "Instagram's website in a focused app: home feed and DMs work, "
                "the Reels tab and feed reels are hidden, and reels sent to you "
                "play without swiping to the next one."
            ),
            "iconURL": f"{raw}/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png",
            "tintColor": "#C13584",
            "category": "social",
            "versions": [
                {
                    "version": version,
                    "buildVersion": build,
                    "date": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "localizedDescription": notes,
                    "downloadURL": f"{releases}/download/v{version}/FocusFeed.ipa",
                    "size": os.path.getsize("FocusFeed.ipa"),
                    "minOSVersion": "16.0",
                }
            ],
            "appPermissions": {
                "entitlements": [],
                "privacy": {
                    "NSCameraUsageDescription": "To take photos and videos to send in messages.",
                    "NSMicrophoneUsageDescription": "To record voice and video messages.",
                    "NSPhotoLibraryUsageDescription": "To send photos and videos in messages.",
                    "NSPhotoLibraryAddUsageDescription": "To save photos you choose to download.",
                },
            },
        }
    ],
    "news": [],
}

with open("source.json", "w") as f:
    json.dump(source, f, indent=2)
print(json.dumps(source, indent=2))
