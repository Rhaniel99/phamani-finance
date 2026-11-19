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
}
