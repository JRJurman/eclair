/*
 * eclair - weak typechecking for the web backend's JS library
 */

var fs = require("fs");
var path = process.argv[2];
var lib = null;

/* the two globals a --js-library file expects to find */
global.LibraryManager = { library: {} };
global.mergeInto = function (target, obj) { lib = obj; };

eval(fs.readFileSync(path, "utf8"));

var keys = Object.keys(lib);
var bad = 0;

function fail(message) {
	console.error(path + ": " + message);
	bad++;
}

keys.forEach(function (key) {
	// a decorator has to name a key that exists
	var decorates = key.match(/^(.+?)__[a-z]+$/);
	if (decorates && keys.indexOf(decorates[1]) === -1) {
		fail(key + " decorates " + decorates[1] + ", which is not defined here");
	}

	// __deps written with one underscore is a malformed key
	if (/[^_]_deps$/.test(key)) {
		fail(key + " should be " + key.replace(/_deps$/, "__deps"));
	}

	// the $ prefix is for naming a JS-only value in __deps
	if (typeof lib[key] === "function" && /\$[A-Za-z_]/.test(String(lib[key]))) {
		fail("$ prefix used inside " + key + " - drop it when reading the value");
	}
});

process.exit(bad === 0 ? 0 : 1);
