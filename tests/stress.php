<?php
$size = 100; // Matriz 100x100
$n = 10;    // Repetir a operação 10 vezes

$i = 0;
while ($i < $n) {
    $a = [];
    $b = [];
    $res = [];
    
    // Inicializa matrizes
    $y = 0;
    while ($y < $size) {
        $x = 0;
        while ($x < $size) {
            $a[$y][$x] = $y + $x;
            $b[$y][$x] = $y * $x;
            $x++;
        }
        $y++;
    }

    // Multiplicação simples (ou soma complexa para estresse de acesso)
    $y = 0;
    while ($y < $size) {
        $x = 0;
        while ($x < $size) {
            $res[$y][$x] = $a[$y][$x] + $b[$y][$x];
            $x++;
        }
        $y++;
    }
    $i++;
}

echo "Estresse finalizado com sucesso\n";
