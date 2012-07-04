shalow = (from, to) ->
  to[key] = value for key, value of from
  to
serializeArray = (a) -> "['#{a.join "','"}']"
rmext = (p) ->
  for k of require.extensions
    (return p.substr 0, p.length-k.length) if p.substr(p.length-k.length) is k
  p
readCode = (filename) -> 
  code = ''
  extfunc = require.extensions[path.extname(filename)]
  extfunc {_compile: (code_) -> code = code_}, filename
  code
file = process.argv[2]
require file
cache = shalow require.cache, {}
find = (id) ->
  obj = cache[id]
  delete cache[id]
  l =  (find v.id for v in obj.children)
  l = l.reduce((a,b) -> a.concat b) if l.length > 0
  l.concat([obj])
ordered = find __filename
baseObj = ordered.pop()
# OK to load other modules
fs = require 'fs'
path = require 'path'
tounix = (p) -> path.normalize(p).replace /\\/g, '/'
resolvePaths = (paths) -> (tounix path.relative(dir, p) for p in paths)
findPackageJson = (start) ->
dir = path.resolve __dirname, path.dirname file
serve = (code) ->
  """
  (function(everything){
    var res={};
    function normalizeArray(parts, allowAboveRoot) {
      // if the path tries to go above the root, `up` ends up > 0
      var up = 0;
      for (var i = parts.length - 1; i >= 0; i--) {
        var last = parts[i];
        if (last == '.') {
          parts.splice(i, 1);
        } else if (last === '..') {
          parts.splice(i, 1);
          up++;
        } else if (up) {
          parts.splice(i, 1);
          up--;
        }
      }

      // if the path is allowed to go above the root, restore leading ..s
      if (allowAboveRoot) {
        for (; up--; up) {
          parts.unshift('..');
        }
      }

      return parts;
    }
    function resolve() {
      var resolvedPath = '',
          resolvedAbsolute = false;

      for (var i = arguments.length - 1; i >= -1 && !resolvedAbsolute; i--) {
        var path = (i >= 0) ? arguments[i] : '';

        // Skip empty and invalid entries
        if (typeof path !== 'string' || !path) {
          continue;
        }

        resolvedPath = path + '/' + resolvedPath;
        resolvedAbsolute = path.charAt(0) === '/';
      }

      // At this point the path should be resolved to a full absolute path, but
      // handle relative paths to be safe (might happen when process.cwd() fails)

      // Normalize the path
      resolvedPath = normalizeArray(resolvedPath.split('/').filter(function(p) {
        return !!p;
      }), !resolvedAbsolute).join('/');

      return ((resolvedAbsolute ? '/' : '') + resolvedPath) || '.';
    }

    function emulateRequire(dirname,paths){
      function require(path){
        if (path.substr(0,1)==='.'){
          return res[resolve(dirname, path)];
        }else{
          for (var i=0;i<paths.length;i++){
            relfilename = paths[i]+'/'+path;
            if (res[relfilename]){
              return res[relfilename];
            }
          }
        }
      }
      return require;
    }
    function register(name,dirname,paths,factory){
      var module={exports:{}};
      factory.call(this,emulateRequire(dirname,paths),module.exports,module);
      res[dirname+'/'+name]=module.exports;
    }
    everything.call(this,register);
    window.boiler=emulateRequire(#{serializeArray resolvePaths baseObj.paths});
  }).call(this,function(register){
  #{code}
  });
  """
boil = (obj) ->
  name = rmext path.basename obj.filename
  rfilename = tounix path.relative dir, obj.filename
  modulePath = path.dirname rfilename
  #modulePath = './'+rmext(rfilename) if modulePath.indexOf('node_modules') < 0
  paths = resolvePaths obj.paths
  code = readCode obj.filename
  """
  register.call(this,'#{name}','#{modulePath}',#{serializeArray paths},
  function(require,exports,module){
  #{code}
  });
  """

process.stdout.write serve (boil obj for obj in ordered).join '\n'
