#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
destination="${1:-platform=iOS Simulator,name=iPhone 18 Pro}"
swiftlint lint
swift build --package-path ATVRemoteKit
swift test --package-path ATVRemoteKit
xcodegen generate --spec ios/ATVRemote/project.yml
xcodebuild test -project ios/ATVRemote/ATVRemote.xcodeproj -scheme ATVRemote \
  -destination "$destination" -derivedDataPath ios/ATVRemote/DerivedData \
  -parallel-testing-enabled NO CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES
xcodebuild archive -project ios/ATVRemote/ATVRemote.xcodeproj -scheme ATVRemote \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath ios/ATVRemote/build/ReleaseDerivedData \
  -archivePath ios/ATVRemote/build/ATVRemote.xcarchive CODE_SIGNING_ALLOWED=NO
