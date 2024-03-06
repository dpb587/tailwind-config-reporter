const resolveConfig = require('tailwindcss/resolveConfig.js');

const config = require(`./${process.argv[2]}`);

process.stdout.write(JSON.stringify({
  resolved: {
    ...resolveConfig(config),
    plugins: undefined, // not introspecting raw config past what was already resolved
  },
}));
