<?php

namespace App\Services\Import;

/**
 * Liga as linhas do extrato ao que já está cadastrado no cartão (para não lançar duas vezes).
 *
 * 1. "exact":    mesmo valor e data até 3 dias de diferença.
 * 2. "amount":   mesmo valor, data mais distante (até 40 dias: compra lançada com outra data).
 * 3. "combined": uma transação cadastrada = soma de 2 ou 3 linhas (ex.: "Jogos" = Epic + Epic + Steam).
 *
 * Valor da transação cadastrada = valor cheio (total_amount, numa divisão) ou amount.
 * Cada transação e cada linha entram em uma ligação só.
 */
class StatementMatcher
{
    /**
     * @param  list<array{index: int, date: string, amount: float, alt?: float|null}>  $lines  positivo = compra, negativo = crédito;
     *                                                                                   alt = outro valor aceito (compra antes do estorno parcial)
     * @param  list<array{id: string, date: string, amount: float, combinable?: bool}>  $existing  mesmo sinal das linhas
     * @return array<int, array{ids: list<string>, confidence: string, group: list<int>}> por índice de linha
     */
    public function match(array $lines, array $existing): array
    {
        $result = [];
        $usedTx = [];

        foreach ([3 => 'exact', 40 => 'amount'] as $maxDays => $confidence) {
            foreach ($lines as $line) {
                if (isset($result[$line['index']])) {
                    continue;
                }

                $best = null;
                $bestDiff = PHP_INT_MAX;
                foreach ($existing as $tx) {
                    if (isset($usedTx[$tx['id']]) || ! $this->sameAmount($tx['amount'], $line)) {
                        continue;
                    }
                    $diff = $this->days($line['date'], $tx['date']);
                    if ($diff <= $maxDays && $diff < $bestDiff) {
                        $best = $tx;
                        $bestDiff = $diff;
                    }
                }

                if ($best !== null) {
                    $usedTx[$best['id']] = true;
                    $result[$line['index']] = ['ids' => [$best['id']], 'confidence' => $confidence, 'group' => [$line['index']]];
                }
            }
        }

        // Combinações: só compras (valor positivo) ainda soltas.
        $free = array_values(array_filter($lines, fn (array $l) => ! isset($result[$l['index']]) && $l['amount'] > 0));
        if (count($free) > 45) {
            return $result;
        }

        foreach ($existing as $tx) {
            // Parcela e recorrência são uma cobrança só no extrato: não entram em combinação.
            if (isset($usedTx[$tx['id']]) || $tx['amount'] <= 0 || ! ($tx['combinable'] ?? true)) {
                continue;
            }

            $group = $this->findCombination($free, $this->cents($tx['amount']), $tx['date'], $result);
            if ($group === null) {
                continue;
            }

            $usedTx[$tx['id']] = true;
            foreach ($group as $index) {
                $result[$index] = ['ids' => [$tx['id']], 'confidence' => 'combined', 'group' => $group];
            }
        }

        return $result;
    }

    /**
     * Menor espalhamento de datas entre as combinações de 2 ou 3 linhas que somam o valor.
     *
     * @param  list<array{index: int, date: string, amount: float}>  $free
     * @param  array<int, mixed>  $taken
     * @return list<int>|null
     */
    private function findCombination(array $free, int $target, string $date, array $taken): ?array
    {
        $candidates = array_values(array_filter(
            $free,
            fn (array $l) => ! isset($taken[$l['index']])
                && $this->cents($l['amount']) < $target
                && $this->days($l['date'], $date) <= 60,
        ));
        $n = count($candidates);
        $cents = array_map(fn (array $l) => $this->cents($l['amount']), $candidates);
        $ts = array_map(fn (array $l) => strtotime($l['date']), $candidates);

        $best = null;
        $bestSpread = PHP_INT_MAX;

        for ($a = 0; $a < $n; $a++) {
            for ($b = $a + 1; $b < $n; $b++) {
                $ab = $cents[$a] + $cents[$b];
                if ($ab === $target) {
                    $spread = abs($ts[$a] - $ts[$b]);
                    if ($spread < $bestSpread) {
                        $best = [$a, $b];
                        $bestSpread = $spread;
                    }
                }
                if ($ab >= $target) {
                    continue;
                }
                for ($c = $b + 1; $c < $n; $c++) {
                    if ($ab + $cents[$c] === $target) {
                        $spread = max($ts[$a], $ts[$b], $ts[$c]) - min($ts[$a], $ts[$b], $ts[$c]);
                        // Dupla ganha de trio com o mesmo espalhamento (menos chance de coincidência).
                        if ($spread < $bestSpread && ($best === null || count($best) === 3)) {
                            $best = [$a, $b, $c];
                            $bestSpread = $spread;
                        }
                    }
                }
            }
        }

        return $best === null ? null : array_map(fn (int $i) => $candidates[$i]['index'], $best);
    }

    /**
     * @param  array{amount: float, alt?: float|null}  $line
     */
    private function sameAmount(float $amount, array $line): bool
    {
        $cents = $this->cents($amount);

        return $cents === $this->cents($line['amount'])
            || (isset($line['alt']) && $cents === $this->cents((float) $line['alt']));
    }

    private function cents(float $value): int
    {
        return (int) round($value * 100);
    }

    private function days(string $a, string $b): int
    {
        return (int) abs(round((strtotime($a) - strtotime($b)) / 86400));
    }
}
