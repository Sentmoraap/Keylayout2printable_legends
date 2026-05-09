import std/[parseutils, strutils, tables, unicode]
import normalize

include prelude

var table: Table[Rune, string]

proc load*(verbose: bool) =
  table = initTable[Rune, string]()

  if verbose: echo "Loading confusables"

  if not (proc(): bool =
    try:
      for line in "confusables.txt".lines:
        let hashPos = line.find '#'
        let firstSemicolonPos = line.find ';'
        if firstSemicolonPos != -1 and (hashPos == -1 or firstSemiColonPos < hashPos):
          let secondSemicolonPos = line.find(';', firstSemicolonPos + 1)
          if secondSemicolonPos != -1 and (hashPos == -1 or secondSemicolonPos < hashPos):
            var c = 0
            if parseHex(line[0..<firstSemicolonPos], c) == 0: 
              if verbose:
                echo "Error while parsing first column hex number. notConfusableWith condition will always be true."
              return false
            let r = c.Rune
            var s = ""
            var pos = firstSemicolonPos + 1
            while true:
              pos += line[pos..<secondSemicolonPos].skipWhitespace
              let advance = parseHex(line[pos..<secondSemicolonPos], c)
              if advance == 0: break
              pos += advance
              s.add(c.Rune)
            if s == "":
              if verbose:
                echo "Error while parsing second column hex numbers. notConfusableWith condition will always be true."
              return false
            table[r] = s
    except IOError:
      if verbose:
        echo "Can't read confusables.txt. notConfusableWith condition will always be true."
      return false
    true)():
      table = initTable[Rune, string]()


# Detect according to http://www.unicode.org/reports/tr39/#Confusable_Detection
# Skip step 2 (Default_Ignorable_Code_Point), probably not needed and would require extra unicode support

proc internalSkeleton(s: string): string =
  let runes = s.toNFD.toRunes
  result = ""
  for r in runes:
    if r in table: result.add table[r] else: result.add r
  result = result.toNFD

proc areStringsConfusables*(a, b: string): bool =
  internalSkeleton(a) == internalSkeleton(b)
