import std/json

import common
import confusables

include prelude

type
  CondAnd = object of Condition
    conds: seq[ref[Condition]] # {.unique.}

  CondOr = object of Condition
    conds: seq[ref[Condition]] # {.unique.}

  CondNot = object of Condition
    cond : ref[Condition] # {.unique.}

  CondIsNotDeadKey = object of Condition
    discard

  CondNoLegendAtPlace = object of Condition
    place: int

  CondNotConfusableWith = object of Condition
    place: int

method check*(self: ref Condition, legendItems: openArray[array[2, LegendItem]], placeIndex: int) :
    bool {.base.} =
  assert(false, "Abstract method called")
  false

method check(self: ref CondAnd, legendItems: openArray[array[2, LegendItem]], placeIndex: int) :
    bool =
  for cond in self.conds:
    if not check(cond, legendItems, placeIndex): return false
  return true

method check(self: ref CondOr, legendItems: openArray[array[2, LegendItem]], placeIndex: int) :
    bool =
  for cond in self.conds:
    if check(cond, legendItems, placeIndex): return true
  return false

method check(self: ref CondNot, legendItems: openArray[array[2, LegendItem]], placeIndex: int) :
    bool =
  not check(self.cond, legendItems, placeIndex)

method check(self: ref CondIsNotDeadKey, legendItems: openArray[array[2, LegendItem]], placeIndex: int) :
    bool =
  not legendItems[placeIndex][0].isDeadKey

method check(self: ref CondNoLegendAtPlace, legendItems: openArray[array[2, LegendItem]], placeIndex: int) :
    bool =
  legendItems[self.place][0].string == "" and legendItems[self.place][0].image == nil

method check(self: ref CondNotConfusableWith, legendItems: openArray[array[2, LegendItem]], placeIndex: int) :
    bool =
  not areStringsConfusables(legendItems[placeIndex][0].string, legendItems[self.place][0].string)


proc getCondition*(node: JsonNode): ref Condition = # {.unique.}
  if node.len != 1:
    echo "Invadid condition"
    return nil

  case node.kind:
    of JObject:
      var key {.noinit.}: string
      for itemKey in node.keys: key = itemKey

      case key:
        of "and":
          var cond = (ref CondAnd)()
          for item in node["and"]:
            cond.conds.add item.getCondition
          return cond
        of "or":
          var cond=  (ref CondOr)()
          for item in node["or"]:
            cond.conds.add item.getCondition
          return cond
        of "not": return (ref CondNot)(cond: node["not"].getCondition)
        of "isNotDeadKey": return (ref CondIsNotDeadKey)()
        of "noLegendAtPlace": return (ref CondNoLegendAtPlace)(place: node["noLegendAtPlace"].getInt)
        of "notConfusableWith": return (ref CondNotConfusableWith)(place: node["notConfusableWith"].getInt)
        else:
          echo "Invalid condition"
          return nil
    else:
      echo "Invalid condition"
      return nil
