// Compose original simulator captures; app pixels are never redrawn.
// Usage: swift compose.swift input.png output.png remote|home|guide iphone|ipad
import AppKit
let args = CommandLine.arguments
precondition(args.count == 5)
let source = NSImage(contentsOfFile: args[1])!
let ipad = args[4] == "ipad"
let width = ipad ? 2048 : 1320
let height = ipad ? 2732 : 2868
let w = CGFloat(width), h = CGFloat(height)
let cg = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
    bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: false)
let blue = NSColor(srgbRed: 0.13, green: 0.40, blue: 0.91, alpha: 1)
let navy = NSColor(srgbRed: 0.025, green: 0.055, blue: 0.14, alpha: 1)
let accent = NSColor(srgbRed: 0.40, green: 0.87, blue: 0.94, alpha: 1)
NSGradient(starting: navy, ending: blue)!.draw(in: NSRect(x: 0,y: 0,width: w,height: h), angle: 38)
func rect(_ x: CGFloat,_ top: CGFloat,_ width: CGFloat,_ height: CGFloat) -> NSRect {
    NSRect(x:x,y:h-top-height,width:width,height:height)
}
func text(_ string: String, top: CGFloat, size: CGFloat, color: NSColor = .white, bold: Bool = false, height: CGFloat = 130) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineSpacing = 12
    let font = NSFont.systemFont(ofSize: size, weight: bold ? .bold : .medium)
    (string as NSString).draw(in: rect(70,top,w-140,height), withAttributes:
        [.font:font,.foregroundColor:color,.paragraphStyle:paragraph])
}
let titles: [String:(String,String,String)] = [
    "remote":("いつものTVを、\n手のひらから。","方向キー・ホーム・音量を、ひとつの画面で。","Google TV / Android TV 対応"),
    "home":("電源を入れて、\n同じWi-Fiへ。","ネットワークにつながったTVを検索。","電源OFFでネットワーク接続が切れるTVは検出できません"),
    "guide":("つながらない時も、\n手順がわかる。","接続の条件と確認ポイントを、アプリ内に。","TVのネットワーク初期設定は別途必要です")
]
let content = titles[args[3]]!
text("ポケットリモコン  /  追加課金なし", top: ipad ? 100 : 110, size: ipad ? 38 : 32, color:accent, bold:true,height:65)
text(content.0, top: ipad ? 215 : 225, size: ipad ? 124 : 96, bold:true,height:320)
text(content.1, top: ipad ? 535 : 505, size: ipad ? 41 : 33,height:90)
let targetHeight: CGFloat = ipad ? 1825 : 2010
let ratio = source.size.width/source.size.height
let screenW = targetHeight * ratio
let x = (w-screenW)/2, top: CGFloat = ipad ? 710 : 700
let bezel: CGFloat = ipad ? 22 : 18
let screen = rect(x,top,screenW,targetHeight)
let outer = screen.insetBy(dx:-bezel,dy:-bezel)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
shadow.shadowBlurRadius = 50; shadow.shadowOffset = NSSize(width:0,height:-25); shadow.set()
NSColor(white:0.08,alpha:1).setFill()
NSBezierPath(roundedRect:outer,xRadius:ipad ? 44 : 82,yRadius:ipad ? 44 : 82).fill()
NSGraphicsContext.restoreGraphicsState()
NSColor(white:0.45,alpha:1).setStroke()
let edge = NSBezierPath(roundedRect:outer,xRadius:ipad ? 44 : 82,yRadius:ipad ? 44 : 82)
edge.lineWidth = 3; edge.stroke()
NSGraphicsContext.saveGraphicsState()
NSBezierPath(roundedRect:screen,xRadius:ipad ? 25 : 64,yRadius:ipad ? 25 : 64).addClip()
source.draw(in:screen,from:.zero,operation:.copy,fraction:1)
NSGraphicsContext.restoreGraphicsState()
text(content.2,top:h-90,size:ipad ? 30 : 25,color:NSColor.white.withAlphaComponent(0.85),height:55)
NSGraphicsContext.restoreGraphicsState()
let bitmap = NSBitmapImageRep(cgImage: cg.makeImage()!)
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:args[2]))
print(args[2])
