<?php

#>builtin
// function count(array $arr): int { return 0; }

$users = [];

$users[] = [
    "name" => "Fernando",
    "age" => 18
];

$users[] = [
    "name" => "MarkZ",
    "age" => 69
];

$i = 0;

while ($i < count($users))
    echo "Hello " . $users[$i++]["name"] . "\n";
