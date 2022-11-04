const rootConfig = require("./build.webpack.config.mjs");
const merge = require('deepmerge');
const isPlainObject = require('is-plain-object');
const path = require('path');
const glob = require("glob");

const testPath = path.resolve(__dirname, "test");
const testBuildPath = path.resolve(__dirname, "test_build/");

// Use the same config as the main build but change the settings below
module.exports = merge(rootConfig,{
  entry: (() => {
      var entries = {};
      glob.sync(path.resolve(testPath, "**/*.js")).forEach(val => {
          entries[val] = val;
      });
      Object.setPrototypeOf(entries,null); //Make not a plain object
      return entries;
  })(),
  output: {
    path: testBuildPath
  },
  externals: {
    tape: 'tape',
    nock: 'nock'
  }
},{
	isMergeableObject: isPlainObject
});
