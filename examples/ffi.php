<?php

#>ffi
function hello(string $msg): bool { return false; }

#>builtin
function __vm_pop(): mixed { return 0; }

$_ = hello("from PHP");
echo __vm_pop();
