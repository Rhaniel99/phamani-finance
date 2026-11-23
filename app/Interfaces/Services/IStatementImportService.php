<?php

namespace App\Interfaces\Services;

use App\DTOs\Import\AcceptImportData;
use App\Models\Account;
use App\Models\StatementImport;
use Illuminate\Http\UploadedFile;

interface IStatementImportService
{
    /**
     * Guarda os arquivos e agenda o OCR (roda depois da resposta; a tela acompanha o progresso).
     *
     * @param  list<UploadedFile>  $files
     */
    public function start(string $userId, Account $card, array $files): StatementImport;

    /**
     * OCR + leitura do extrato. Atualiza progress/stage; termina em "ready" ou "failed".
     * Os arquivos enviados são apagados no fim, dê certo ou não.
     */
    public function process(StatementImport $import): void;

    /**
     * Dados da tela de revisão para a fatura escolhida (Y-m-d; null = a fatura da data do extrato):
     * linhas com sugestão (nome/categoria/tags) e ligação com o que já está cadastrado.
     *
     * @return array<string, mixed>
     */
    public function review(StatementImport $import, ?string $reference): array;

    /**
     * Lança as linhas aceitas no cartão (já conferidas), marca as já cadastradas como conferidas
     * e aprende as lojas. Devolve quantas transações foram criadas.
     */
    public function accept(StatementImport $import, AcceptImportData $data): int;

    /** Descarta a importação (e os arquivos, se ainda existirem). */
    public function discard(StatementImport $import): void;
}
