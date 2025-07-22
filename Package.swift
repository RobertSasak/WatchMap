// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "WatchMap",
  platforms: [
    .watchOS(.v8),
    .iOS(.v15),
  ],
  products: [
    .library(
      name: "WatchMap",
      targets: ["WatchMap"])
  ],
  targets: [
    .target(
      name: "WatchMap")
  ]
)
