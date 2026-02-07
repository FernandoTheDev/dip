<?php
// LD_LIBRARY_PATH=. ./dip test.php

#>builtin
function libffi_open(string $lib): int | false {
    return 0;
}

#>builtin
function libffi_call(int $lib, string $symbol, mixed ...$args): mixed {
    return 0;
}

#>builtin
function __vm_pop(): mixed {
    return 0;
}

#>builtin
function libffi_cleanup(): void {}

$open = libffi_open("./libtest.so");

if ($open < 0) {
    echo "Error.\n";
} else {
    $result = libffi_call($open, "hello", "from PHP");
    echo __vm_pop(); // pop from stack
    libffi_cleanup();
}
