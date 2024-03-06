import { readFileSync } from 'fs';
import { join } from 'path';
import { profileFloatOrPercent, profileFontWeight, profileBoxShadowValue, profileOpacityValue, profileZIndex, profileRotateValue, profileLengthValue, profileColorValue } from './profilers.js';

const baselineConfig = JSON.parse(readFileSync(join(process.argv[2], 'extract-tailwind-config-baseline.json')));
let effectiveConfig;

try {
  // found occasional console.log or debug write from the build; e.g. github.com/HugoBlox/hugo-blox-builder/bWFpbgo/bW9kdWxlcy9ibG94LXRhaWx3aW5kCg
  // for now silently ignore
  effectiveConfig = JSON.parse(readFileSync(join(process.argv[2], 'extract-tailwind-config-effective.json')));
} catch (err) {
  process.stderr.write(`[analyze-tailwind-changes] ERROR: ${err}\n`)
  process.exit(0);
}

const results = [];

[
  // capture content path conventions
  (baseline, effective) => {
    const extension1 = /\.\{([^}]+)\}$/
    const extension2 = /\.([^\.]+)$/

    const foundExtensions = [];

    for (const glob of [...new Set([
      ...(effective.resolved.content?.files || []),
      // old, v2
      ...(effective.resolved.purge?.content || []),
    ])]) {
      if (typeof glob != 'string') {
        continue;
      }

      results.push({
        contentFilesPathGlob: {
          glob,
        },
      });

      const globBase = glob.split('/').slice(-1)[0];

      // naive; official library probably has better introspection

      const extension1match = globBase.match(extension1);
      if (extension1match) {
        extension1match[1].split(/\s*,\s*/).map(ext => {
          if (!foundExtensions.includes(ext)) {
            foundExtensions.push(ext);
          }
        });
      } else {
        const extension2match = globBase.match(extension2);
        if (extension2match) {
          if (!foundExtensions.includes(extension2match[1])) {
            foundExtensions.push(extension2match[1]);
          }
        }
      }
    }

    foundExtensions.filter(Boolean).map(ext => {
      results.push({
        contentFilesPathExt: {
          ext,
        },
      });
    });
  },
  // capture core plugin reconfigurations
  (baseline, effective) => {
    // 1.x supported corePlugins as object; lazy ignoring for now
    if (typeof baseline.resolved.corePlugins == 'object' && !Array.isArray(baseline.resolved.corePlugins)) {
      return;
    }

    for (const plugin of [...new Set([
      ...baseline.resolved.corePlugins,
      ...effective.resolved.corePlugins,
    ])]) {
      const baselineEnabled = baseline.resolved.corePlugins.includes(plugin);
      const effectiveEnabled = effective.resolved.corePlugins.includes(plugin);

      if (baselineEnabled == effectiveEnabled) {
        continue;
      }

      results.push({
        corePlugin: {
          plugin,
          configAction: 'UPDATE',
          effectiveEnabled,
        },
      });
    }
  },
  // capture prefix usage
  (baseline, effective) => {
    if (JSON.stringify(baseline.resolved.prefix) == JSON.stringify(effective.resolved.prefix)) {
      return;
    }

    results.push({
      prefix: {
        configAction: 'UPDATE',
        configValue: JSON.stringify(effective.resolved.prefix),
      },
    });
  },
  // capture separator usage
  (baseline, effective) => {
    if (JSON.stringify(baseline.resolved.separator) == JSON.stringify(effective.resolved.separator)) {
      return;
    }

    results.push({
      separator: {
        configAction: 'UPDATE',
        configValue: JSON.stringify(effective.resolved.separator),
      },
    });
  },
  // capture simple key-value settings
  // (.+): ResolvableTo<KeyValuePair> from https://github.com/tailwindlabs/tailwindcss/blob/master/types/config.d.ts
  (baseline, effective) => {
    const themeKeyValueProfilers = {
      animation: null,
      aspectRatio: null,
      backgroundImage: null,
      backgroundPosition: null,
      backgroundSize: null,
      blur: profileLengthValue,
      borderRadius: profileLengthValue,
      borderWidth: profileLengthValue,
      boxShadow: profileBoxShadowValue,
      brightness: null,
      columns: null,
      content: null,
      contrast: null,
      cursor: null,
      flex: null,
      flexGrow: null,
      flexShrink: null,
      fontWeight: profileFontWeight,
      grayscale: null,
      gridAutoColumns: null,
      gridAutoRows: null,
      gridColumn: null,
      gridColumnEnd: null,
      gridColumnStart: null,
      gridRow: null,
      gridRowEnd: null,
      gridRowStart: null,
      gridTemplateColumns: null,
      gridTemplateRows: null,
      hueRotate: profileRotateValue,
      invert: null,
      letterSpacing: profileLengthValue,
      lineHeight: profileLengthValue,
      listStyleType: null,
      maxWidth: profileLengthValue,
      minHeight: profileLengthValue,
      minWidth: profileLengthValue,
      objectPosition: null,
      opacity: profileOpacityValue,
      order: null,
      outlineOffset: profileLengthValue,
      outlineWidth: profileLengthValue,
      ringOffsetWidth: profileLengthValue,
      ringWidth: profileLengthValue,
      rotate: profileRotateValue,
      saturate: null,
      scale: profileFloatOrPercent,
      sepia: null,
      skew: profileRotateValue,
      spacing: profileLengthValue,
      strokeWidth: profileLengthValue,
      textDecorationThickness: profileLengthValue,
      textUnderlineOffset: profileLengthValue,
      transformOrigin: null,
      transitionDelay: null,
      transitionDuration: null,
      transitionProperty: null,
      transitionTimingFunction: null,
      willChange: null,
      zIndex: profileZIndex,
    }

    for (const property of Object.keys(themeKeyValueProfilers)) {
      const baselineProperty = baseline.resolved.theme[property];
      const effectiveProperty = effective.resolved.theme[property];

      const propertyProfileFunc = themeKeyValueProfilers[property];
      const propertyChangeKey = `theme${property.substring(0, 1).toUpperCase()}${property.substring(1)}`

      for (const name of [...new Set([
        ...Object.keys(baselineProperty || {}),
        ...Object.keys(effectiveProperty || {}),
      ])]) {
        const baselineValue = baseline.resolved.theme[property]?.[name];
        const effectiveValue = effective.resolved.theme[property]?.[name];
        
        if (JSON.stringify(baselineValue) == JSON.stringify(effectiveValue)) {
          continue;
        }

        let baselineProfile = {};
        let effectiveProfile = {};

        if (propertyProfileFunc) {
          baselineProfile = propertyProfileFunc(baselineValue) || {};
          effectiveProfile = propertyProfileFunc(effectiveValue) || {};

          if (Object.keys(baselineProfile).length > 0 && Object.keys(effectiveProfile).length > 0 && JSON.stringify(baselineProfile) == JSON.stringify(effectiveProfile)) {
            continue;
          }
        }

        if (baselineValue && !effectiveValue) {
          results.push({
            [propertyChangeKey]: {
              name,
              configAction: 'DELETE',
            },
          });
        } else {
          results.push({
            [propertyChangeKey]: {
              name,
              configAction: !baselineValue ? 'CREATE' : 'UPDATE',
              configValue: JSON.stringify(effectiveValue),
              valueProfile: Object.keys(effectiveProfile).length > 0 ? effectiveProfile : undefined,
            },
          })
        }
      }
    }
  },
  // screens
  (baseline, effective) => {
    function norm(v) {
      // reinventing conversion; should import utilities
      if (typeof v == 'string') {
        return {
          raw: `min-width: ${v}`,
          twcrMatcher: 'string',
        };
      } else if ('raw' in v) {
        return {
          ...v,
          twcrMatcher: 'object-raw',
        };
      }

      return {
        ...v,
        raw: [
          'min' in v ? `min-width: ${v.min}` : undefined,
          'max' in v ? `max-width: ${v.max}` : undefined,
        ].filter(Boolean).join(' and '),
        twcrMatcher: 'object',
      };
    }

    for (const name of [...new Set([
      ...Object.keys(baseline.resolved.theme.screens),
      ...Object.keys(effective.resolved.theme.screens),
    ])]) {
      const baselineScreen = baseline.resolved.theme.screens[name];
      const effectiveScreen = effective.resolved.theme.screens[name];

      if (JSON.stringify(baselineScreen) == JSON.stringify(effectiveScreen)) {
        continue;
      }

      const baselineScreenNorm = baselineScreen ? norm(baselineScreen) : undefined;
      const effectiveScreenNorm = effectiveScreen ? norm(effectiveScreen) : undefined;
      
      if (baselineScreen && !effectiveScreen) {
        results.push({
          themeScreen: {
            name,
            configAction: 'DELETE',
          },
        });
      } else if (!baselineScreen && effectiveScreen) {
        results.push({
          themeScreen: {
            name,
            configAction: 'CREATE',
            valueProfile: effectiveScreenNorm,
          },
        });
      } else {
        results.push({
          themeScreen: {
            name,
            configAction: 'UPDATE',
            valueProfile: effectiveScreenNorm,
          },
        });
      }
    }
  },
  // colors
  (baseline, effective) => {
    function flat(color, value) {
      if (typeof value == 'string') {
        return [
          [
            color,
            value,
          ],
        ];
      }

      return Object.entries(value).map(vk => (
        typeof vk[1] == 'object'
          ? flat(`${color}-${vk[0]}`, vk[1])
          : [[
            `${color}-${vk[0]}`,
            vk[1],
          ]]
      )).flat(1);
    }

    const baselineColors = Object.fromEntries(Object.entries(baseline.resolved.theme.colors).map(kv => flat(kv[0], kv[1])).flat(1));
    const effectiveColors = Object.fromEntries(Object.entries(effective.resolved.theme.colors).map(kv => flat(kv[0], kv[1])).flat(1));

    for (const name of [...new Set([
      ...Object.keys(baselineColors),
      ...Object.keys(effectiveColors),
    ])]) {
      const baselineColor = baselineColors[name];
      const effectiveColor = effectiveColors[name];

      if (JSON.stringify(baselineColor) == JSON.stringify(effectiveColor)) {
        continue;
      } else if (baselineColor && !effectiveColor) {
        results.push({
          themeColor: {
            name,
            configAction: 'DELETE',
          },
        });
      } else {
        results.push({
          themeColor: {
            name,
            configAction: !baselineColor ? 'CREATE' : 'UPDATE',
            configValue: JSON.stringify(effectiveColor),
            valueProfile: profileColorValue(effectiveColor),
          },
        });
      }
    }
  },
  // color collections (easier to measure color name generic usage)
  (baseline, effective) => {
    const baselineColors = Object.fromEntries(Object.entries(baseline.resolved.theme.colors).filter(kv => typeof kv[1] == 'object'));
    const effectiveColors = Object.fromEntries(Object.entries(effective.resolved.theme.colors).filter(kv => typeof kv[1] == 'object'));

    for (const name of [...new Set([
      ...Object.keys(baselineColors),
      ...Object.keys(effectiveColors),
    ])]) {
      const baselineColor = baselineColors[name];
      const effectiveColor = effectiveColors[name];

      if (JSON.stringify(baselineColor) == JSON.stringify(effectiveColor)) {
        continue;
      } else if (baselineColor && !effectiveColor) {
        results.push({
          themeColorCollection: {
            name,
            configAction: 'DELETE',
          },
        });
      } else if (!baselineColor && effectiveColor) {
        const createdNames = Object.keys(effectiveColor);

        results.push({
          themeColorCollection: {
            name,
            configAction: 'CREATE',
            valueProfile: {
              createdNamesCount: createdNames.length,
              createdNames,
            }
          },
        });
      } else {
        const updatedNames = Object.entries(effectiveColor).filter(kv => baselineColor[kv[0]] != kv[1]).map(kv => kv[0]);

        results.push({
          themeColorCollection: {
            name,
            configAction: 'UPDATE',
            valueProfile: {
              updatedNamesCount: updatedNames.length,
              updatedNames,
            }
          },
        });
      }
    }
  },
  // font-family usage
  (baseline, effective) => {
    function norm(values) {
      if (!values) {
        return values;
      }

      // apparently possible to be strings; https://github.com/railwayapp/nixpacks/blob/2ec70b75709af40db28762a77a3c98aaaebb09ad/docs/tailwind.config.js
      if (typeof values == 'string') {
        return norm(values.split(/\s*,\s*/));
      } else if (typeof values != 'object' || !Array.isArray(values)) {
        process.stderr.write(`[resultparser] WARN: fontFamily: unrecognized values type (${JSON.stringify(values)})\n`);
        return values;
      }
      
      // seems like it is sometimes arrays of arrays
      // seems like it sometimes contains a null
      return values.flat().filter(Boolean).map(value => {
        if (typeof value != 'string') {
          process.stderr.write(`[resultparser] WARN: fontFamily: unrecognized value type (${JSON.stringify(value)}) for values (${JSON.stringify(values)})\n`);

          return value;
        }

        // officially should be quoted, but commonly not; normalize to avoid noisy diffs
        const quoted = value.match(/^(['"])(.+)\1$/);
        if (quoted) {
          return quoted[2];
        }

        return value;
      });
    }

    for (const name of [...new Set([
      ...Object.keys(baseline.resolved.theme.fontFamily),
      ...Object.keys(effective.resolved.theme.fontFamily),
    ])]) {
      let baselineFontFamily = norm(baseline.resolved.theme.fontFamily[name]);
      let effectiveFontFamily = norm(effective.resolved.theme.fontFamily[name]);

      if (JSON.stringify(baselineFontFamily) == JSON.stringify(effectiveFontFamily)) {
        continue;
      } else if (baselineFontFamily && !effectiveFontFamily) {
        results.push({
          themeFontFamily: {
            name,
            configAction: 'DELETE',
          },
        });
      } else if (!baselineFontFamily && effectiveFontFamily) {
        results.push({
          themeFontFamily: {
            name,
            configAction: 'CREATE',
            valueProfile: {
              createdValuesCount: effectiveFontFamily.length,
              createdValues: effectiveFontFamily,
            },
          },
        });
      } else {
        const addedValues = effectiveFontFamily.filter(v => !baselineFontFamily.includes(v));
        const removedValues = baselineFontFamily.filter(v => !effectiveFontFamily.includes(v));

        results.push({
          themeFontFamily: {
            name,
            configAction: 'UPDATE',
            valueProfile: {
              valuesCount: effectiveFontFamily.length,
              values: effectiveFontFamily,
              addedValues: addedValues.length > 0 ? addedValues : undefined,
              addedValuesCount: addedValues.length > 0 ? addedValues.length : undefined,
              removedValues: removedValues.length > 0 ? removedValues : undefined,
              removedValuesCount: removedValues.length > 0 ? removedValues.length : undefined,
            },
          },
        });
      }
    }
  },
  // property-variants
  // seems unstable; baseline or effective often missing value
  // (baseline, effective) => {
  //   for (const property of [...new Set([
  //     ...Object.keys(baseline.resolved.variants || {}),
  //     ...Object.keys(effective.resolved.variants || {}),
  //   ])]) {
  //     for (const variant of [...new Set([
  //       ...Object.keys(baseline.resolved.variants && baseline.resolved.variants[property] || {}),
  //       ...Object.keys(effective.resolved.variants && effective.resolved.variants[property] || {}),
  //     ])]) {
  //       const baselineExists = (baseline.resolved.variants && baseline.resolved.variants[property] || []).includes(variant);
  //       const effectiveExists = (effective.resolved.variants && effective.resolved.variants[property] || []).includes(variant);

  //       if (baselineExists == effectiveExists) {
  //         continue;
  //       }

  //       results.push({
  //         variant: {
  //           property,
  //           variant,
  //           configAction: baselineExists ? 'DELETE' : 'CREATE',
  //         },
  //       });
  //     }
  //   }
  // },
].map(fn => fn(baselineConfig, effectiveConfig));

results.map(r => console.log(JSON.stringify(r)));
