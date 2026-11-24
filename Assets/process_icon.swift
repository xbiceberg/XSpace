import AppKit
import Foundation

// 用法: swift process_icon.swift <输入图> <输出透明PNG>
// 手机图标(蓝底白X文件夹)通常带一圈浅色相框 + 深灰背景，
// 本脚本: 裁掉浅色相框 -> 将深灰背景透明化 -> 裁到文件夹主体并补成正方形
let args = CommandLine.arguments
guard args.count >= 3 else { fatalError("usage: process_icon.swift <input> <output>") }
let inputPath = args[1]
let outputPath = args[2]

guard let image = NSImage(contentsOfFile: inputPath),
      let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let data = rep.bitmapData else { fatalError("无法读取图片") }

let w = rep.pixelsWide, h = rep.pixelsHigh
let bpp = rep.bitsPerPixel / 8
let stride = rep.bytesPerRow
print("源图 \(w)x\(h)")

func rgb(_ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
    let p = data + y * stride + x * bpp
    return (p[0], p[1], p[2])
}

// 1) 检测浅色相框宽度：从中线向中心找第一个"非浅色"像素
func isLight(_ c: (r: UInt8,g: UInt8,b: UInt8)) -> Bool {
    Int(c.r) > 200 && Int(c.g) > 200 && Int(c.b) > 200
}
var top = 0
while top < h/2 && isLight(rgb(w/2, top)) { top += 1 }
var left = 0
while left < w/2 && isLight(rgb(left, h/2)) { left += 1 }
var bottom = h - 1
while bottom > h/2 && isLight(rgb(w/2, bottom)) { bottom -= 1 }
var right = w - 1
while right > w/2 && isLight(rgb(right, h/2)) { right -= 1 }
// 往里各收 2px 避开相框抗锯齿
top += 2; left += 2; bottom -= 2; right -= 2
print("相框内边界: top=\(top) left=\(left) bottom=\(bottom) right=\(right)")

let cw = right - left + 1
let ch = bottom - top + 1

// 2) 深灰背景色：取相框内侧四角
let s = 15
let samples = [rgb(left+s, top+s), rgb(right-s, top+s), rgb(left+s, bottom-s), rgb(right-s, bottom-s)]
let bgR = Double(samples.reduce(0) { $0 + Int($1.r) }) / 4
let bgG = Double(samples.reduce(0) { $0 + Int($1.g) }) / 4
let bgB = Double(samples.reduce(0) { $0 + Int($1.b) }) / 4
print("深灰背景色 R=\(bgR) G=\(bgG) B=\(bgB)")

// 3) 生成去掉相框后的 RGBA 图，深灰背景透明化
guard let cropped = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: cw, pixelsHigh: ch,
                                     bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 32),
      let cd = cropped.bitmapData else { fatalError("无法创建位图") }

var minX = cw, minY = ch, maxX = 0, maxY = 0
for y in 0..<ch {
    for x in 0..<cw {
        let c = rgb(left + x, top + y)
        let r = Double(c.r), g = Double(c.g), b = Double(c.b)
        let dist = sqrt(pow(r-bgR,2) + pow(g-bgG,2) + pow(b-bgB,2))
        var alpha: UInt8 = 255
        if dist < 26 { alpha = 0 }
        else if dist < 60 { alpha = UInt8((dist-26)/34 * 255) }
        let dst = cd + y * cropped.bytesPerRow + x * 4
        dst[0] = c.r; dst[1] = c.g; dst[2] = c.b; dst[3] = alpha
        if alpha > 40 {
            if x < minX { minX = x }; if x > maxX { maxX = x }
            if y < minY { minY = y }; if y > maxY { maxY = y }
        }
    }
}
print("文件夹主体边界: (\(minX),\(minY))-(\(maxX),\(maxY))")

// 4) 裁到主体 + 少量边距，并补成正方形(透明填充)
let pad = 8
var fx0 = max(0, minX - pad), fy0 = max(0, minY - pad)
var fx1 = min(cw-1, maxX + pad), fy1 = min(ch-1, maxY + pad)
let fw = fx1 - fx0 + 1, fh = fy1 - fy0 + 1
let side = max(fw, fh)
print("主体 \(fw)x\(fh) -> 正方形 \(side)x\(side)")

guard let final = NSBitmapImageRep(bitmapDataPlanes: nil,
                                   pixelsWide: side, pixelsHigh: side,
                                   bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 32),
      let fd = final.bitmapData else { fatalError("无法创建最终位图") }
// 默认全透明
var idx = 0
while idx < side * final.bytesPerRow { fd[idx+3] = 0; idx += 4 }
let ox = (side - fw) / 2, oy = (side - fh) / 2
for y in 0..<fh {
    for x in 0..<fw {
        let src = cd + (fy0 + y) * cropped.bytesPerRow + (fx0 + x) * 4
        let dst = fd + (oy + y) * final.bytesPerRow + (ox + x) * 4
        for k in 0..<4 { dst[k] = src[k] }
    }
}

guard let png = final.representation(using: .png, properties: [:]) else { fatalError("无法生成 PNG") }
try png.write(to: URL(fileURLWithPath: outputPath))
print("已输出 \(outputPath) (\(side)x\(side))")
