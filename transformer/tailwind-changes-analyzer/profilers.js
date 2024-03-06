// some spec-ish, naive functions to extract more meaningful properties

function collectCssVariables(v) {
  if (typeof v != 'string') {
    return;
  }

  const matches = v.matchAll(/var\(\s*([^,\)]+)/g);
  if (!matches) {
    return;
  }

  return Array.from(matches).map(v => v[1]);
}

function profileCssFunctions(v) {
  if (typeof v != 'string') {
    return;
  }

  const profile = {};

  if (v.indexOf('calc(') > -1) {
    profile.cssFunctionCalc = true;
  }

  if (v.indexOf('var(') > -1) {
    profile.cssFunctionVar = true;
    profile.cssVariableNames = collectCssVariables(v);
  }

  if (Object.keys(profile).length == 0) {
    return;
  }

  return {
    ...profile,
    cssFunction: true,
  };
}

function tokenizeBoxShadow(v) {
  const entries = [];
  let entryCurrent = [];

  const tokens = v;
  let tokenBuild = [];
  let tokenDepth = 0;

  for (let idx = 0; idx < tokens.length; idx++) {
    const token = tokens.substring(idx, idx+1);

    if (token.match(/\s+/)) {
      if (tokenBuild.length == 0) {
        continue;
      } else if (tokenDepth == 0) {
        entryCurrent.push(tokenBuild.join(''));
        tokenBuild = [];

        continue;
      }
    } else if (token == ',') {
      if (tokenDepth == 0) {
        if (tokenBuild.length > 0) {
          entryCurrent.push(tokenBuild.join(''));
          tokenBuild = [];
        }

        entries.push(entryCurrent);
        entryCurrent = [];

        continue;
      }
    } else if (token == '(') {
      tokenDepth++;
    } else if (token == ')') {
      tokenDepth--;
    }

    tokenBuild.push(token);
  }

  if (tokenBuild.length > 0) {
    entryCurrent.push(tokenBuild.join(''));
  }

  if (entryCurrent.length > 0) {
    entries.push(entryCurrent);
  }

  return entries;
}

function profileFontWeight(v) {
  if (typeof v == 'number') {
    return {
      number: v,
    };
  } else if (typeof v != 'string') {
    return;
  } else if (v.match(/^[a-z\-]+$/)) {
    return {
      keyword: v,
    };
  }

  const dynamicCssProfile = profileCssFunctions(v);
  if (dynamicCssProfile) {
    return dynamicCssProfile;
  }

  try {
    return {
      number: parseInt(v),
    };
  } catch (e) {
    process.stderr.write(`[resultparser] WARN: profileFontWeight: failed due to invalid number (${JSON.stringify(v)})\n`);

    return;
  }
}

function profileBoxShadowValue(v) {
  if (typeof v != 'string') {
    return;
  }

  const entries = [];

  for (const rawEntry of tokenizeBoxShadow(v)) {
    if (rawEntry.length == 1) {
      // should validate
      entries.push({
        keyword: rawEntry[0],
      });

      continue;
    }

    const entry = {};
    let entryLengths = [];

    for (const rawEntryToken of rawEntry) {
      if (rawEntryToken == 'inset') {
        entry.inset = true;

        continue;
      }

      const maybeLength = profileLengthValue(rawEntryToken);
      if (maybeLength) {
        entryLengths.push(maybeLength);

        continue;
      }

      const maybeColor = profileColorValue(rawEntryToken);
      if (maybeColor) {
        entry.color = maybeColor;

        continue;
      }

      process.stderr.write(`[resultparser] WARN: profileBoxShadowValue: failed due to unrecognized token (${JSON.stringify(rawEntryToken)}) for entry (${JSON.stringify(rawEntry)})\n`);

      return;
    }

    if (!entry.color) {
      // insufficient, but try and assume a single, dynamic css is for color and backfill it
      if (entryLengths.filter(v => v.cssFunction).length == 1) {
        const dynamicEntryIndex = entryLengths.findIndex(v => v.cssFunction);

        // further limit it to first or last entry
        if (dynamicEntryIndex == 0) {
          entry.color = entryLengths[0];
          entryLengths = entryLengths.slice(1);
        } else if (dynamicEntryIndex == (entryLengths.length - 1)) {
          entry.color = entryLengths.pop();
        }
      }

      if (!entry.color) {
        process.stderr.write(`[resultparser] WARN: profileBoxShadowValue: failed due to missing color for entry (${JSON.stringify(rawEntry)})\n`);
      }

      return;
    }

    switch (entryLengths.length) {
    case 4:
      entry.spreadRadius = entryLengths[3];
      // intentional next
    case 3:
      entry.blurRadius = entryLengths[2];
      // intentional next
    case 2:
      entry.offsetX = entryLengths[0];
      entry.offsetY = entryLengths[1];

      break;
    default:
      process.stderr.write(`[resultparser] WARN: profileBoxShadowValue: failed due to unrecognized length values (${JSON.stringify(entryLengths)}) for entry (${JSON.stringify(rawEntry)})\n`);

      return;
    }

    entries.push(entry);
  }

  if (entries.length == 0) {
    return;
  }

  return {
    entriesCount: entries.length,
    entriesFirst: entries[0],
    entries: entries.length > 1 ? entries.slice(1) : undefined,
  }
}

function profileFloatOrPercent(v) {
  if (typeof v == 'number') {
    return {
      number: v,
    };
  } else if (typeof v != 'string') {
    return;
  } else if (v.endsWith('%')) {
    try {
      return {
        number: parseFloat(v.substring(0, -1)),
        unit: '%',
      };
    } catch (e) {
      process.stderr.write(`[resultparser] WARN: profileFloatOrPercent: failed due to invalid percent number (${JSON.stringify(v)})\n`);

      return;
    }
  }

  const dynamicCssProfile = profileCssFunctions(v);
  if (dynamicCssProfile) {
    return dynamicCssProfile;
  }

  try {
    return {
      number: parseFloat(v),
      unit: 'none',
    };
  } catch (e) {
    process.stderr.write(`[resultparser] WARN: profileFloatOrPercent: failed due to invalid number (${JSON.stringify(v)})\n`);

    return;
  }
}

function profileOpacityValue(v) {
  if (typeof v == 'number') {
    return {
      number: v,
    };
  } else if (typeof v != 'string') {
    return;
  } else if (v.endsWith('%')) {
    try {
      return {
        number: parseFloat(v.substring(0, -1)),
        unit: '%',
      };
    } catch (e) {
      process.stderr.write(`[resultparser] WARN: profileOpacityValue: failed due to invalid percent number (${JSON.stringify(v)})\n`);

      return;
    }
  } else if (v.match(/^[a-z\-]+$/)) {
    return {
      keyword: v,
    };
  }

  const dynamicCssProfile = profileCssFunctions(v);
  if (dynamicCssProfile) {
    return dynamicCssProfile;
  }

  try {
    return {
      number: parseFloat(v),
      unit: 'none',
    };
  } catch (e) {
    process.stderr.write(`[resultparser] WARN: profileOpacityValue: failed due to invalid number (${JSON.stringify(v)})\n`);

    return;
  }
}

function profileZIndex(v) {
  if (typeof v == 'number') {
    return {
      number: v,
    };
  } else if (typeof v != 'string') {
    return;
  } else if (v.match(/^[a-z\-]+$/)) {
    return {
      keyword: v,
    };
  }

  const dynamicCssProfile = profileCssFunctions(v);
  if (dynamicCssProfile) {
    return dynamicCssProfile;
  }

  try {
    return {
      number: parseInt(v),
      unit: 'none',
    };
  } catch (e) {
    process.stderr.write(`[resultparser] WARN: profileZIndex: failed due to invalid number (${JSON.stringify(v)})\n`);

    return;
  }
}

function profileRotateValue(v) {
  if (typeof v == 'number') {
    if (v == 0) {
      return {
        number: v,
        unit: 'none',
      };
    }

    process.stderr.write(`[resultparser] WARN: profileRotateValue: failed due to number value missing unit (${JSON.stringify(v)})\n`);

    return;
  } else if (typeof v != 'string') {
    return;
  } else if (v == '0') {
    return {
      number: 0,
      unit: 'none',
    };
  }

  const dynamicCssProfile = profileCssFunctions(v);
  if (dynamicCssProfile) {
    return dynamicCssProfile;
  }

  // https://developer.mozilla.org/en-US/docs/Web/CSS/angle
  const naiveMatcher = /^\s*([+\-]?[\d\.]+)(deg|grad|rad|turn)\s*$/;
  const m = v.match(naiveMatcher);
  if (!m) {
    return;
  }

  return {
    number: parseFloat(m[1]),
    unit: m[2],
  };
}

function profileLengthValue(v) {
  if (typeof v == 'number') {
    if (v == 0) {
      return {
        number: v,
        unit: 'none',
      };
    }

    process.stderr.write(`[resultparser] WARN: profileLengthValue: failed due to number value missing unit (${JSON.stringify(v)})\n`);

    return;
  } else if (typeof v != 'string') {
    return;
  } else if (v == '0') {
    return {
      number: 0,
      unit: 'none',
    };
  } else if (v.match(/^[a-z\-]+$/)) {
    return {
      keyword: v,
    };
  }

  const dynamicCssProfile = profileCssFunctions(v);
  if (dynamicCssProfile) {
    return dynamicCssProfile;
  }

  // https://github.com/tailwindlabs/tailwindcss/blob/4429ab80101bdebcb3e84e817201beb69f05fc3b/src/util/dataTypes.js#L207
  // + %
  const naiveMatcher = /^\s*(\-?[\d\.]+)(%|cm|mm|Q|in|pc|pt|px|em|ex|ch|rem|lh|rlh|vw|vh|vmin|vmax|vb|vi|svw|svh|lvw|lvh|dvw|dvh|cqw|cqh|cqi|cqb|cqmin|cqmax)\s*$/;
  const m = v.match(naiveMatcher);
  if (!m) {
    return;
  }

  return {
    number: parseFloat(m[1]),
    unit: m[2],
  };
}

// lazy matchers; doesn't support named colors, some decimals, alternate percent/number values, more...
const reColorHex = /^\s*#(([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2}))\s*$/i
const reColorHexShort = /^\s*#(([0-9a-f])([0-9a-f])([0-9a-f]))\s*$/i
const reColorRGB = /^\s*rgba?\(\s*(\d+)(\s*,\s*|\s+)(\d+)(\s*,\s*|\s+)(\d+)(\s*[,/]\s*([\d]*(\.\d*)?%?))?\s*\)\s*$/
const reColorHSL = /^\s*hsla?\(\s*(\d+)(\s*,\s*|\s+)(([\d]*(\.\d*)?)%?)(\s*,\s*|\s+)(([\d]*(\.\d*)?)%?)(\s*[,/]\s*([\d]*(\.\d*)?%?))?\s*\)\s*$/
const reColorKeyword = /^\s*([^\s]+)\s*$/;

function profileColorValue(v) {
  function normAlpha(v) {
    if (typeof v != 'string') {
      return {};
    } else if (v.length == 0) {
      return {};
    }

    if (v.endsWith('%')) {
      return {
        alpha: parseFloat(v.replace(/%$/, '')),
      };
    }

    return {
      alpha: parseFloat(v) * 100,
    }
  }

  if (typeof v != 'string') {
    return;
  }

  const dynamicCssProfile = profileCssFunctions(v);
  if (dynamicCssProfile) {
    return dynamicCssProfile;
  }

  const matchHex = v.match(reColorHex);
  if (matchHex) {
    return {
      twcrMatcher: 'hex',
      hex: matchHex[1],
      rgbR: parseInt(`0x${matchHex[2]}`),
      rgbG: parseInt(`0x${matchHex[3]}`),
      rgbB: parseInt(`0x${matchHex[4]}`),
    };
  }

  const matchHexShort = v.match(reColorHexShort);
  if (matchHexShort) {
    return {
      twcrMatcher: 'hex',
      hex: matchHexShort[1],
      rgbR: parseInt(`0x${matchHexShort[2]}${matchHexShort[2]}`),
      rgbG: parseInt(`0x${matchHexShort[3]}${matchHexShort[3]}`),
      rgbB: parseInt(`0x${matchHexShort[4]}${matchHexShort[4]}`),
    };
  }

  const matchRGB = v.match(reColorRGB);
  if (matchRGB) {
    try {
      return {
        twcrMatcher: 'rgb',
        rgbR: parseInt(matchRGB[1]),
        rgbG: parseInt(matchRGB[3]),
        rgbB: parseInt(matchRGB[5]),
        ...normAlpha(matchRGB[7]),
      }
    } catch (err) {
      process.stderr.write(`[resultparser] WARN: profileColorValue: failed to match rgb: ${err}\n`);

      return;
    }
  }

  const matchHSL = v.match(reColorHSL);
  if (matchHSL) {
    try {
      return {
        twcrMatcher: 'hsl',
        hslH: parseInt(matchHSL[1]),
        hslS: parseFloat(matchHSL[4]),
        hslL: parseFloat(matchHSL[8]),
        ...normAlpha(matchHSL[11]),
      }
    } catch (err) {
      process.stderr.write(`[resultparser] WARN: profileColorValue: failed to match hsl: ${err}\n`);

      return;
    }
  }

  const matchKeyword = v.match(reColorKeyword);
  if (matchKeyword) {
    // function is optimistically called for other values
    // for now, only accept limited, known values; should add named- and system-colors
    switch (matchKeyword[1]) {
    case 'transparent':
      return {
        twcrMatcher: 'keyword',
        keyword: matchKeyword[1],
      };
    }
  }
}

module.exports = {
  profileBoxShadowValue,
  profileColorValue,
  profileCssFunctions,
  profileFloatOrPercent,
  profileFontWeight,
  profileLengthValue,
  profileOpacityValue,
  profileRotateValue,
  profileZIndex,
};
