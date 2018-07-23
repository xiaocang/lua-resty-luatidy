perl version from: https://www.oschina.net/code/snippet_563463_19381

usage:

- from command line:

``` bash
resty luatidy.lua <filename>
```

- built in lua

```
local tidy = require "resty.luatidy"
tidy.pretty(code)
```
