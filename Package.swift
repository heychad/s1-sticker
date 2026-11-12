// swift-tools-version: 5.9
import PackageDescription
let package=Package(name:"S1StickerCore",platforms:[.macOS(.v13),.iOS(.v17)],products:[.library(name:"StickerCore",targets:["StickerCore"])],targets:[.target(name:"StickerCore",path:"Shared/Core"),.testTarget(name:"StickerCoreTests",dependencies:["StickerCore"],path:"tests/StickerCoreTests")])
