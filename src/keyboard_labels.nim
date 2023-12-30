import std/json
import pixie

func getColor(node: JsonNode): ColorRGBA =
  rgba(node["r"].getInt.uint8, node["g"].getInt.uint8, node["b"].getInt.uint8, 255)

proc main() =
  let settingsJson = json.parsefile "settings.json" # TODO: parameter

  let imageNode = settingsJson["image"]
  let ppcm = imageNode["ppcm"].getFloat
  func getPixels(x: JsonNode): float = ppcm * x.getFloat
  let imageWidth = imageNode["width"].getPixels.int
  let imageHeight = imageNode["height"].getPixels.int
  let imageBackground = imageNode["background"].getColor

  let keysNode = settingsJson["keys"]
  let keyWidth = keysNode["width"].getPixels
  let keyHeight = keysNode["height"].getPixels
  let keyBackground = keysNode["background"].getColor
  let padding = keysNode["padding"].getPixels
  let codesArray = keysNode["codes"]

  let image = newImage(imageWidth, imageHeight)
  image.fill imageBackground


  var posX = padding
  var posY = padding
  var posXAdd = keyWidth + padding
  var posYAdd = keyHeight + padding
  for code in codesArray:
    var path = newPath()
    path.rect(posX, posY, keyWidth, keyHeight)
    image.fillPath path, keyBackground
    if posX + 2 * posXAdd >= imageWidth.float:
      posX = padding
      posY += posYAdd
    else: posX += posXAdd
  
  image.writeFile "out.png" # TODO: parameter
  
main()
