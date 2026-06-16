// Metro config so the example resolves the package from the repo root (one level
// up) instead of a published copy — changes are picked up live.
const path = require('path');
const { getDefaultConfig } = require('expo/metro-config');

const projectRoot = __dirname;
const moduleRoot = path.resolve(projectRoot, '..');

const config = getDefaultConfig(projectRoot);

config.watchFolders = [moduleRoot];
config.resolver.nodeModulesPaths = [
  path.resolve(projectRoot, 'node_modules'),
  path.resolve(moduleRoot, 'node_modules'),
];
config.resolver.disableHierarchicalLookup = true;

module.exports = config;
