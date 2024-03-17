import std/[json, jsonutils, options, strformat, strutils, tables, unicode, xmlparser, xmltree]
import pixie

type
  Legend = object
    # JSON data
    fontPaths: seq[string]
    size: float
    color: Color
    deadKeyColor: Color
    deadKey2Color: Color
    otherColor: Color
    keyMapSet: string
    keyMapIndex: int
    stateName: string
    pos: Vec2
    align: HorizontalAlignment

    # Program data
    keyMaps: seq[XmlNode]
    fonts: seq[Font]

  TypefaceData = object
    uses: int = 0
    typeface: Typeface

  Substitution = object
    string: string
    translate = vec2()
    scale = vec2(1)
    image: Image

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
        {.error: "T must be string or int".}
      success
      break loop
    failure

var ppcm: float

func getColor(node: JsonNode): ColorRGBA =
  rgba node["r"].getInt.uint8, node["g"].getInt.uint8, node["b"].getInt.uint8, 255

proc getPixels(x: JsonNode): float = ppcm * x.getFloat

proc getLegend(node: JsonNode, base: Option[Legend] = none(Legend)): Legend =
  if base.isSome : result = base.unsafeGet
  if node.contains "fonts":
    result.fontPaths.setLen 0
    for arrayNode in node["fonts"]: result.fontPaths.add arrayNode.getStr
  if node.contains "size": result.size = node["size"].getPixels
  if node.contains "color": result.color = node["color"].getColor.color
  if node.contains "deadKeyColor": result.deadKeyColor = node["deadKeyColor"].getColor.color
  if node.contains "deadKey2Color": result.deadKey2Color = node["deadKey2Color"].getColor.color
  if node.contains "otherColor": result.otherColor = node["otherColor"].getColor.color
  if node.contains "keyMapSet": result.keyMapSet = node["keyMapSet"].getStr
  if node.contains "keyMapIndex": result.keyMapIndex = node["keyMapIndex"].getInt
  if node.contains "state": result.stateName = node["state"].getStr
  if node.contains "posX": result.pos.x = node["posX"].getPixels
  if node.contains "posY": result.pos.y = node["posY"].getPixels
  if node.contains "align": result.align.fromJson node["align"]

proc main() =
  echo "Reading data"

  let settingsJson = json.parsefile "settings.json" # TODO: parameter
  let keyLayout = loadXml "Optimot Qwerty.keylayout" # TODO: parameter

  let imageNode = settingsJson["image"]
  ppcm = imageNode["ppcm"].getFloat
  let imageWidth = imageNode["width"].getPixels.int
  let imageHeight = imageNode["height"].getPixels.int
  let imageBackground = imageNode["background"].getColor

  let keysNode = settingsJson["keys"]
  let keyWidth = keysNode["width"].getPixels
  let keyHeight = keysNode["height"].getPixels
  let keyBackground = keysNode["background"].getColor
  let padding = keysNode["padding"].getPixels
  let codesArray = keysNode["codes"]

  var typefaces = initTable[string, TypefaceData]()
  let baseLegends = keysNode["baseLegends"].getLegend
  var legends = newSeq[Legend]()
  for legend in keysNode["legends"]: legends.add legend.getLegend some(baseLegends)
  for legend in legends.mitems:
    for fontPath in legend.fontPaths:
      var font = newFont (if typefaces.contains fontPath: typefaces[fontPath].typeface
      else:
        let typeface = readTypeface fontPath
        typefaces[fontPath] = TypefaceData(typeface: typeface)
        typeface)
      font.size = legend.size
      legend.fonts.add font
    block findKeyMaps:
      var mapSetName = legend.keyMapSet
      var keyMapIndex = legend.keyMapIndex
      while true:
        findChild keyLayout, keyMapSet, "keyMapSet", "id", mapSetName:
          findChild keyMapSet, keyMap, "keyMap", "index", keyMapIndex:
            legend.keyMaps.add keyMap
            mapSetName = keyMap.attr("baseMapSet")
            if mapSetName == "": break findKeyMaps
            keyMapIndex = keyMap.attr("baseIndex").parseInt
          do: quit &"keyMap {keyMapIndex} in keyMapSet {mapSetName} not found"
        do: quit &"keyMapSet {mapSetName} not found"

  var substitutions = initTable[string, Substitution]()
  for key, node in settingsJson["substitutions"]:
    var substitution = Substitution()
    if node.contains "string": substitution.string = node["string"].getStr
    if node.contains "image": substitution.image = readImage node["image"].getStr
    if node.contains "translateX": substitution.translate.x = node["translateX"].getPixels
    if node.contains "translateY": substitution.translate.y = node["translateY"].getPixels
    if node.contains "scaleX": substitution.scale.x = node["scaleX"].getFloat
    if node.contains "scaleY": substitution.scale.y = node["scaleY"].getFloat
    if node.contains "scale": substitution.scale = vec2 node["scale"].getFloat
    substitutions[key] = substitution

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
    let keyCode = code.getInt
    for legend in legends:
      block findKeyMaps:
        for keyMap in legend.keyMaps:
          findChild keyMap, keyElement, "key", "code", keyCode:
            let actionName = keyElement.attr("action")
            findChild actions, action, "action", "id", actionName:
              findChild action, state, "when", "state", legend.stateName:
                let nextState = state.attr("next")
                var str: string
                var color: Color
                if nextState == "":
                  str = state.attr("output")
                  color = legend.color
                else:
                  str = "dead_" & nextState
                  color = legend.deadKeyColor
                var strTranslate = vec2()
                var strScale = vec2(1)
                var labelImage: Image
                if substitutions.contains str:
                  let substitution = substitutions[str]
                  if substitution.string != "": str = substitution.string
                  strTranslate = substitution.translate
                  strScale = substitution.scale
                  labelImage = substitution.image
                if labelImage == nil:
                  block fontsLoop:
                    for font in legend.fonts:
                      var hasGlyphs = true
                      block runesLoop:
                        for rune in str.runes:
                          if not font.typeface.hasGlyph rune:
                            hasGlyphs = false
                            break runesLoop
                      if hasGlyphs:
                        var transform = translate(vec2(posX, posY) + legend.pos + strTranslate) * scale(strScale)
                        font.paint.color = color
                        image.fillText font, str, transform, hAlign = legend.align
                        typefaces[font.typeface.filePath].uses += 1
                        break fontsLoop
                    echo &"Glyphs for {str} not found"
                else:
                  let extraTranslate = (if legend.align == RightAlign: -ppcm * labelImage.width.float * strScale.x /
                      labelImage.height.float else: 0)
                  var transform = translate(vec2(posX + extratranslate, posY) + legend.pos + strTranslate) *
                      scale(strScale * ppcm / labelImage.height.float)
                  var newImage = labelImage.copy()
                  var transformColor = mat3(color.r, color.g, color.b,
                      legend.otherColor.r, legend.otherColor.g, legend.otherColor.b, 0, 0, 0)
                  for pixel in newImage.data.mitems:
                    var v = transformColor * vec3(pixel.r.float, pixel.g.float, pixel.b.float)
                    pixel.r = v.x.uint8
                    pixel.g = v.y.uint8
                    pixel.b = v.z.uint8
                  image.draw newImage, transform
              do: discard
            do: echo "Action ", actionName, " not found"
            {.push warning[UnreachableCode]:off.}
            break findKeyMaps
            {.pop.}
          do: discard
        echo "Key ", keyCode, " not found"
    if posX + 2 * posXAdd >= imageWidth.float:
      posX = padding
      posY += posYAdd
    else: posX += posXAdd

  for path, typeface in typefaces:
    echo &"Font {path} used {typeface.uses} time(s)"

  echo "Saving file"

  image.writeFile "out.png" # TODO: parameter

  echo "Done"

main()

# TODO: error checking
# TODO: check inneficient memory usages
