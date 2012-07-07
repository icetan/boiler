# Boiler
Bundle Node.js compatible modules to one browser compatible file.

    boiler app.js > bundle.js

## Examples

Install Backbone with NPM and use in browser:

    npm install backbone

```javascript
var Backbone = require('backbone');
```

Underscore will be downloaded by NPM and bundled as a dependecy to Backbone.

Include a non-global jquery instance:

```javascript
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

// Use plugin
$.plugin();
```
