import AppKit
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let folder = root.appendingPathComponent("build/MenuVeil.iconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
guard let image = NSImage(contentsOf: root.appendingPathComponent("Assets/MenuVeil.svg")) else { fatalError("Cannot read SVG") }
for size in [16,32,128,256,512] {
  for scale in [1,2] {
    let pixels = size * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:rep)
    image.draw(in:NSRect(x:0,y:0,width:pixels,height:pixels))
    NSGraphicsContext.restoreGraphicsState()
    let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
    try rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent(name))
    if pixels == 1024 {try rep.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent("Assets/MenuVeil.png"))}
  }
}
func lengthBytes(_ count: Int) -> Data {
    var value = UInt32(count).bigEndian
    return withUnsafeBytes(of: &value) { Data($0) }
}
var entries = Data()
for (kind, name) in [("icp4","icon_16x16.png"),("icp5","icon_32x32.png"),("icp6","icon_32x32@2x.png"),("ic07","icon_128x128.png"),("ic08","icon_256x256.png"),("ic09","icon_512x512.png"),("ic10","icon_512x512@2x.png")] {
    let png = try Data(contentsOf: folder.appendingPathComponent(name))
    entries.append(Data(kind.utf8)); entries.append(lengthBytes(png.count + 8)); entries.append(png)
}
var icon = Data("icns".utf8)
icon.append(lengthBytes(entries.count + 8)); icon.append(entries)
try icon.write(to: root.appendingPathComponent("Assets/MenuVeil.icns"))
