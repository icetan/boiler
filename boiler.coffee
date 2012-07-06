path_ = require 'path'
toDict = (kvps) ->
  dict = {}
  dict[kvp[0]] = kvp[1] for kvp in kvps
  dict


class Boiler
  constructor: ->
    @debugging = off
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
    #extra = ''
    #if typeof exportSpoofs is 'string'
    #  extra = "var #{exportSpoofs} = exports"
    #else typeof exportSpoofs is 'object'
    #  for alias, func of exportSpoofs
    #    extra =
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
          return exports;
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
            @debug "hook into #{path}:#{filename}"
            @config =
              parent:@config
              exclude:opt.exclude or []
              excluded:opt.excluded or @isExcluded path, @config
              head:opt.head or ''
              foot:opt.foot or ''
              path:path
            #config.path = path
            #config.parent.deps = deps
            deps[path] = resolve path
            @debug @config
          module.__boiler_hook_error = (err) =>
            @debug "hook error #{@config.path}:#{filename}: #{err}"
          module.__boiler_hook_out = =>
            @debug "hook outof #{@config.path}:#{filename}"
            @config = @config.parent if @config.parent
          module._compile = (content, filename) ->
            code = content
            cmp.call this,
              """
              require = function(req) {
                var require = function(path, opt) {
                  var res;
                  module.__boiler_hook_in(req.resolve, path, opt);
                  try {
                    res = req.call(this, path);
                  } catch (err) {
                    module.__boiler_hook_error(err);
                  } finally {
                    module.__boiler_hook_out();
                  }
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
          if not @config.excluded
            @debug "boiling #{@config.path}:#{filename}"
            pathIdMap = toDict([path, @filenameToId fn] for path, fn of deps)
            @everything += @_boil @filenameToId(filename), pathIdMap,
              "#{@config.head};\n#{code}\n;#{@config.foot};\n", filename
          else
            @debug 'excluded '+filename
          @hookExtensions()
        hook.__boiler_hook_orig = func
        require.extensions[ext] = hook

  debug: ->
    console.log.apply @, arguments if @debugging

module.exports = (file, debug=off) ->
  boiler = new Boiler
  boiler.debugging = debug
  boiler.require file
  if debug
    ''
  else
    boiler.serve()

module.exports.Boiler = Boiler
