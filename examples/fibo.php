<?php

function fibo($n) {
    if ($n < 2) return $n;
    return fibo($n - 2) + fibo($n - 1);
}

echo "fibo(10): " . fibo(10) . "\n";

