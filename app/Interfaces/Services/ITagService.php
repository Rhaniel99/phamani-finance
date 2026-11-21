<?php

namespace App\Interfaces\Services;

use App\Models\Tag;
use App\Models\Transaction;
use Illuminate\Support\Collection;

/**
 * Tags livres das transações. Pessoais de cada usuário; comparação sem maiúsculas/acentos.
 */
interface ITagService
{
    /**
     * Tags do usuário com quantas transações cada uma tem.
     *
     * @return Collection<int, Tag>
     */
    public function listForUser(string $userId): Collection;

    /**
     * Define as tags das transações (cria as que não existem).
     *
     * @param  iterable<Transaction>  $transactions
     * @param  list<string>  $names
     */
    public function syncFor(iterable $transactions, string $userId, array $names): void;

    /** Copia as tags de uma ocorrência para a próxima (recorrências). */
    public function copy(Transaction $from, Transaction $to): void;

    /** Renomeia; se já existir outra com o mesmo nome, as duas viram uma só. */
    public function rename(Tag $tag, string $name): Tag;

    public function delete(Tag $tag): void;

    /** Nome normalizado usado na comparação ("Ifood" = "iFood" = "ifood"). */
    public function slug(string $name): string;
}
