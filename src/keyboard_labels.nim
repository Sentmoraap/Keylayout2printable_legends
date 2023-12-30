import std/[json, xmlparser, xmltree, strutils]
import pixie

func getColor(node: JsonNode): ColorRGBA =
  rgba(node["r"].getInt.uint8, node["g"].getInt.uint8, node["b"].getInt.uint8, 255)

template findChild[T](node:XmlNode, child:untyped, elementTag:string, attrName:string, attrValue:T, success: untyped,
    failure: untyped) =
  block loop:
    for `child` {.inject.} in node:
      if `child`.kind != xnElement or `child`.tag != elementTag: continue
      when T is string:
        if `child`.attr(attrName) != attrValue: continue
      elif T is int:
        if `child`.attr(attrName).parseInt != attrValue: continue
      else:
        {.fatal: "T must be string or int".}
      success
      break loop
    failure

proc main() =
  echo "Reading data"

  let settingsJson = json.parsefile "settings.json" # TODO: parameter
  let keyLayout = loadXml "Optimot Qwerty.keylayout" # TODO: parameter 

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
  var font = readFont keysNode["font"].getStr
  font.size = keysNode["fontSize"].getPixels
  font.paint.color = keysNode["fontColor"].getColor.color
  let codesArray = keysNode["codes"]
  let stateName = keysNode["state"].getStr
  
  let mapSetName = keysNode["keyMapSet"].getStr
  let keyMapIndex = keysNode["keyMapIndex"].getInt
  var keyMaps = newSeq[XmlNode]()
  findChild keyLayout, keyMapSet, "keyMapSet", "id", mapSetName:
    findChild keyMapSet, keyMap, "keyMap", "index", keyMapIndex:
      keyMaps.add keyMap
    do: echo "TODO error"
  do: echo "TODO error"
  # TODO: baseMapSet

  let actions = keyLayout.child("actions")
  
  echo "Generating image"

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
    findChild keyMaps[0], keyElement, "key", "code", code.getInt:
      let actionName = keyElement.attr("action")
      findChild actions, action, "action", "id", actionName:
        findChild action, state, "when", "state", stateName:
          image.fillText font, state.attr("output"), translate(vec2(posX, posY)), hAlign = CenterAlign
        do: discard
      do: echo "Action ", actionName, " not found"
    do: echo "TODO parent keymap"
    if posX + 2 * posXAdd >= imageWidth.float:
      posX = padding
      posY += posYAdd
    else: posX += posXAdd

  echo "Saving file"

  image.writeFile "out.png" # TODO: parameter

  echo "Done"

main()

# TODO: error checking
