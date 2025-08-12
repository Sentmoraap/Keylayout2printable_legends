import std/[json, jsonutils, options, sequtils, strformat, strutils, tables, unicode, xmlparser, xmltree]
import pixie

type
  MergeType {.pure.} = enum NO, SAME, UPPERCASE, LOWERCASE

  LegendPlace = object
    # JSON data
    layoutPath: string
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
    pos2: Vec2
    align: HorizontalAlignment
    mergeType: MergeType
    merge: array[2, int]

    # Program data
    keyMaps: seq[XmlNode]
    font: Font
    actions: XmlNode

  TypefaceData = object
    uses: int = 0
    typeface: Typeface

  LegendItem = object
    string: string
    translate = vec2()
    translateMirrored = vec2()
    scale = vec2(1)
    image: Image
    color: Color

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
var substitutions = initTable[string, seq[LegendItem]]()


func getColor(node: JsonNode): ColorRGBA =
  rgba node["r"].getInt.uint8, node["g"].getInt.uint8, node["b"].getInt.uint8, 255

proc getPixels(x: JsonNode): float = ppcm * x.getFloat

proc getLegendPlace(node: JsonNode; base: Option[LegendPlace] = none(LegendPlace)): LegendPlace =
  result.pos = vec2(system.Nan)
  result.pos2 = vec2(system.Nan)
  result.mergeType = NO
  if base.isSome: result = base.unsafeGet
  if node.contains "fonts":
    result.fontPaths.setLen 0
    for arrayNode in node["fonts"]: result.fontPaths.add arrayNode.getStr
  if node.contains "size": result.size = node["size"].getPixels
  if node.contains "color": result.color = node["color"].getColor.color
  if node.contains "deadKeyColor": result.deadKeyColor = node["deadKeyColor"].getColor.color
  if node.contains "deadKey2Color": result.deadKey2Color = node["deadKey2Color"].getColor.color
  if node.contains "otherColor": result.otherColor = node["otherColor"].getColor.color
  if node.contains "keyLayout": result.layoutPath = node["keyLayout"].getStr
  if node.contains "keyMapSet": result.keyMapSet = node["keyMapSet"].getStr
  if node.contains "keyMapIndex": result.keyMapIndex = node["keyMapIndex"].getInt
  if node.contains "state": result.stateName = node["state"].getStr
  if node.contains "posX": result.pos.x = node["posX"].getPixels
  if node.contains "posY": result.pos.y = node["posY"].getPixels
  if node.contains "pos2X": result.pos2.x = node["pos2X"].getPixels
  if node.contains "pos2Y": result.pos2.y = node["pos2Y"].getPixels
  if node.contains "align": result.align.fromJson node["align"]
  if node.contains "mergeRule": result.mergeType.fromJson node["mergeRule"]
  if node.contains "merge":
    for i in 0..1: result.merge[i] = node["merge"][i].getInt

proc getTypeface(path: string): Typeface =
  if typefaces.contains path: typefaces[path].typeface
  else:
    let typeface = readTypeface path
    typefaces[path] = TypefaceData(typeface: typeface)
    typeface

proc getSubstitution(node: JsonNode): LegendItem =
  # result is not intitialized with default values, I don't kynow why
  result.string = ""
  result.translate = vec2()
  result.translateMirrored = vec2()
  result.scale = vec2(1)
  result.image = nil

  if node.contains "string": result.string = node["string"].getStr
  if node.contains "image": result.image = readImage node["image"].getStr
  if node.contains "translateX": result.translate.x = node["translateX"].getPixels
  if node.contains "translateY": result.translate.y = node["translateY"].getPixels
  if node.contains "translateMirroredX": result.translateMirrored.x = node["translateMirroredX"].getPixels
  if node.contains "translateMirroredY": result.translateMirrored.y = node["translateMirroredY"].getPixels
  if node.contains "scaleX": result.scale.x = node["scaleX"].getFloat
  if node.contains "scaleY": result.scale.y = node["scaleY"].getFloat
  if node.contains "scale": result.scale = vec2 node["scale"].getFloat

proc getLegendItem(node: XmlNode; currentState: string; normalColor, deadKeyColor: Color):
    tuple[item: LegendItem; isDeadKey: bool; nextState: string] =
  result.nextState = node.attr("next")
  if result.nextState == "" or result.nextState == currentState:
    result.isDeadKey = false
    result.item.string = node.attr("output")
    result.item.color = normalColor
  else:
    result.isDeadKey = true
    result.item.string = "dead_" & result.nextState
    result.item.color = deadKeyColor
  # TODO: does it need initialization?
  result.item.translate = vec2()
  result.item.scale = vec2(1)
  result.item.image = nil

proc renderLegend(image: Image; place: LegendPlace; item: LegendItem; posX, posY: float,
    is2ndPlace: bool) =
  let placePos = (
    var tempPos = place.pos
    if is2ndPlace:
      if place.pos2.x == place.pos2.x: tempPos.x = place.pos2.x
      if place.pos2.y == place.pos2.y: tempPos.y = place.pos2.y
    tempPos
  )
  let translateMirrored = vec2(item.translateMirrored.x * (case place.align:
      of LeftAlign:
        1
      of CenterAlign:
        0
      of RightAlign:
        -1
      ), item.translateMirrored.y)

  if item.image == nil:
    var transform = translate(vec2(posX, posY) + placePos + item.translate + translateMirrored) * scale(item.scale)
    place.font.paint.color = item.color
    image.fillText place.font, item.string, transform, hAlign = place.align
    let typeface = place.font.typeface
    for rune in item.string.runes:
      block fontsLoop:
        if typeface.hasGlyph rune:
          typefaces[typeface.filepath].uses += 1
          break fontsLoop
        else:
          for fallback in typeface.fallbacks:
            if fallback.hasGlyph rune:
              typefaces[fallback.filepath].uses += 1
              break fontsLoop
        echo &"Glyph for {rune} not found"
  else:
    let extraTranslate = (if place.align == RightAlign: -ppcm * item.image.width.float * item.scale.x /
        item.image.height.float else: 0)
    var transform = translate(vec2(posX + extratranslate, posY) + placePos + item.translate + translateMirrored) *
        scale(item.scale * ppcm / item.image.height.float)
    var newImage = item.image.copy()
    var transformColor = mat3(item.color.r, item.color.g, item.color.b,
        place.otherColor.r, place.otherColor.g, place.otherColor.b, 0, 0, 0)
    for pixel in newImage.data.mitems:
      var v = transformColor * vec3(pixel.r.float, pixel.g.float, pixel.b.float)
      pixel.r = v.x.uint8
      pixel.g = v.y.uint8
      pixel.b = v.z.uint8
    image.draw newImage, transform

proc renderLegendSubstitutions(image: Image; place: LegendPlace; item: LegendItem; posX, posY: float;
    isDeadKey, is2ndPlace: bool): bool =
  if substitutions.contains item.string:
    for substitution in substitutions[item.string]:
      var overridenLegend = substitution
      if substitution.string == "": overridenLegend.string = item.string
      overridenLegend.color = item.color
      image.renderLegend place, overridenLegend, posX, posY, is2ndPlace
    substitutions[item.string].len > 0
  else:
    if isDeadKey:
      echo "No substitution for ", item.string
    image.renderLegend place, item, posX, posY, is2ndPlace
    true

proc main() =
  echo "Reading data"

  let settingsJson = json.parsefile "settings.json" # TODO: parameter
  var keyLayouts = initTable[string, XmlNode]()

  let imageNode = settingsJson["image"]
  ppcm = imageNode["ppcm"].getFloat
  let imageWidth = imageNode["width"].getPixels.int
  let imageHeight = imageNode["height"].getPixels.int
  let imageBackground = imageNode["background"].getColor

  let keysNode = settingsJson["keys"]
  let keyTopWidth = keysNode["topWidth"].getPixels
  let keyTopHeight = keysNode["topHeight"].getPixels
  let keySideSize = keysNode["sideSize"].getPixels
  let keyBackground = keysNode["background"].getColor
  let padding = keysNode["padding"].getPixels
  let codesArray = keysNode["codes"]

  typefaces = initTable[string, TypefaceData]()
  let baseLegendPlace = keysNode["baseLegends"].getLegendPlace
  var legendPlaces = newSeq[LegendPlace]()
  for legendPlace in keysNode["legends"]: legendPlaces.add legendPlace.getLegendPlace some(baseLegendPlace)
  for legendPlace in legendPlaces.mitems:
    for index, fontPath in legendPlace.fontPaths:
      if index == 0:
        discard getTypeface fontPath
        legendPlace.font = fontPath.readTypeface.newFont
      else:
        legendPlace.font.typeface.fallbacks.add fontPath.getTypeface
    legendPlace.font.size = legendPlace.size

    block findKeyMaps:
      var mapSetName = legendPlace.keyMapSet
      var keyMapIndex = legendPlace.keyMapIndex
      while true:
        let keyLayout = if keyLayouts.contains legendPlace.layoutPath: keyLayouts[legendPlace.layoutPath]
        else:
          let newKeyLayout = loadXml legendPlace.layoutPath
          keyLayouts[legendPlace.layoutPath] = newKeyLayout
          newKeyLayout
        legendPlace.actions = keyLayout.child("actions")
        findChild keyLayout, keyMapSet, "keyMapSet", "id", mapSetName:
          findChild keyMapSet, keyMap, "keyMap", "index", keyMapIndex:
            legendPlace.keyMaps.add keyMap
            mapSetName = keyMap.attr("baseMapSet")
            if mapSetName == "": break findKeyMaps
            keyMapIndex = keyMap.attr("baseIndex").parseInt
          do: quit &"keyMap {keyMapIndex} in keyMapSet {mapSetName} not found"
        do: quit &"keyMapSet {mapSetName} not found"

  for key, node in settingsJson["substitutions"]:
    substitutions[key] = if node.kind == JArray: node.mapIt it.getSubstitution else: @[node.getSubstitution]

  echo "Generating image"

  let image = newImage(imageWidth, imageHeight)
  image.fill imageBackground

  var posX = padding
  var posY = padding
  let keyTotalWidth = keyTopWidth + keySideSize * 2
  let keyTotalHeight = keyTopHeight + keySideSize * 2
  let posXAdd = keyTotalWidth + padding
  let posYAdd = keyTotalHeight + padding
  for code in codesArray:
    var path = newPath()
    path.rect(posX + keySideSize, posY, keyTopWidth, keyTotalHeight)
    path.rect(posX, posY + keySideSize, keyTotalWidth, keyTopHeight)
    image.fillPath path, keyBackground
    let keyCode = code.getInt
    var legendItems = newSeq[array[2, LegendItem]](legendPlaces.len)
    for placeIndex, legendPlace in legendPlaces:
      if legendPlace.mergeType == NO:
        block findKeyMaps:
          for keyMap in legendPlace.keyMaps:
            findChild keyMap, keyElement, "key", "code", keyCode:
              let actionName = keyElement.attr("action")
              if actionName.len > 0:
                findChild legendPlace.actions, action, "action", "id", actionName:
                  let stateName = legendPlace.stateName
                  var hasDeadKey2 = false
                  findChild action, state, "when", "state", stateName:
                    var legendItem2: LegendItem
                    let (legendItem, isDeadKey, nextState) = getLegendItem(state, stateName, legendPlace.color,
                        legendPlace.deadKeyColor)
                    if isDeadKey:
                      findChild action, state2, "when", "state", nextState:
                        (legendItem2, hasDeadKey2, _) = getLegendItem(state2, nextState, legendPlace.color,
                            legendPlace.deadKey2Color)
                      do: discard
                    if not hasDeadKey2:
                      legendItem2.string = ""
                    legendItems[placeIndex] = [legendItem, legendItem2]
                  do: discard
                do: echo "Action ", actionName, " not found"
                {.push warning[UnreachableCode]:off.}
                break findKeyMaps
                {.pop.}
              else:
                legendItems[placeIndex][0].string = keyElement.attr("output")
                legendItems[placeIndex][0].color = legendPlace.color
                legendItems[placeIndex][1].string = ""
                break findKeyMaps
            do: discard
          echo "Key ", keyCode, " not found"
          # TODO: normalize unicode strings
      else:
        let str0 = legendItems[legendPlace.merge[0]][0].string
        let str1 = legendItems[legendPlace.merge[1]][0].string
        let merge = if legendPlace.mergeType == SAME:
          str0 == str1
        else:
          case legendPlace.mergeType:
            of NO, SAME: # Unreachable
              assert false
              false
            of MergeType.UPPERCASE:
              str0 == str1 or str0.toLower == str1 or str0 == str1.toUpper
            of MergeType.LOWERCASE:
              str0 == str1 or str0.toUpper == str1 or str0 == str1.toLower
        if merge:
          legendItems[placeIndex][0].string = legendItems[legendPlace.merge[0]][0].string
          legendItems[placeIndex][0].color = legendPlace.color
          for i in 0..1: legendItems[legendPlace.merge[i]][0].string = ""
        else:
          legendItems[placeIndex][0].string = ""
    for placeIndex, legendPlace in legendPlaces:
      let second = addr legendItems[placeIndex][1]
      let renderedSomething = second.string.len > 0 and
          image.renderLegendSubstitutions(legendPlace, second[], posX + keySideSize, posY + keySideSize, true, true)
      discard image.renderLegendSubstitutions(legendPlace, legendItems[placeIndex][0],
          posX + keySideSize, posY + keySideSize, false, legendPlace.align == RightAlign and not renderedSomething)
    if posX + 2 * posXAdd >= imageWidth.float:
      posX = padding
      posY += posYAdd
    else: posX += posXAdd

  for path, typeface in typefaces: echo &"Font {path} used {typeface.uses} time(s)"

  echo "Saving file"

  image.writeFile "out.png" # TODO: parameter

  echo "Done"

main()

# TODO: error checking
# TODO: check inneficient memory usages
# TODO: comments
