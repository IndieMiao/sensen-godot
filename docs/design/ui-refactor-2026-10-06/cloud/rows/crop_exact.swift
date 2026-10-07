import Foundation
import CoreGraphics
import ImageIO
let base=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
for row in ["27","28"] {
 let url=base.appendingPathComponent("row-\(row).png")
 let source=CGImageSourceCreateWithURL(url as CFURL,nil)!
 let image=CGImageSourceCreateImageAtIndex(source,0,nil)!
 for (part,x,width) in [("a",0,1662),("b",1662,image.width-1662)] {
  let cropped=image.cropping(to:CGRect(x:x,y:0,width:width,height:image.height))!
  let dest=CGImageDestinationCreateWithURL(base.appendingPathComponent("row-\(row)-\(part).png") as CFURL,"public.png" as CFString,1,nil)!
  CGImageDestinationAddImage(dest,cropped,nil)
  if !CGImageDestinationFinalize(dest) { fatalError("Write failed") }
 }
}
