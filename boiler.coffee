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
    function register(name,filename,paths,factory){
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
  register.call(this,'#{name}','#{modulePath}',['#{paths.join "','"}'],
  function(require,exports,module){
  #{code}
  });
  """

process.stdout.write serve (boil obj for obj in ordered).join '\n' 
