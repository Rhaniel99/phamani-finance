<?php

namespace App\Services\Import;

/**
 * Sugere nome, categoria e tags para uma linha do extrato.
 *
 * Ordem: regra do usuário para essa loja → regra do usuário para a marca (ex.: tudo do iFood) →
 * marcas conhecidas → descrição limpa (sem prefixo da maquininha, em "Título").
 * As regras são aprendidas ao lançar uma importação.
 */
class MerchantSuggester
{
    /**
     * Marcas conhecidas: padrão na descrição → [marca, nome, tags].
     *
     * @var list<array{string, string, string, list<string>}>
     */
    private const BRANDS = [
        ['/^(?:IFD|IFOODCOM|IFOOD)\b/', 'ifood', 'iFood', ['ifood']],
        ['/^99FOOD\b/', '99food', '99Food', ['99food']],
        ['/^99APP\b|^99 ?TAXI|^99POP/', '99app', '99App', ['99']],
        ['/^UBER ?\*? ?EATS/', 'ubereats', 'Uber Eats', ['uber']],
        ['/^UBER\b/', 'uber', 'Uber', ['uber']],
        ['/AMAZON|AMZN/', 'amazon', 'Amazon', ['amazon']],
        ['/ALIEXPRESS/', 'aliexpress', 'AliExpress', ['aliexpress']],
        ['/SHOPEE/', 'shopee', 'Shopee', ['shopee']],
        ['/MERCADO ?LIVRE|^MERCADOLIVRE|^MLIVRE/', 'mercadolivre', 'Mercado Livre', ['mercado livre']],
        ['/EPIC ?GAMES/', 'epicgames', 'Epic Games', ['jogos']],
        ['/\bSTEAM\b/', 'steam', 'Steam', ['jogos']],
        ['/NETFLIX/', 'netflix', 'Netflix', ['assinatura']],
        ['/SPOTIFY/', 'spotify', 'Spotify', ['assinatura']],
        ['/GOOGLE/', 'google', 'Google', []],
        ['/^TIM\b/', 'tim', 'TIM', []],
    ];

    /** Prefixos de adquirente/maquininha que não fazem parte do nome. */
    private const PREFIXES = '/^(?:DL|EC|MP|EBN|PG|PAG|PAGSEGURO|MTD|IFD|IFOODCOM|SUMUP|SUM|STONE|CIELO|PAYPAL|PP|GETNET|ZP|ZOOP|LV|DM|PIC|PICPAY)\s*\*?\s+/';

    /**
     * @param  array<string, array{name: string, category_id: string|null, tags: list<string>}>  $rules  por chave
     * @return array{key: string, brand: string|null, name: string, category_id: string|null, tags: list<string>, learned: bool}
     */
    public function suggest(string $description, array $rules): array
    {
        $key = $this->key($description);
        $brand = $this->brand($key);

        if (isset($rules[$key])) {
            return ['key' => $key, 'brand' => $brand[0] ?? null, ...$rules[$key], 'learned' => true];
        }

        $name = $this->prettyName($description, $brand);

        if ($brand !== null && isset($rules['brand:'.$brand[0]])) {
            $rule = $rules['brand:'.$brand[0]];

            return [
                'key' => $key,
                'brand' => $brand[0],
                'name' => $name,
                'category_id' => $rule['category_id'],
                'tags' => $rule['tags'],
                'learned' => true,
            ];
        }

        return [
            'key' => $key,
            'brand' => $brand[0] ?? null,
            'name' => $name,
            'category_id' => null,
            'tags' => $brand[2] ?? [],
            'learned' => false,
        ];
    }

    /**
     * Chave da loja: maiúsculas, sem acento, sem números longos (telefone, pedido), espaços simples.
     */
    public function key(string $description): string
    {
        $ascii = (string) (iconv('UTF-8', 'ASCII//TRANSLIT//IGNORE', $description) ?: $description);
        $upper = strtoupper($ascii);
        $upper = preg_replace('/\d{3,}/', ' ', $upper) ?? $upper;
        $upper = preg_replace('/[^A-Z0-9]+/', ' ', $upper) ?? $upper;

        return trim(preg_replace('/\s+/', ' ', $upper) ?? $upper);
    }

    /**
     * @return array{string, string, list<string>}|null [marca, nome, tags]
     */
    public function brand(string $key): ?array
    {
        foreach (self::BRANDS as [$pattern, $brand, $name, $tags]) {
            if (preg_match($pattern, $key)) {
                return [$brand, $name, $tags];
            }
        }

        return null;
    }

    /**
     * @param  array{string, string, list<string>}|null  $brand
     */
    private function prettyName(string $description, ?array $brand): string
    {
        $key = $this->key($description);
        $rest = trim(preg_replace(self::PREFIXES, '', $key.' ') ?? $key);

        if ($brand !== null) {
            // "IFD DENISE PINHEIRO DE" → "iFood · Denise Pinheiro De"; "IFD iFood" → "iFood".
            $detail = trim(preg_replace('/^(?:'.preg_quote(strtoupper($brand[1]), '/').'|'.preg_quote(strtoupper($brand[0]), '/').')\b/', '', $rest) ?? '');
            $detail = trim(preg_replace('/\b(?:IFOOD|AGENCIA DE R|AGENCIA DER|AGENCIA|BR|COM|MKTPLC|MARKETPLACE)\b/', '', $detail) ?? '');
            $detail = $this->title($detail);

            return $detail !== '' && in_array($brand[0], ['ifood', '99food', 'shopee', 'ubereats'], true)
                ? $brand[1].' · '.$detail
                : $brand[1];
        }

        return $this->title($rest !== '' ? $rest : $key);
    }

    private function title(string $text): string
    {
        $words = array_filter(explode(' ', mb_strtolower(trim($text))));
        $small = ['de', 'da', 'do', 'das', 'dos', 'e'];

        $out = [];
        foreach (array_values($words) as $i => $word) {
            $out[] = $i > 0 && in_array($word, $small, true) ? $word : mb_convert_case($word, MB_CASE_TITLE);
        }

        return implode(' ', $out);
    }
}
