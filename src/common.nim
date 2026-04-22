import pixie

include prelude

type
  Condition* = object of RootObj

  LegendItem* = object
    string*: string # Unicode NFC, with NFD and bad fonts accents are misplaced
    translate* = vec2()
    translateMirrored* = vec2()
    scale* = vec2(1)
    image*: Image
    color*: Color
    isDeadKey* = false
    isNonGraphic* = false
