path_ = require 'path'
toDict = (kvps) ->
  dict = {}
  dict[kvp[0]] = kvp[1] for kvp in kvps
  dict

class Boiler
  constructor: ->
    @filenameIdMap = {}
    @id = 0
    @everything = ''

  require: (file) ->
    @config = exclude:[], path:''
    @hookExtensions()
    require path_.resolve file
    @unhookExtensions()

  filenameToId: (filename) ->
    @filenameIdMap[filename] = @id+=1 if filename not of @filenameIdMap
    @filenameIdMap[filename]

  isExcluded: (path, config) ->
    if config.excluded or path in config.exclude
      yes
    else if config.parent
      @isExcluded path, config.parent
    else
      no

  _boil: (id, pathIdMap, code, filename) ->
    """
    register.call(this,#{id},#{JSON.stringify pathIdMap},
    function(require,exports,module){
    // file: #{path_.relative __dirname, filename}
    #{code}
    });
    """

  serve: ->
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
    #{@everything}
    });
    """

  unhookExtensions: ->
    for ext, func of require.extensions when func.__boiler_hook_orig?
      require.extensions[ext] = func.__boiler_hook_orig

  hookExtensions: ->
    for ext, func of require.extensions when not func.__boiler_hook_orig?
      do (ext, func) =>
        hook = (module, filename) =>
          code = ''
          deps = {}
          cmp = module._compile
          module.__boiler_hook_in = (resolve, path, opt={}) =>
            #console.log "hook into #{filename}"
            #            @config.excluded = yes if opt.excluded is yes
            @config =
              parent:@config
              exclude:opt.exclude or []
              excluded:opt.excluded or @isExcluded path, @config
            #config.path = path
            #config.parent.deps = deps
            deps[path] = resolve path
            #console.dir config
          module.__boiler_hook_out = =>
            #console.log "hook outof #{filename}"
            @config = @config.parent if @config.parent
          module._compile = (content, filename) ->
            code = content
            cmp.call this,
              """
              require = function(req) {
                var require = function(path, opt) {
                  module.__boiler_hook_in(req.resolve, path, opt);
                  var res = req.call(this, path);
                  module.__boiler_hook_out();
                  return res;
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
            #console.log "loaded #{config.path}:#{filename} is loading #{deps}"
          catch error
            #console.log 'error in '+filename+': '+error
          if not @config.excluded
            #console.log "boiling #{config.path}:#{filename}"
            pathIdMap = toDict([path, @filenameToId fn] for path, fn of deps)
            @everything += @_boil @filenameToId(filename), pathIdMap, code, filename
          #else
            #console.log 'excluded '+filename
          @hookExtensions()
        hook.__boiler_hook_orig = func
        require.extensions[ext] = hook


module.exports = (file) ->
  boiler = new Boiler
  boiler.require file
  return boiler.serve()

module.exports.Boiler = Boiler
