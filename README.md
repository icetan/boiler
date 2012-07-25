# Boiler
Bundle Node.js compatible modules to one browser compatible file.

    $ boiler app.js > bundle.js

## Examples

Install Backbone with NPM and use in browser:

    npm install backbone

```javascript
var Backbone = require('backbone');
```

Underscore will be downloaded by NPM and bundled as a dependecy to Backbone.

Include a non-global jquery instance:

```javascript
// app.js
var $ = require('./jquery', {
  // Export and remove jquery from the global scope
  exports: '$.noConflict()'
});

require('./jquery.plugin', {
  // Give the jquery plugin a non-global reference to jquery.
  injects: {
    '$': './jquery'
  }
});
```

To use your boiled module in the browser, include it in a script tag and access
the exported function through ```boiler.main```.

```javascript
// app.js
module.exports = {
  init: function () {
    $('body').html('Hello World!');
  }
}
```

```html
<script src="bundle.js"></script>
<script>
  boiler.main.init();
</script>
````

To use browser javascripts as Node.js modules you can require them with boiler:

*Warning: example doesn't work without injecting a fake window object, but can
be done in theory*

```javascript
// my-node-program.js
var boiler = require('boiler'),
    L = boiler(require, './leaflet', 'window.L');

console.log(new L.Point(3, 4));
```

    $ node my-node-program.js