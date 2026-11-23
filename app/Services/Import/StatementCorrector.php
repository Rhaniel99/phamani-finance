<?php

namespace App\Services\Import;

use App\Interfaces\Services\IStatementOcr;

/**
 * Segunda opinião quando a soma de uma seção não bate com o "Total para".
 *
 * Relê as linhas da seção com outras ampliações; cada linha fica com os valores lidos (candidatos).
 * Se alguma combinação dos candidatos fecha o total, ela é aplicada (linha marcada "corrected").
 * Se não, as linhas com leituras diferentes ficam "uncertain" com os candidatos, para você conferir.
 * Também aproveita a releitura para corrigir datas ilegíveis.
 */
class StatementCorrector
{
    /** @var list<float> */
    private const SCALES = [2.0, 2.5];

    public function __construct(
        private BradescoStatementParser $parser,
    ) {}

    /**
     * @param  array{statement_date: string|null, sections: list<array<string, mixed>>, lines: list<array<string, mixed>>}  $parsed
     * @return array{statement_date: string|null, sections: list<array<string, mixed>>, lines: list<array<string, mixed>>}
     */
    public function fix(array $parsed, IStatementOcr $ocr, string $reference): array
    {
        $lines = $parsed['lines'];

        $needsReread = [];
        foreach ($lines as $line) {
            $sectionOk = $parsed['sections'][$line['section']]['ok'] ?? true;
            if (! $sectionOk || ! $line['date_ok']) {
                $needsReread[$line['band']][] = $line['index'];
            }
        }

        if ($needsReread === []) {
            return $parsed;
        }

        // Leituras alternativas de cada linha (alinhadas pela posição dentro da faixa).
        $alternatives = [];
        foreach (self::SCALES as $scale) {
            $texts = $ocr->reread(array_keys($needsReread), $scale);

            foreach ($needsReread as $band => $indexes) {
                $items = $this->items($texts[$band] ?? '');
                $ordinal = $this->ordinals($lines, $band);

                foreach ($indexes as $index) {
                    $item = $items[$ordinal[$index]] ?? null;
                    if ($item !== null) {
                        $alternatives[$index][] = $item;
                    }
                }
            }
        }

        // Datas ilegíveis: primeira leitura válida.
        foreach ($alternatives as $index => $items) {
            if ($lines[$index]['date_ok']) {
                continue;
            }
            foreach ($items as $item) {
                $date = $this->parser->dateFor($item['day'], $item['month'], $reference);
                if ($date !== null) {
                    $lines[$index]['date'] = $date;
                    $lines[$index]['date_ok'] = true;
                    $lines[$index]['corrected'] = true;
                    break;
                }
            }
        }

        // Valores: por seção que não fechou.
        foreach ($parsed['sections'] as $s => $section) {
            if ($section['ok'] || $section['total'] === null) {
                continue;
            }

            $lines = $this->solveSection($lines, $s, (float) $section['total'], $alternatives);
        }

        return [
            ...$parsed,
            'sections' => $this->parser->checkSections($parsed['sections'], $lines),
            'lines' => $lines,
        ];
    }

    /**
     * @param  list<array<string, mixed>>  $lines
     * @param  array<int, list<array{amount: float}>>  $alternatives
     * @return list<array<string, mixed>>
     */
    private function solveSection(array $lines, int $section, float $total, array $alternatives): array
    {
        $fixedCents = 0;
        $variable = [];

        foreach ($lines as $line) {
            if ($line['section'] !== $section) {
                continue;
            }

            $options = [$this->cents($line['amount'])];
            foreach ($alternatives[$line['index']] ?? [] as $item) {
                $options[] = $this->cents($item['amount']);
            }
            $options = array_values(array_unique($options));

            if (count($options) === 1) {
                $fixedCents += $options[0];
            } else {
                $variable[$line['index']] = $options;
            }
        }

        if ($variable === []) {
            return $lines;
        }

        $target = $this->cents($total) - $fixedCents;
        $solution = count($variable) <= 12 ? $this->search($variable, $target) : null;

        foreach ($variable as $index => $options) {
            if ($solution !== null) {
                $chosen = $solution[$index];
                if ($chosen !== $this->cents($lines[$index]['amount'])) {
                    $lines[$index]['amount'] = $chosen / 100;
                    $lines[$index]['kind'] = $this->parser->kind($lines[$index]['description'], $chosen / 100);
                    $lines[$index]['corrected'] = true;
                }
            } else {
                $lines[$index]['uncertain'] = true;
                $lines[$index]['candidates'] = array_map(fn (int $c) => $c / 100, $options);
            }
        }

        return $lines;
    }

    /**
     * Combinação dos candidatos que soma $target, mudando o menor número de linhas.
     *
     * @param  array<int, list<int>>  $variable  índice → [lido na 1ª vez, alternativas...]
     * @return array<int, int>|null
     */
    private function search(array $variable, int $target): ?array
    {
        $keys = array_keys($variable);
        $best = null;
        $bestChanges = PHP_INT_MAX;

        $walk = function (int $k, int $sum, array $picked, int $changes) use (&$walk, &$best, &$bestChanges, $keys, $variable, $target): void {
            if ($changes >= $bestChanges) {
                return;
            }
            if ($k === count($keys)) {
                if ($sum === $target) {
                    $best = $picked;
                    $bestChanges = $changes;
                }

                return;
            }
            foreach ($variable[$keys[$k]] as $o => $cents) {
                $walk($k + 1, $sum + $cents, $picked + [$keys[$k] => $cents], $changes + ($o > 0 ? 1 : 0));
            }
        };
        $walk(0, 0, [], 0);

        return $best;
    }

    /**
     * @return list<array{day: int, month: int, description: string, amount: float, kind: string}>
     */
    private function items(string $text): array
    {
        $items = [];
        foreach (preg_split('/\R/u', $text) ?: [] as $raw) {
            $item = $this->parser->item(trim($raw));
            if ($item !== null) {
                $items[] = $item;
            }
        }

        return $items;
    }

    /**
     * Posição de cada linha dentro da sua faixa (0, 1, ...).
     *
     * @param  list<array<string, mixed>>  $lines
     * @return array<int, int>
     */
    private function ordinals(array $lines, int $band): array
    {
        $ordinal = [];
        $n = 0;
        foreach ($lines as $line) {
            if ($line['band'] === $band) {
                $ordinal[$line['index']] = $n++;
            }
        }

        return $ordinal;
    }

    private function cents(float $value): int
    {
        return (int) round($value * 100);
    }
}
