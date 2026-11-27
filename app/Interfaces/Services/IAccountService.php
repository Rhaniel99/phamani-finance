<?php

namespace App\Interfaces\Services;

use App\DTOs\Account\StoreAccountData;
use App\DTOs\Account\UpdateAccountData;
use App\Models\Account;
use Illuminate\Database\Eloquent\Collection;

interface IAccountService
{
    /**
     * Contas do usuário. Cartões vêm com `card` (limite, usado, disponível e fatura atual).
     */
    public function listForUser(string $userId): Collection;

    public function create(string $userId, StoreAccountData $dto): Account;

    /**
     * Atualiza a conta; se mudar fechamento/vencimento do cartão, reorganiza as faturas não pagas.
     */
    public function update(Account $account, UpdateAccountData $dto): Account;

    /**
     * Cria a conta padrão ("Carteira") de um usuário recém-cadastrado.
     */
    public function createDefaultForUser(string $userId): Account;

    /**
     * O que some junto com a conta (para a confirmação mostrar antes).
     *
     * @return array{transactions: int, installments: int, recurring: int, invoices: int, paid_invoices: int, shared: int, mirrors: int, balance: float, is_last: bool}
     */
    public function deletionImpact(Account $account): array;

    /**
     * Exclui a conta de vez, com tudo que é dela: transações (pelo mesmo caminho da exclusão
     * normal, então divisões, cópias de quem aceitou e reembolsos recebidos são desfeitos),
     * parcelamentos, recorrências, faturas e importações. Não dá para desfazer.
     * Não exclui a última conta que não é cartão.
     */
    public function delete(Account $account): void;
}
