<?php

namespace App\Services\Import;

/**
 * Lê o texto (OCR) do extrato do cartão Bradesco (app → "Extrato da fatura").
 *
 * Linha de compra:  "17/11 DROGARIA SOFIA USD 0,00 R$ 0,00 R$ 17,00"
 * Cabeçalho:        "RHANIEL M MONTEIRO - ELO GRAFITE XXXX.XXXX.XXXX.8140"
 * Total da seção:   "Total para: RHANIEL M MONTEIRO R$ 185,39"
 *
 * - Valor: só os dígitos contam, sempre com 2 casas (o OCR às vezes troca a vírgula por ponto: "49.99").
 * - Ano: o extrato não traz; vem da data do extrato (mês maior que o do extrato = ano anterior).
 * - SALDO ANTERIOR / PAGTO: entram na soma da seção (para conferir o total), mas não são compras.
 * - Estorno (valor negativo) com a compra igual na mesma seção: os dois se anulam ("refunded").
 *   Estorno menor que a compra da mesma loja: abate dela ("deducted" + deduction na compra).
 *
 * kind: purchase | refund (crédito avulso) | refunded | deducted | balance | payment
 */
class BradescoStatementParser
{
    /** Valor com 2 casas decimais (vírgula ou ponto), com sinal opcional. */
    private const MONEY = '/-?\s?\.?(?:\d{1,3}(?:[.\s]\d{3})+|\d+)[.,]\d{2}(?!\d)/u';

    private const JUNK = '\s|§©®=+\'"‘’“”`´.,:;~_\-—–!*\[\](){}<>¢$';

    /**
     * @param  list<string>  $bands  texto de cada faixa
     * @return array{
     *     statement_date: string|null,
     *     sections: list<array{label: string, last4: string|null, total: float|null, sum: float, ok: bool}>,
     *     lines: list<array{index: int, band: int, section: int, raw: string, day: int, month: int, date: string|null, date_ok: bool, description: string, amount: float, kind: string, pair: int|null, deduction: float, installment: array{number: int, count: int}|null}>,
     *     unparsed: list<array{band: int, raw: string}>
     * }
     */
    public function parse(array $bands, ?string $fallbackDate = null): array
    {
        $statementDate = null;
        $sections = [];
        $lines = [];
        $unparsed = [];
        $current = null;

        foreach ($bands as $band => $text) {
            foreach (preg_split('/\R/u', $text) ?: [] as $raw) {
                $raw = trim($raw);
                if ($raw === '') {
                    continue;
                }

                if ($statementDate === null && preg_match('#Data:?\s*(\d{2})/(\d{2})/(\d{4})#u', $raw, $m)) {
                    $statementDate = sprintf('%04d-%02d-%02d', $m[3], $m[2], $m[1]);

                    continue;
                }

                if (preg_match('/^\W*Total\s+para:?\s*(.*?)(?:\s+R\$\s*(-?[\d.,\s]*\d))?\W*$/iu', $raw, $m)) {
                    $current ??= $this->openSection($sections, null, null);
                    $sections[$current]['total'] = isset($m[2]) && $m[2] !== '' ? $this->amount($m[2]) : null;
                    $sections[$current]['label'] = $sections[$current]['label'] ?: trim($m[1]);
                    $current = null;

                    continue;
                }

                if (stripos($raw, 'XXXX') !== false && preg_match('/(\d{4})\W*$/u', $raw, $m)) {
                    $holder = trim(preg_replace('/\s+-\s+.*$/u', '', ltrim($raw, ' |')) ?? '');
                    $current = $this->openSection($sections, $holder, $m[1]);

                    continue;
                }

                $item = $this->item($raw);
                if ($item === null) {
                    // Tem valor mas não deu para entender: mostra na revisão para você lançar à mão.
                    if (preg_match(self::MONEY, $raw)) {
                        $unparsed[] = ['band' => (int) $band, 'raw' => $raw];
                    }

                    continue;
                }

                $current ??= $this->openSection($sections, null, null);
                $lines[] = [
                    'index' => count($lines),
                    'band' => (int) $band,
                    'section' => $current,
                    'raw' => $raw,
                    ...$item,
                    'date' => null,
                    'pair' => null,
                    'deduction' => 0.0,
                ];
            }
        }

        $reference = $statementDate ?? $fallbackDate ?? date('Y-m-d');
        $lines = $this->resolveDates($lines, $reference);
        $lines = $this->pairRefunds($lines);

        return [
            'statement_date' => $statementDate,
            'sections' => $this->checkSections($sections, $lines),
            'lines' => $lines,
            'unparsed' => $unparsed,
        ];
    }

    /**
     * Linha de lançamento: "dd/mm descrição ... R$ valor" (o último R$ da linha é o valor em reais).
     *
     * @return array{day: int, month: int, description: string, amount: float, kind: string, installment: array{number: int, count: int}|null}|null
     */
    public function item(string $raw): ?array
    {
        // Data no começo (o OCR troca 0↔O, 1↔l/I, 5↔S).
        if (! preg_match('#^[^\dA-Za-z]*([\dSsOoIl]{1,2})\s*[/.]\s*([\dOoIl]{2})\b(.*)$#u', $raw, $m)) {
            return null;
        }

        $rest = $m[3];

        // Valores com 2 casas: "1.234,56", "-.114,90", "49.99". O "R$" não é exigido: o OCR às vezes
        // lê "RS", "R§" ou nem lê. O valor em reais é o último da linha.
        if (! preg_match_all(self::MONEY, $rest, $values, PREG_OFFSET_CAPTURE) || $values[0] === []) {
            return null;
        }

        $last = end($values[0]);
        $tail = substr($rest, $last[1] + strlen($last[0]));
        if (preg_match('/[\p{L}\d]/u', $tail)) {
            return null;
        }

        $amount = $this->amount($last[0]);

        // Descrição: até o primeiro valor, sem as colunas de moeda ("USD", "usD", "R$", "RS"...).
        $description = substr($rest, 0, $values[0][0][1]);
        $description = preg_replace('/(?:\s+(?:u\s?s\s?[d$]|r\s?[$s§5]|u\$|\$))+\s*$/iu', '', $description) ?? $description;
        $description = $this->cleanDescription($description);

        // Parcela no fim da descrição: "PARC 01/04", "PARCELA 2/10" ou só "01/04".
        $installment = null;
        if (preg_match('#\s+(?:PARC(?:ELA)?\.?\s*)?(\d{1,2})\s*/\s*(\d{1,2})$#iu', $description, $p)) {
            $number = (int) $p[1];
            $count = (int) $p[2];
            if ($number >= 1 && $count >= 2 && $count <= 48 && $number <= $count) {
                $installment = ['number' => $number, 'count' => $count];
                $description = $this->cleanDescription(substr($description, 0, -strlen($p[0])));
            }
        }

        if ($description === '') {
            return null;
        }

        $digits = fn (string $s) => (int) strtr($s, ['S' => '5', 's' => '5', 'O' => '0', 'o' => '0', 'I' => '1', 'l' => '1']);

        return [
            'day' => $digits($m[1]),
            'month' => $digits($m[2]),
            'description' => $description,
            'amount' => $amount,
            'kind' => $this->kind($description, $amount),
            'installment' => $installment,
        ];
    }

    public function amount(string $text): float
    {
        $negative = str_contains($text, '-');
        $digits = preg_replace('/\D/', '', $text) ?? '';

        if ($digits === '') {
            return 0.0;
        }

        $value = (int) $digits / 100;

        return round($negative ? -$value : $value, 2);
    }

    public function cleanDescription(string $text): string
    {
        $text = preg_replace('/^['.self::JUNK.']+|['.self::JUNK.']+$/u', '', trim($text)) ?? '';
        // "S$" e "|" soltos que o OCR deixa no fim.
        $text = preg_replace('/\s+(?:S\$|\$|\||[§©=])$/u', '', $text) ?? $text;

        return trim(preg_replace('/\s+/u', ' ', $text) ?? $text);
    }

    public function kind(string $description, float $amount): string
    {
        $upper = mb_strtoupper($description);

        return match (true) {
            str_contains($upper, 'SALDO ANTERIOR') => 'balance',
            (bool) preg_match('/\bPAG(?:TO|AMENTO)\b/u', $upper) => 'payment',
            $amount < 0 => 'refund',
            default => 'purchase',
        };
    }

    /**
     * @param  list<array{label: string, last4: string|null, total: float|null}>  $sections
     */
    private function openSection(array &$sections, ?string $holder, ?string $last4): int
    {
        $sections[] = ['label' => (string) $holder, 'last4' => $last4, 'total' => null];

        return count($sections) - 1;
    }

    /**
     * Ano a partir da data do extrato; dia ilegível vira o dia da linha de cima (a lista é do mais
     * recente para o mais antigo) e a linha fica marcada para conferir.
     *
     * @param  list<array<string, mixed>>  $lines
     * @return list<array<string, mixed>>
     */
    private function resolveDates(array $lines, string $reference): array
    {
        $previous = null;

        foreach ($lines as $i => $line) {
            $date = $this->dateFor($line['day'], $line['month'], $reference);

            $lines[$i]['date'] = $date ?? $previous ?? $reference;
            $lines[$i]['date_ok'] = $date !== null;

            $previous = $lines[$i]['date'];
        }

        return $lines;
    }

    /**
     * "dd/mm" → Y-m-d, com o ano da data do extrato (mês depois do mês do extrato = ano anterior).
     */
    public function dateFor(int $day, int $month, string $reference): ?string
    {
        $refYear = (int) substr($reference, 0, 4);
        $refMonth = (int) substr($reference, 5, 2);

        if ($month < 1 || $month > 12 || $day < 1) {
            return null;
        }

        $year = $month > $refMonth ? $refYear - 1 : $refYear;

        return checkdate($month, $day, $year) ? sprintf('%04d-%02d-%02d', $year, $month, $day) : null;
    }

    /**
     * @param  list<array<string, mixed>>  $lines
     * @return list<array<string, mixed>>
     */
    private function pairRefunds(array $lines): array
    {
        foreach ($lines as $i => $refund) {
            if ($refund['kind'] !== 'refund') {
                continue;
            }

            foreach ($lines as $j => $purchase) {
                if ($purchase['kind'] === 'purchase'
                    && $purchase['pair'] === null
                    && $purchase['section'] === $refund['section']
                    && abs($purchase['amount'] + $refund['amount']) < 0.005
                    && $this->sameMerchant($purchase['description'], $refund['description'])) {
                    $lines[$i]['kind'] = 'refunded';
                    $lines[$i]['pair'] = $j;
                    $lines[$j]['kind'] = 'refunded';
                    $lines[$j]['pair'] = $i;

                    break;
                }
            }
        }

        // Estorno parcial (ex.: compra 44,35 e estorno 26,90 da mesma loja): abate da compra.
        foreach ($lines as $i => $refund) {
            if ($refund['kind'] !== 'refund') {
                continue;
            }

            foreach ($lines as $j => $purchase) {
                if ($purchase['kind'] === 'purchase'
                    && $purchase['pair'] === null
                    && $purchase['section'] === $refund['section']
                    && $purchase['amount'] + $refund['amount'] > 0.005
                    && $this->sameMerchant($purchase['description'], $refund['description'])) {
                    $lines[$i]['kind'] = 'deducted';
                    $lines[$i]['pair'] = $j;
                    $lines[$j]['pair'] = $i;
                    $lines[$j]['deduction'] = round(-$refund['amount'], 2);

                    break;
                }
            }
        }

        return $lines;
    }

    private function sameMerchant(string $a, string $b): bool
    {
        $key = fn (string $s) => preg_replace('/[^A-Z0-9]/', '', mb_strtoupper($s));

        return $key($a) === $key($b) || similar_text((string) $key($a), (string) $key($b)) >= 0.8 * max(strlen((string) $key($a)), 1);
    }

    /**
     * Soma de cada seção (todas as linhas, inclusive saldo e pagamento) contra o "Total para".
     *
     * @param  list<array{label: string, last4: string|null, total: float|null}>  $sections
     * @param  list<array<string, mixed>>  $lines
     * @return list<array{label: string, last4: string|null, total: float|null, sum: float, ok: bool}>
     */
    public function checkSections(array $sections, array $lines): array
    {
        foreach ($sections as $s => $section) {
            $sum = 0.0;
            foreach ($lines as $line) {
                if ($line['section'] === $s) {
                    $sum += $line['amount'];
                }
            }
            $sum = round($sum, 2);

            $sections[$s]['sum'] = $sum;
            $sections[$s]['ok'] = $section['total'] === null
                ? abs($sum) < 0.005
                : abs($sum - $section['total']) < 0.005;
        }

        return array_values($sections);
    }
}
