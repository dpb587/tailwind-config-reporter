#!/bin/bash

set -euo pipefail

properties=(
  color
  # copied from ./transformer/tailwind-changes-analyzer/run.mjs
  spacing
  zIndex
  order
  gridColumn
  gridColumnStart
  gridColumnEnd
  gridRow
  gridRowStart
  gridRowEnd
  aspectRatio
  minHeight
  maxWidth
  minWidth
  flex
  flexShrink
  flexGrow
  transformOrigin
  rotate
  skew
  scale
  animation
  cursor
  listStyleType
  columns
  gridAutoColumns
  gridAutoRows
  gridTemplateColumns
  gridTemplateRows
  borderRadius
  borderWidth
  backgroundImage
  backgroundSize
  backgroundPosition
  strokeWidth
  objectPosition
  fontWeight
  lineHeight
  letterSpacing
  textDecorationThickness
  textUnderlineOffset
  opacity
  boxShadow
  outlineWidth
  outlineOffset
  ringWidth
  ringOffsetWidth
  blur
  brightness
  contrast
  grayscale
  hueRotate
  invert
  saturate
  sepia
  transitionProperty
  transitionTimingFunction
  transitionDelay
  transitionDuration
  willChange
  content
)

for property in "${properties[@]}"
do
  known="$(
    sqlite3 mnt/dataset/aggregate/db.sqlite \
      "
        SELECT name
        FROM pragma_table_info('tailwind_changes')
        WHERE name LIKE 'theme${property}\_%' ESCAPE '\'
      "
  )"

  if [[ -z "${known}" ]]
  then
    # properties may not have been enumerated
    continue
  fi

  outfile=/dev/stdout

  if ! [ -z "${1:-}" ]
  then
    outfile="${1}/theme-${property}.md"
  fi

  (
    echo "# Theme (${property})"

    echo
    ./aggregator/exporter/common/kv-config-actions.sh "${property}"

    if grep -q "_configValue" <<<"${known}"
    then
      echo
      echo '## Updated Names'
      echo

      ./aggregator/exporter/common/kv-config-action-values.sh "${property}" UPDATE

      echo
      echo '## Additional Names'
      echo

      ./aggregator/exporter/common/kv-config-action-values.sh "${property}" CREATE
    fi

    if grep -q "_valueProfile_" <<<"${known}"
    then
      echo
      echo '## Value Conventions'
      echo

      ./aggregator/exporter/common/kv-config-profile-flags.sh "theme${property}"
    fi

    echo
    echo '## Deleted Names'
    echo

    ./aggregator/exporter/common/kv-config-delete-names.sh "${property}"
  ) > "${outfile}"
done
