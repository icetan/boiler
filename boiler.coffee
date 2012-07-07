path_ = require 'path'
relativeModule = (from, to) ->
  './'+path_.relative(path_.dirname(from), to).replace /\\/g, '/'
toDict = (kvps) ->
  dict = {}
  dict[kvp[0]] = kvp[1] for kvp in kvps
  dict
hasProp = (dict, props) ->
  for prop in props
    (return yes) if prop of dict
  no

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

  @injectScript: (injects={}) ->
    (for alias, args of injects
      strArgs = (JSON.stringify arg for arg in args).join ','
      "var #{alias}=require(#{strArgs});\n").join ''
  @exportScript: (exp) ->
    if exp then "\n;module.exports=#{exp};" else ''

  @requireWrap: (content) ->
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
    """

  @boil: (id, pathIdMap, code, filename) ->
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
          return idModuleMap[pathIdMap[path]];
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
          that = @
          codeBrowser = ''
          deps = {}
          cmp = module._compile
          module.__boiler_hook_in = (resolve, path, opt={}) =>
            @debug "hook into #{path}:#{filename}"
            # Check for convinience conversion
            if typeof opt is 'string'
              opt = exports:opt
            else if opt is true or opt instanceof Array
              opt = exclude:opt
            else if opt instanceof Object and not hasProp opt, ['exclude', 'exports', 'injects']
              opt = injects:opt

            exclude = (resolve p for p in (if opt.exclude instanceof Array then opt.exclude else []))
            injects = toDict(for alias, p of (opt.injects or {})
              [p, reqOpt] = p if p instanceof Array
              args = [relativeModule resolve(path), resolve(p)]
              args.push reqOpt if reqOpt?
              [alias, args])
            @config = {
              path:resolve path
              exclude
              injects
              exports:opt.exports
              excluded:opt.exclude is true or @isExcluded resolve(path), @config
              parent:@config
            }
            deps[path] = resolve path
            #config.deps = deps
            @debug @config
          module.__boiler_hook_error = (err) =>
            @debug "hook error #{@config.path}:#{filename}: #{err}"
          module.__boiler_hook_out = =>
            @debug "hook outof #{@config.path}:#{filename}"
            @config = @config.parent if @config.parent
          module._compile = (content, filename) ->
            code =  Boiler.injectScript(that.config.injects)
            code += content
            code += Boiler.exportScript(that.config.exports)
            codeBrowser = code
            codeNode = Boiler.requireWrap code
            cmp.call this, codeNode, filename
          try
            func module, filename
          catch err
            @debug "error: #{err}"
          if not @config.excluded
            @debug "boiling #{@config.path}:#{filename}"
            pathIdMap = toDict([path, @filenameToId fn] for path, fn of deps)
            @everything += Boiler.boil @filenameToId(filename), pathIdMap,
              codeBrowser, filename
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
