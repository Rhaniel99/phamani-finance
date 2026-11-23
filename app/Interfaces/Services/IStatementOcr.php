<?php

namespace App\Interfaces\Services;

/**
 * OCR de extratos (PDF ou prints). Lê a imagem "faixa por faixa" (cada linha da tabela),
 * o que dá o progresso real e evita que uma linha seja cortada entre duas páginas.
 *
 * Uma instância por importação: reread() usa as imagens carregadas no read().
 */
interface IStatementOcr
{
    /**
     * @param  list<string>  $paths  PDFs e/ou imagens (png, jpg, webp)
     * @param  callable(int, int): void  $progress  ($feitas, $total)
     * @return list<string> texto de cada faixa, de cima para baixo
     */
    public function read(array $paths, callable $progress): array;

    /**
     * Relê algumas faixas com outra ampliação (segunda opinião quando o total não bate).
     *
     * @param  list<int>  $bands
     * @return array<int, string>
     */
    public function reread(array $bands, float $scale): array;

    /** Apaga os arquivos temporários. */
    public function cleanup(): void;
}
