<?php

namespace Tests\Unit;

use App\Interfaces\Services\IStatementOcr;
use App\Services\Import\BradescoStatementParser;
use App\Services\Import\MerchantSuggester;
use App\Services\Import\StatementCorrector;
use App\Services\Import\StatementMatcher;
use PHPUnit\Framework\TestCase;

/**
 * Leitura do extrato do cartão Bradesco (texto do OCR), correção pelo total e ligação com o cadastrado.
 */
class BradescoStatementTest extends TestCase
{
    /** @return list<string> */
    private function bands(): array
    {
        return explode("\n", trim((string) file_get_contents(__DIR__.'/../Fixtures/bradesco-extrato.txt')));
    }

    public function test_reads_sections_totals_and_lines(): void
    {
        $result = (new BradescoStatementParser)->parse($this->bands());

        $this->assertSame('2026-11-22', $result['statement_date']);
        $this->assertCount(3, $result['sections']);
        $this->assertSame(['1111', '2222', '3333'], array_column($result['sections'], 'last4'));
        $this->assertSame([true, true, true], array_column($result['sections'], 'ok'));
        $this->assertSame(96.99, $result['sections'][0]['total']);
        $this->assertNull($result['sections'][1]['total']);
        $this->assertCount(14, $result['lines']);

        $byDescription = array_column($result['lines'], null, 'description');
        // "49.99": o OCR trocou a vírgula por ponto; contam só os dígitos.
        $this->assertSame(49.99, $byDescription['TIM 11999990000']['amount']);
        // Lixo do OCR no começo ("|", "§=", "©") sai da descrição.
        $this->assertArrayHasKey('DROGARIA SOFIA', $byDescription);
        $this->assertArrayHasKey('MP ALIEXPRESS', $byDescription);
        $this->assertSame('payment', $byDescription['PAGTO ANTECIPADO PIX']['kind']);
        $this->assertSame('balance', $byDescription['SALDO ANTERIOR']['kind']);
    }

    public function test_tolerates_ocr_variations_and_reads_installments(): void
    {
        $parser = new BradescoStatementParser;

        // "R$" lido como "RS"/"R§" ou perdido, "USD" como "usD", mês "1l".
        $this->assertSame(['IFD iFood', 12.90], $this->pick($parser->item('15/11 IFD iFood usD 0,00 RS 0,00 RS 12,90')));
        $this->assertSame(['99Food Sabor do A a', 24.60], $this->pick($parser->item('30/10 99Food Sabor do A a usD 0,00 R§ 0,00 R§ 24,60')));
        $this->assertSame(['DROGARIA SOFIA', 17.00], $this->pick($parser->item('17/11 DROGARIA SOFIA USD 0,00 0,00 17,00')));
        $this->assertSame(11, $parser->item('06/1l Mercadinho USD 0.00 R$ 0.00 R$35,10 |')['month'] ?? null);

        $parc = $parser->item('20/11 MAGAZINE LUIZA PARC 01/04 USD 0,00 R$ 0,00 R$ 35,10');
        $this->assertSame('MAGAZINE LUIZA', $parc['description'] ?? null);
        $this->assertSame(['number' => 1, 'count' => 4], $parc['installment'] ?? null);
        $this->assertSame(['number' => 3, 'count' => 10], $parser->item('20/11 MERCADOLIVRE 3/10 USD 0,00 R$ 0,00 R$ 16,68')['installment'] ?? null);
        $tim = $parser->item('12/11 TIM 11999990000 USD 0,00 R$ 0,00 R$ 49.99');
        $this->assertNotNull($tim);
        $this->assertNull($tim['installment']);

        // Linha com valor que não dá para entender: vai para "unparsed".
        $result = $parser->parse(['Data: 22/11/2026', 'X? MERCADO Y R$ 0,00 R$ 10,00']);
        $this->assertSame(['X? MERCADO Y R$ 0,00 R$ 10,00'], array_column($result['unparsed'], 'raw'));
    }

    /**
     * @param  array<string, mixed>|null  $item
     * @return array{mixed, mixed}
     */
    private function pick(?array $item): array
    {
        return [$item['description'] ?? null, $item['amount'] ?? null];
    }

    public function test_infers_the_year_from_the_statement_date(): void
    {
        $parser = new BradescoStatementParser;
        $lines = array_column($parser->parse($this->bands())['lines'], 'date', 'description');

        $this->assertSame('2026-09-16', $lines['MP ALIEXPRESS']);
        $this->assertSame('2026-10-09', $lines['Steam']);
        // Extrato de janeiro com compra de dezembro → ano anterior.
        $this->assertSame('2025-12-28', $parser->dateFor(28, 12, '2026-01-05'));
        $this->assertNull($parser->dateFor(50, 10, '2026-11-22'));
    }

    public function test_pairs_refunds_and_deducts_partial_ones(): void
    {
        $lines = (new BradescoStatementParser)->parse($this->bands())['lines'];

        // Estorno igual à compra: os dois ficam de fora.
        $this->assertSame('refunded', $lines[8]['kind']);
        $this->assertSame('refunded', $lines[11]['kind']);
        $this->assertSame(11, $lines[8]['pair']);

        // Estorno menor que a compra da mesma loja: abate.
        $this->assertSame('purchase', $lines[7]['kind']);
        $this->assertSame(26.90, $lines[7]['deduction']);
        $this->assertSame('deducted', $lines[10]['kind']);
    }

    public function test_unreadable_amount_is_fixed_by_the_bank_total(): void
    {
        $good = $this->bands();
        $bad = array_map(fn (string $b) => str_replace(['R$ 68,19', '09/10'], ['R$ 88,19', '59/10'], $b), $good);

        $parser = new BradescoStatementParser;
        $parsed = $parser->parse($bad);
        $this->assertFalse($parsed['sections'][2]['ok']);

        $ocr = new class($good) implements IStatementOcr
        {
            /** @param list<string> $good */
            public function __construct(private array $good) {}

            public function read(array $paths, callable $progress): array
            {
                return $this->good;
            }

            public function reread(array $bands, float $scale): array
            {
                return array_combine($bands, array_map(fn (int $i) => $this->good[$i], $bands));
            }

            public function cleanup(): void {}
        };

        $fixed = (new StatementCorrector($parser))->fix($parsed, $ocr, '2026-11-22');
        $steam = array_column($fixed['lines'], null, 'description')['Steam'];

        $this->assertTrue($fixed['sections'][2]['ok']);
        $this->assertSame(68.19, $steam['amount']);
        $this->assertSame('2026-10-09', $steam['date']);
        $this->assertTrue($steam['corrected']);
    }

    public function test_matches_registered_purchases_including_combinations(): void
    {
        $lines = [
            ['index' => 0, 'date' => '2026-11-12', 'amount' => 49.99],
            ['index' => 1, 'date' => '2026-11-17', 'amount' => 14.04],
            ['index' => 2, 'date' => '2026-11-07', 'amount' => 39.29],
            ['index' => 3, 'date' => '2026-10-09', 'amount' => 68.19],
            ['index' => 4, 'date' => '2026-11-17', 'amount' => 30.00],
            ['index' => 5, 'date' => '2026-11-17', 'amount' => 17.00],
            ['index' => 6, 'date' => '2026-11-15', 'amount' => 12.90],
            ['index' => 7, 'date' => '2026-11-07', 'amount' => 17.45, 'alt' => 44.35],
        ];

        $matches = (new StatementMatcher)->match($lines, [
            ['id' => 'tim', 'date' => '2026-11-10', 'amount' => 49.99],
            ['id' => 'jogos', 'date' => '2026-11-17', 'amount' => 121.52],
            // Parcela: é uma cobrança só, nunca a soma de outras linhas (30 + 17 + 12,90 = 59,90).
            ['id' => 'mouse', 'date' => '2026-11-05', 'amount' => 59.90, 'combinable' => false],
            // Cadastrada pelo valor antes do estorno.
            ['id' => 'amazon', 'date' => '2026-11-07', 'amount' => 44.35],
        ]);

        $this->assertSame(['tim'], $matches[0]['ids']);
        $this->assertSame('exact', $matches[0]['confidence']);
        $this->assertSame('combined', $matches[1]['confidence']);
        $this->assertSame([1, 2, 3], $matches[3]['group']);
        $this->assertSame(['amazon'], $matches[7]['ids']);
        $this->assertArrayNotHasKey(4, $matches);
        $this->assertArrayNotHasKey(6, $matches);
    }

    public function test_suggests_names_and_uses_learned_rules(): void
    {
        $suggester = new MerchantSuggester;

        $this->assertSame('iFood · Denise Pinheiro de', $suggester->suggest('IFD DENISE PINHEIRO DE', [])['name']);
        $this->assertSame(['ifood'], $suggester->suggest('IFD iFood', [])['tags']);
        $this->assertSame('Amazon', $suggester->suggest('AMAZONMKTPLC MSANTOSUT', [])['name']);
        $this->assertSame('TIM', $suggester->suggest('TIM 11999990000', [])['name']);
        $this->assertSame('Drogaria Sofia', $suggester->suggest('DROGARIA SOFIA', [])['name']);

        $rules = [
            'DROGARIA SOFIA' => ['name' => 'Farmácia', 'category_id' => 'cat-saude', 'tags' => []],
            'brand:ifood' => ['name' => 'iFood', 'category_id' => 'cat-comida', 'tags' => ['ifood']],
        ];

        $drogaria = $suggester->suggest('DROGARIA SOFIA', $rules);
        $this->assertSame('Farmácia', $drogaria['name']);
        $this->assertSame('cat-saude', $drogaria['category_id']);
        $this->assertTrue($drogaria['learned']);

        // Marca aprendida vale para outra loja do iFood.
        $this->assertSame('cat-comida', $suggester->suggest('IFD E F REIS LTDA', $rules)['category_id']);
    }
}
