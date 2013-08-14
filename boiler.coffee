boilerCacheCleared = no

debug = (args...) -> console.log args... if module.exports.debug

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


class Pot
  constructor: (filename, @recursive=yes) ->
    @config = {filename, deps:{}, exclude:[]}

  require: ->
    Boiler.hookExtensions @
    if not boilerCacheCleared
      delete require.cache[module.filename]
      debug 'removing boiler.js code from cache'
      boilerCacheCleared = yes
    mod = require @config.filename
    Boiler.unhookExtensions()
    mod

  boil: ->
    @require()
    @config


class Boiler
  constructor: ->
    @pots = {}
    @filenameIdMap = {}
    @id = 0
    @hooked = no

  add: (filename) ->
    filename = path_.resolve filename
    @pots[filename] = new Pot(filename) if filename not of @pots

  boil: (config) ->
    if config.code? and not config.excluded
      codes = (@boil cfg for path, cfg of config.deps).join '\n'
      debug "boiling #{config.filename}"
      pathIdMap = toDict([path, @filenameToId cfg.filename] for path, cfg of config.deps)
      codes += Boiler.registerWrap @filenameToId(config.filename), pathIdMap,
        config.code, config.filename
    else
      debug 'excluded '+config.filename
      ''

  serve: ->
    Boiler.browserWrap (@boil pot.boil() for fn, pot of @pots).join '\n'

  filenameToId: (filename) ->
    @filenameIdMap[filename] = @id+=1 if filename not of @filenameIdMap
    @filenameIdMap[filename]


  @isExcluded: (path, config) ->
    if config.excluded or path in config.exclude
      yes
    else if config.parent
      Boiler.isExcluded path, config.parent
    else
      no

  @injectScript: (injects={}) ->
    scripts = (for alias, args of injects
      strArgs = (JSON.stringify arg for arg in args).join ','
      "var #{alias}=require(#{strArgs});\n")
    if scripts.length > 0
      "// Boiler injects\n#{scripts.join ''}"
    else
      ''
  @exportScript: (exp) ->
    if exp then "\n;\n// Boiler exports\nmodule.exports=#{exp};" else ''

  @injectExportWrap: (pot, code) ->
    Boiler.injectScript(pot.config.injects) +
    code +
    Boiler.exportScript(pot.config.exports)

  @fakeRequire: (req) ->
    fake = (path, opt) ->
      module.__boiler_hook_in(req.resolve, path, opt)
      try
        res = req.call(this, path)
      catch err
        module.__boiler_hook_error(err)
      finally
        module.__boiler_hook_out()
      res
    fake[k] = v for k,v of req
    fake

  @requireWrap: (code) ->
    fakeScript = Boiler.fakeRequire.toString().replace(/\n\s*/g,'')
    "require = (#{fakeScript})(require);#{code}"

  @registerWrap: (id, pathIdMap, code, filename) ->
    """
    register.call(this,#{id},#{JSON.stringify pathIdMap},
    function(require,exports,module,global){var GLOBAL = global;
    // Boiler file: #{path_.relative process.cwd(), filename}
    #{code}
    });
    """

  @browserWrap: (code) ->
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
        factory.call(this,emulateRequire(pathIdMap),module.exports,module,window);
        window.boiler.main=idModuleMap[id]=module.exports;
      }
      everything.call(this,register);
    }).call(this,function(register){
    #{code}
    });
    """

  @inHook: (pot, resolve, path, opt={}) ->
    debug "hook into #{path}"
    if path of pot.config.deps
      debug "#{path} already configured!"
      cfg = pot.config.deps[path]
    else
      filename = resolve path
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
        args = [relativeModule filename, resolve(p)]
        args.push reqOpt if reqOpt?
        [alias, args])
      cfg = {
        filename
        exclude
        injects
        exports:opt.exports
        excluded:opt.exclude is true or Boiler.isExcluded filename, pot.config
        parent:pot.config
        deps:{}
      }
    pot.config = pot.config.deps[path] = cfg
  @errorHook: (pot, err) ->
    debug "hook error #{pot.config.filename}: #{err}"
  @outHook: (pot) ->
    debug "hook outof #{pot.config.filename}"
    pot.config = pot.config.parent if pot.config.parent

  @getHook: (pot, ext, func) ->
    hook = (module_, filename) ->
      # TODO: make sure it is boiler.js and not some other file with the
      # same name.
      isBoiler = path_.basename(module_.filename, '.js') is 'boiler'
      cmp = module_._compile
      module_.__boiler_hook_in = (args...) -> Boiler.inHook pot, args...
      module_.__boiler_hook_out = (args...) -> Boiler.outHook pot, args...
      module_.__boiler_hook_error = (args...) -> Boiler.errorHook pot, args...
      module_._compile = (content, filename) ->
        debug module_.filename
        if isBoiler
          debug 'this is thee boiler, using fake code'
          code = nodeCode = pot.config.code = module.exports.__boiler_code
        else
          code = pot.config.code = Boiler.injectExportWrap pot, content
          #if pot.recursive
          debug "adding fake require to #{filename}"
          #else
          #  debug "not faking require for #{filename}"
          #nodeCode = if pot.recursive then Boiler.requireWrap code else code
          nodeCode = Boiler.requireWrap code
        res = cmp.call this, nodeCode, filename
        #pot.config.excluded = module_.exports?.__boiler_exclude
        #pot.config.code = module_.exports.__boiler_code if module_.exports?.__boiler_code
        res
      try
        func module_, filename
      catch err
        msg = err.toString()
        if msg.indexOf('Error: Cannot find module') is 0
          console.warn msg, 'in file:', filename
        debug "Boiler error when running wrapped code:", err.stack
      # Add hooks if new extensions have been added
      Boiler.hookExtensions pot
    hook.__boiler_hook_orig = func
    hook

  @unhookExtensions: ->
    for ext, func of require.extensions when func.__boiler_hook_orig?
      require.extensions[ext] = func.__boiler_hook_orig

  @hookExtensions: (pot) ->
    for ext, func of require.extensions when not func.__boiler_hook_orig?
      require.extensions[ext] = Boiler.getHook pot, ext, func


module.exports = (req, path, opt) ->
  pot = new Pot(req.resolve path, no)
  Boiler.inHook pot, req.resolve, path, opt
  pot.require()

module.exports.Boiler = Boiler
module.exports.debug = no

module.exports.__boiler_exclude = no
module.exports.__boiler_code = "module.exports=function(req, path, opt){return req(path, opt);};"
