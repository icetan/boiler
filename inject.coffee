path_ = require 'path'
fs = require 'fs'
file = path_.resolve process.argv[2]
filenameIdMap = {}
id = 0
shalow = (from, to) ->
  to[key] = value for key, value of from
  to
filenameToId = (filename) ->
  filenameIdMap[filename] = id+=1 if filename not of filenameIdMap
  filenameIdMap[filename]
toDict = (kvps) ->
  dict = {}
  dict[kvp[0]] = kvp[1] for kvp in kvps
  dict
isExcluded = (config) ->
  if config.excluded or config.path in config.exclude
    yes
  else
    no
boil = (id, pathIdMap, code, filename) ->
  """
  register.call(this,#{id},#{JSON.stringify pathIdMap},
  function(require,exports,module){
  // file: #{path_.relative __dirname, filename}
  #{code}
  });
  """
serve = (code) ->
  """
  (function(everything){
    window.boiler={main:{}};
    var idModuleMap={};
    function emulateRequire(pathIdMap){
      function require(path, opt){
        var exports = idModuleMap[pathIdMap[path]];
        if(typeof opt==='function'){
          return opt(exports);
        }else if(typeof opt==='string'){
          return window[opt];
        }else{
          return exports;
        }
      }
      return require;
    }
    function register(id,pathIdMap,factory){
      var module={exports:{}};
      factory.call(this,emulateRequire(pathIdMap),module.exports,module);
      window.boiler.main=idModuleMap[id]=module.exports;
    }
    everything.call(this,register);
  }).call(this,function(register){
  #{code}
  });
  """

everything = ''
hookedExts = []
config = exclude:[], path:''

updateExtensions = ->
  for ext, func of require.extensions when ext not in hookedExts
    do (ext, func) ->
      hookedExts.push ext
      require.extensions[ext] = (module, filename) ->
        code = ''
        deps = {}
        cmp = module._compile
        module.__boiler_hook = (resolve, path, opt={}) ->
          config =
            parent:config
            exclude:(x for x in config.exclude)
            excluded:config.excluded or path in config.exclude
          config.path = path
          config.parent.deps = deps
          deps[path] = resolve path
          if opt.exclude
            config.exclude.push path for path in opt.exclude # when (filename=resolve path) not in config.exclude
          #console.dir config
        module._compile = (content, filename) ->
          code = content
          cmp.call this,
            """
            require = function(req) {
              var require = function(path, opt) {
                module.__boiler_hook(req.resolve, path, opt);
                return req.call(this, path);
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
        #  console.log "loaded #{config.path}:#{filename} is loading #{deps}"
        #catch error
        #  console.log 'error in '+filename+': '+error

        if not config.excluded
          #  console.log "boiling #{config.path}:#{filename}"
          pathIdMap = toDict([path, filenameToId fn] for path, fn of deps)
          everything += boil filenameToId(filename), pathIdMap, code, filename
        #else
        #  console.log 'excluded '+filename
        config = config.parent if config.parent
        updateExtensions()

updateExtensions()
require file
process.stdout.write serve everything
