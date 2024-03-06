import _loadConfig from 'tailwindcss/lib/lib/load-config.js';
import resolveConfig from 'tailwindcss/resolveConfig.js';
import { resolve } from 'path';

const config = _loadConfig.loadConfig(resolve(process.argv[2]));

process.stdout.write(JSON.stringify({
  resolved: {
    ...resolveConfig(config),
    plugins: undefined, // not introspecting raw config past what was already resolved
  },
}));
