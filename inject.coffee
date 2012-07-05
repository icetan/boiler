path = require 'path'
fs = require 'fs'
file = path.resolve process.argv[2]
pathIdMap = {}
id = 0
pathToId = (path) ->
  pathIdMap[path] = id+=1 if path not of pathIdMap
  pathIdMap[path]
toDict = (kvps) ->
  dict = {}
  dict[kvp[0]] = kvp[1] for kvp in kvps
  dict
boil = (id, aliasIdMap, code, filename) ->
  """
  // file: #{path.relative __dirname, filename}
  register.call(this,#{id},#{JSON.stringify aliasIdMap},
  function(require,exports,module){
  #{code}
  });
  """
serve = (code) ->
  """
  (function(everything){
    window.boiler={main:{}};
    var idModuleMap={};
    function emulateRequire(aliasIdMap){
      function require(alias, windowName){
        var exports = idModuleMap[aliasIdMap[alias]];
        if(typeof windowName==='function'){
          return windowName(exports);
        }else if(typeof windowName==='string'){
          return window[windowName];
        }else{
          return exports;
        }
      }
      return require;
    }
    function register(id,aliasIdMap,factory){
      var module={exports:{}};
      factory.call(this,emulateRequire(aliasIdMap),module.exports,module);
      window.boiler.main=idModuleMap[id]=module.exports;
    }
    everything.call(this,register);
  }).call(this,function(register){
  #{code}
  });
  """

everything = ''
hookedExts = []

updateExtensions = ->
  for ext, func of require.extensions when ext not in hookedExts
    do (ext, func) ->
      hookedExts.push ext
      require.extensions[ext] = (module, filename) ->
        code = ''
        cmp = module._compile
        module.__required = {}
        module._compile = (content, filename) ->
          code = content
          cmp.call this,
            """
            require = function(req) {
              var require = function(alias) {
                module.__required[alias] = req.resolve(alias);
                return req.apply(this, arguments);
              };
              for (var i in req) {
                require[i] = req[i];
              }
              return require;
            }(require);
            #{content}
            """, filename
        try
          func module, filename
        aliasIdMap = toDict([alias, pathToId path] for alias, path of module.__required)
        everything += boil pathToId(filename), aliasIdMap, code, filename
        updateExtensions()

updateExtensions()
require file
process.stdout.write serve everything
