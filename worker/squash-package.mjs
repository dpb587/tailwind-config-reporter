// Patch package.json to only use references found in tailwind.config.js. This is intended to shortcut analysis for
// simple configurations, but does have shortcomings:
// * references to indirect dependencies will fail if the direct dependency is not also referenced
// * module installers may resolve to slightly different versions without the dropped constraints

import { readFileSync, writeFileSync } from 'fs';
import { isBuiltin } from 'node:module';

const tailwindConfigFile = readFileSync(process.argv[2], { encoding: 'utf8' });
const packageData = JSON.parse(readFileSync('package.json', { encoding: 'utf8' }));

const packageUsages = [
  ...(Object.keys(packageData.dependencies || {})),
  ...(Object.keys(packageData.devDependencies || {})),
  ...(Object.keys(packageData.optionalDependencies || {})),
  ...(Object.keys(packageData.peerDependencies || {})),
].reduce((pV, cV) => pV.set(cV, false), new Map());

// base tailwind packages which must be retained, if present, and are unlikely to be referenced by tailwind.config.js
[
  'tailwindcss',
  '@astrojs/tailwind',
  '@nuxtjs/tailwindcss',
].map(v => packageUsages.has(v) && packageUsages.set(v, true));

function processRef(v) {
  if (v.startsWith('./') || v.startsWith('../')) {
    return;
  }

  const vS = v.split('/');

  for (let idx = 0; idx < vS.length; idx++) {
    const vSP = vS.slice(0, idx + 1).join('/');

    if (packageUsages.has(vSP)) {
      packageUsages.set(vSP, true);

      return;
    } else if (isBuiltin(vSP)) {
      return;
    }
  }

  process.stderr.write(`[squash-package] ERROR: failed to find any match for import path (${v})\n`);
  process.exit(1);
}

[
  ...Array.from(tailwindConfigFile.matchAll(/require\s*\(['"]([^'"]+)['"]\)/g) || []).map(v => v[1]),
  ...Array.from(tailwindConfigFile.matchAll(/\s+from\s+['"]([^'"]+)['"]/g) || []).map(v => v[1]),
  ...Array.from(tailwindConfigFile.matchAll(/import\s*\(['"]([^'"]+)['"]\)/g) || []).map(v => v[1]),
].map(v => processRef(v));

function filterPackage(packageData, dependenciesKey) {
  if (!(dependenciesKey in packageData)) {
    return;
  }

  packageData[dependenciesKey] = Object.fromEntries(
    Object.entries(packageData[dependenciesKey]).filter(kv => packageUsages.get(kv[0])),
  );
}

let nextPackageData = {
  ...packageData,
  // avoid postinstall; plus anything else
  scripts: undefined,
};

filterPackage(nextPackageData, 'dependencies');
filterPackage(nextPackageData, 'devDependencies');
filterPackage(nextPackageData, 'optionalDependencies');
filterPackage(nextPackageData, 'peerDependencies');

writeFileSync('package.json', JSON.stringify(nextPackageData, null, '  '));
