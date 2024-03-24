import std/[json, jsonutils, options, sequtils, strformat, strutils, tables, unicode, xmlparser, xmltree]
import pixie

type
  LegendPlace = object
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

  LegendItem = object
    string: string
    translate = vec2()
    scale = vec2(1)
    image: Image

template findChild[T](node:XmlNode; child:untyped; elementTag:string; attrName:string; attrValue:T; success: untyped;
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
var typefaces: Table[string, TypefaceData]

func getColor(node: JsonNode): ColorRGBA =
  rgba node["r"].getInt.uint8, node["g"].getInt.uint8, node["b"].getInt.uint8, 255

proc getPixels(x: JsonNode): float = ppcm * x.getFloat

proc getLegendPlace(node: JsonNode; base: Option[LegendPlace] = none(LegendPlace)): LegendPlace =
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

proc getSubstitution(node: JsonNode): LegendItem =
  # result is not intitialized with default values, I don't kynow why
  result.string = ""
  result.translate = vec2()
  result.scale = vec2(1)
  result.image = nil

  if node.contains "string": result.string = node["string"].getStr
  if node.contains "image": result.image = readImage node["image"].getStr
  if node.contains "translateX": result.translate.x = node["translateX"].getPixels
  if node.contains "translateY": result.translate.y = node["translateY"].getPixels
  if node.contains "scaleX": result.scale.x = node["scaleX"].getFloat
  if node.contains "scaleY": result.scale.y = node["scaleY"].getFloat
  if node.contains "scale": result.scale = vec2 node["scale"].getFloat

proc renderLegend(image: Image; place: LegendPlace; item: LegendItem; color: Color; posX, posY: float) =
  if item.image == nil:
    block fontsLoop:
      for font in place.fonts:
        var hasGlyphs = true
        block runesLoop:
          for rune in item.string.runes:
            if not font.typeface.hasGlyph rune:
              hasGlyphs = false
              break runesLoop
        if hasGlyphs:
          var transform = translate(vec2(posX, posY) + place.pos + item.translate) * scale(item.scale)
          font.paint.color = color
          image.fillText font, item.string, transform, hAlign = place.align
          typefaces[font.typeface.filePath].uses += 1
          break fontsLoop
      echo &"Glyphs for {item.string} not found"
  else:
    let extraTranslate = (if place.align == RightAlign: -ppcm * item.image.width.float * item.scale.x /
        item.image.height.float else: 0)
    var transform = translate(vec2(posX + extratranslate, posY) + place.pos + item.translate) *
        scale(item.scale * ppcm / item.image.height.float)
    var newImage = item.image.copy()
    var transformColor = mat3(color.r, color.g, color.b,
        place.otherColor.r, place.otherColor.g, place.otherColor.b, 0, 0, 0)
    for pixel in newImage.data.mitems:
      var v = transformColor * vec3(pixel.r.float, pixel.g.float, pixel.b.float)
      pixel.r = v.x.uint8
      pixel.g = v.y.uint8
      pixel.b = v.z.uint8
    image.draw newImage, transform

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

  typefaces = initTable[string, TypefaceData]()
  let baseLegendPlace = keysNode["baseLegends"].getLegendPlace
  var legendPlaces = newSeq[LegendPlace]()
  for legendPlace in keysNode["legends"]: legendPlaces.add legendPlace.getLegendPlace some(baseLegendPlace)
  for legendPlace in legendPlaces.mitems:
    for fontPath in legendPlace.fontPaths:
      var font = newFont (if typefaces.contains fontPath: typefaces[fontPath].typeface
      else:
        let typeface = readTypeface fontPath
        typefaces[fontPath] = TypefaceData(typeface: typeface)
        typeface)
      font.size = legendPlace.size
      legendPlace.fonts.add font
    block findKeyMaps:
      var mapSetName = legendPlace.keyMapSet
      var keyMapIndex = legendPlace.keyMapIndex
      while true:
        findChild keyLayout, keyMapSet, "keyMapSet", "id", mapSetName:
          findChild keyMapSet, keyMap, "keyMap", "index", keyMapIndex:
            legendPlace.keyMaps.add keyMap
            mapSetName = keyMap.attr("baseMapSet")
            if mapSetName == "": break findKeyMaps
            keyMapIndex = keyMap.attr("baseIndex").parseInt
          do: quit &"keyMap {keyMapIndex} in keyMapSet {mapSetName} not found"
        do: quit &"keyMapSet {mapSetName} not found"

  var substitutions = initTable[string, seq[LegendItem]]()
  for key, node in settingsJson["substitutions"]:
    substitutions[key] = if node.kind == JArray: node.mapIt it.getSubstitution else: @[node.getSubstitution]

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
    for legendPlace in legendPlaces:
      block findKeyMaps:
        for keyMap in legendPlace.keyMaps:
          findChild keyMap, keyElement, "key", "code", keyCode:
            let actionName = keyElement.attr("action")
            findChild actions, action, "action", "id", actionName:
              findChild action, state, "when", "state", legendPlace.stateName:
                let nextState = state.attr("next")
                var legendItem: LegendItem
                var color: Color
                if nextState == "":
                  legendItem.string = state.attr("output")
                  color = legendPlace.color
                else:
                  legendItem.string = "dead_" & nextState
                  color = legendPlace.deadKeyColor
                # it should be intitialized but it's not
                legendItem.translate = vec2()
                legendItem.scale = vec2(1)
                legendItem.image = nil
                if substitutions.contains legendItem.string:
                  for substitution in substitutions[legendItem.string]:
                    var overridenLegend = substitution
                    if substitution.string == "": overridenLegend.string = legendItem.string
                    image.renderLegend legendPlace, overridenLegend, color, posX, posY
                else:
                  image.renderLegend legendPlace, legendItem, color, posX, posY
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
