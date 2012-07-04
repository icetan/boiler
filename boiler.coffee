shalow = (from, to) ->
  to[key] = value for key, value of from
  to
file = process.argv[2]
require file
cache = shalow require.cache, {}
find = (id) ->
  obj = cache[id]
  #if not obj?
  #  console.log "dead end #{id}"
  #  return
  delete cache[id]
  l =  (find v.id for v in obj.children)
  l = l.reduce((a,b) -> a.concat b) if l.length > 0
  l.concat([obj])
ordered = find __filename
ordered.pop()
# OK to load other modules
fs = require 'fs'
path = require 'path'
dir = path.dirname file
serve = (code) ->
  """
  (function(everything){
    var res={};
    function resp(){
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
      //resolvedPath = normalizeArray(resolvedPath.split('/').filter(function(p) {
      //  return !!p;
      //}), !resolvedAbsolute).join('/');

      return ((resolvedAbsolute ? '/' : '') + resolvedPath) || '.';
    }
    function relp(from,to){
      from = resp(from).substr(1);
      to = resp(to).substr(1);

      function trim(arr) {
        var start = 0;
        for (; start < arr.length; start++) {
          if (arr[start] !== '') break;
        }

        var end = arr.length - 1;
        for (; end >= 0; end--) {
          if (arr[end] !== '') break;
        }

        if (start > end) return [];
        return arr.slice(start, end - start + 1);
      }

      var fromParts = trim(from.split('/'));
      var toParts = trim(to.split('/'));

      var length = Math.min(fromParts.length, toParts.length);
      var samePartsLength = length;
      for (var i = 0; i < length; i++) {
        if (fromParts[i] !== toParts[i]) {
          samePartsLength = i;
          break;
        }
      }

      var outputParts = [];
      for (var i = samePartsLength; i < fromParts.length; i++) {
        outputParts.push('..');
      }

      outputParts = outputParts.concat(toParts.slice(samePartsLength));

      return outputParts.join('/');
    }
    function register(name, filename, paths, factory){
      function require(path){
        console.log('requiering '+path);
        if (res[path]){
          return res[path];
        }else{
          for (var i=0;i<paths.length;i++){
            relfilename = paths[i]+'/'+path;
            console.log(relfilename);
            if (res[relfilename]){
              console.log('Success!');
              return res[relfilename];
            }
          }
        }
      }
      var module={exports:{}};
      factory.call(this,require,module.exports,module);
      res[filename]=module.exports;
    }
    everything.call(this,register);
  }).call(this,function(register){
  #{code}
  });
  """
boil = (obj) ->
  name = path.basename obj.filename, '.js'
  rfilename = path.relative dir, obj.filename
  modulePath = path.dirname rfilename
  modulePath = './'+rfilename.replace(/.js$/,'') if modulePath.indexOf('node_modules') < 0
  paths = (path.relative(dir, p) for p in obj.paths)
  code = fs.readFileSync obj.filename
  """
  register.call(this,
    '#{name}',
    '#{modulePath}',
    ['#{paths.join "','"}'],
    function(require, exports, module){
  #{code}
    }
  );
  """

process.stdout.write serve (boil obj for obj in ordered).join '\n' 
